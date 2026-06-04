import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:pos_app/services/env_config.dart';
import 'package:pos_app/services/license_activation_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseSyncService {
  const SupabaseSyncService();

  static const cloudImagePrefix = 'supabase-storage://';
  static const _imageDeleteFunction = 'pos-image-delete';
  static const _syncApplyFunction = 'pos-sync-apply';

  Future<List<SyncUploadResult>> uploadEvents(
    List<Map<String, Object?>> events,
  ) async {
    if (events.isEmpty) return const [];

    final client = await _authenticatedClient();
    final storeId = await _activeStoreId();
    final results = <SyncUploadResult>[];
    for (final event in events) {
      results.add(await _uploadMirrorRow(client, event, storeId));
    }

    await _cleanupUnusedSyncedImages(client: client, storeId: storeId);
    return results;
  }

  Future<Map<String, List<Map<String, dynamic>>>>
  downloadStoreSnapshot() async {
    final client = await _authenticatedClient();
    final storeId = await _activeStoreId();
    final snapshot = <String, List<Map<String, dynamic>>>{};

    for (final table in const [
      'products',
      'users',
      'sales',
      'shifts',
      'shift_readings',
      'audit_logs',
    ]) {
      final rows = await client
          .from(table)
          .select()
          .eq('store_id', storeId)
          .order('local_id', ascending: true);
      snapshot[table] = rows
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList(growable: false);
    }

    return snapshot;
  }

  Future<int> deleteLegacySalesImageFolder() async {
    final client = await _authenticatedClient();
    final storeId = await _activeStoreId();
    final folderPath = '$storeId/sync_images/sales';
    final bucket = client.storage.from(_storageBucket);

    final objects = await bucket.list(path: folderPath);
    final paths = objects
        .map((object) => object.name)
        .where((name) => name.isNotEmpty)
        .map((name) => '$folderPath/$name')
        .toList(growable: false);
    if (paths.isEmpty) return 0;

    await bucket.remove(paths);
    return paths.length;
  }

  Future<SupabaseClient> _authenticatedClient() async {
    try {
      final client = Supabase.instance.client;
      final cloudSignedIn = await LicenseActivationService.instance
          .ensureCloudSyncSignedIn();
      if (!cloudSignedIn || client.auth.currentSession == null) {
        throw Exception(
          'Cloud sync is not connected. Activate or restore a license while online.',
        );
      }
      return client;
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Supabase is not configured.');
    }
  }

  Future<String> _activeStoreId() async {
    final activation = await LicenseActivationService.instance
        .readLocalActivation();
    final storeId = activation?.storeId.trim() ?? '';
    if (storeId.isEmpty) {
      throw Exception('Activate this device before syncing POS data.');
    }
    return storeId;
  }

  Future<SyncUploadResult> _uploadMirrorRow(
    SupabaseClient client,
    Map<String, Object?> event,
    String storeId,
  ) async {
    final sourceTable = event['table_name']?.toString();
    final targetTable = _targetTable(sourceTable);
    if (targetTable == null) {
      return SyncUploadResult.applied(
        queueKey: event['queue_key']?.toString() ?? '',
        revision: (event['cloud_revision'] as num?)?.toInt() ?? 0,
      );
    }

    final localId = event['local_id']?.toString();
    if (localId == null || localId.isEmpty) {
      throw Exception('Sync event local id is missing.');
    }

    final operation = event['operation']?.toString() ?? 'upsert';
    Map<String, Object?>? mirrorRow;
    if (operation == 'delete') {
      if (sourceTable == 'products') {
        await _requestProductImageDeletion(
          client: client,
          storeId: storeId,
          localId: localId,
          imagePath: _payloadImagePath(event),
          syncEventId: '$storeId:${event['queue_key']?.toString()}',
        );
      }
    } else {
      mirrorRow = await _toMirrorRow(client, event, storeId);
    }

    return _applySyncEvent(
      client: client,
      storeId: storeId,
      event: event,
      mirrorRow: mirrorRow,
    );
  }

  Future<SyncUploadResult> _applySyncEvent({
    required SupabaseClient client,
    required String storeId,
    required Map<String, Object?> event,
    required Map<String, Object?>? mirrorRow,
  }) async {
    final accessToken = client.auth.currentSession?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw Exception('Cloud sync is not connected.');
    }
    final queueKey = event['queue_key']?.toString() ?? '';
    final payload = _decodePayload(event['payload']?.toString() ?? '{}');
    final response = await http.post(
      _functionUrl(_syncApplyFunction),
      headers: {
        'apikey': EnvConfig.supabaseAnonKey,
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'storeId': storeId,
        'queueKey': queueKey,
        'localQueueId': event['id'],
        'tableName': event['table_name']?.toString(),
        'localId': event['local_id']?.toString(),
        'operation': event['operation']?.toString(),
        'payload': payload is Map ? payload : <String, Object?>{},
        'mirrorRow': mirrorRow,
        'baseRevision': (event['base_revision'] as num?)?.toInt() ?? 0,
        'createdAt': event['created_at']?.toString(),
        'updatedAt': event['updated_at']?.toString(),
      }),
    );

    final body = _decodePayload(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final result = body is Map ? body : const <String, Object?>{};
      return SyncUploadResult.applied(
        queueKey: queueKey,
        revision: (result['revision'] as num?)?.toInt() ?? 0,
      );
    }
    if (response.statusCode == 409 &&
        body is Map &&
        body['code']?.toString() == 'SYNC_CONFLICT') {
      return SyncUploadResult.conflict(
        queueKey: queueKey,
        message: body['error']?.toString() ?? 'Cloud row changed.',
        revision: (body['currentRevision'] as num?)?.toInt() ?? 0,
      );
    }
    final message = body is Map
        ? body['error']?.toString() ?? response.body
        : response.body;
    throw Exception('Cloud sync apply failed: $message');
  }

  Future<void> _cleanupUnusedSyncedImages({
    required SupabaseClient client,
    required String storeId,
  }) async {
    try {
      await _invokeImageDeleteFunction(client, {
        'operation': 'cleanup_unused_images',
        'storeId': storeId,
        'bucket': _storageBucket,
      });
    } catch (_) {
      // Orphan cleanup should not block POS data sync; product delete events still
      // call the same function in a required path before their mirror rows delete.
    }
  }

  Future<void> _requestProductImageDeletion({
    required SupabaseClient client,
    required String storeId,
    required String localId,
    required String? imagePath,
    required String? syncEventId,
  }) async {
    await _invokeImageDeleteFunction(client, {
      'operation': 'delete_product_image',
      'storeId': storeId,
      'localId': localId,
      'bucket': _storageBucket,
      'imagePath': imagePath,
      'syncEventId': syncEventId,
    });
  }

  Future<void> _invokeImageDeleteFunction(
    SupabaseClient client,
    Map<String, Object?> body,
  ) async {
    final functionUrl = _functionUrl(_imageDeleteFunction);
    final accessToken = client.auth.currentSession?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw Exception('Cloud sync is not connected.');
    }

    final response = await http.post(
      functionUrl,
      headers: {
        'apikey': EnvConfig.supabaseAnonKey,
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) return;

    var message = response.body.trim();
    var code = '';
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        code = decoded['code']?.toString() ?? '';
        if (decoded['error'] != null) {
          message = decoded['error'].toString();
        } else if (decoded['message'] != null) {
          message = decoded['message'].toString();
        }
      }
    } catch (_) {
      // Keep the raw response body.
    }
    if (response.statusCode == 404 || code == 'NOT_FOUND') {
      throw Exception(
        'Image delete function "$_imageDeleteFunction" is not deployed. '
        'Deploy supabase/functions/$_imageDeleteFunction before syncing product image deletes.',
      );
    }
    throw Exception('Image delete function failed: $message');
  }

  Uri _functionUrl(String functionName) {
    final projectUrl = EnvConfig.supabaseUrl.trim();
    if (projectUrl.isEmpty) throw Exception('Supabase is not configured.');
    return Uri.parse('$projectUrl/functions/v1/$functionName');
  }

  String? _targetTable(String? sourceTable) {
    switch (sourceTable) {
      case 'products':
        return 'products';
      case 'sales':
        return 'sales';
      case 'shifts':
        return 'shifts';
      case 'shift_readings':
        return 'shift_readings';
      case 'users':
        return 'users';
      case 'audit_logs':
        return 'audit_logs';
      default:
        return null;
    }
  }

  String? _payloadImagePath(Map<String, Object?> event) {
    final payload = _decodePayload(event['payload']?.toString() ?? '{}');
    if (payload is! Map) return null;
    return payload['image_url']?.toString();
  }

  Future<Map<String, Object?>> _toMirrorRow(
    SupabaseClient client,
    Map<String, Object?> event,
    String storeId,
  ) async {
    final payloadText = event['payload']?.toString() ?? '{}';
    final payload = _decodePayload(payloadText);

    final payloadMap = payload is Map
        ? Map<String, Object?>.from(payload)
        : <String, Object?>{'raw': payloadText};
    payloadMap.remove('id');

    final sourceTable = event['table_name']?.toString();
    if (sourceTable == 'sales') {
      final localProductId = payloadMap.remove('product_id');
      if (localProductId != null) {
        payloadMap['local_product_id'] = localProductId.toString();
      }
      final localVoidedBy = payloadMap.remove('voided_by');
      if (localVoidedBy != null) {
        payloadMap['local_voided_by'] = localVoidedBy.toString();
      }
      payloadMap.remove('image_url');
    } else if (sourceTable == 'users') {
      final email = payloadMap['email']?.toString().trim() ?? '';
      if (email.isEmpty) {
        final username = payloadMap['username']?.toString().trim();
        final localId = event['local_id']?.toString().trim();
        final emailName = (username == null || username.isEmpty)
            ? 'user-${localId == null || localId.isEmpty ? 'unknown' : localId}'
            : username.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
        payloadMap['email'] = '$emailName@local.pos';
      }
    } else if (sourceTable == 'audit_logs') {
      final localUser = payloadMap.remove('user');
      if (localUser != null) {
        payloadMap['local_user'] = localUser.toString();
      }
    }

    final imageSourceTable = sourceTable;
    if (imageSourceTable == 'products') {
      payloadMap['pending_delete'] = _truthy(payloadMap['pending_delete']);
      payloadMap['image_url'] = await _uploadLocalImageIfAvailable(
        client: client,
        storeId: storeId,
        sourceTable: imageSourceTable!,
        localId: event['local_id']?.toString(),
        imagePath: payloadMap['image_url']?.toString(),
      );
    }

    return {
      ...payloadMap,
      'store_id': storeId,
      'local_id': event['local_id']?.toString(),
      'source_table': sourceTable,
      'sync_event_id': '$storeId:${event['queue_key']?.toString()}',
      'operation': event['operation']?.toString(),
      'payload': payloadMap,
      'local_updated_at': event['updated_at']?.toString(),
      'cloud_updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  bool _truthy(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return value?.toString().toLowerCase() == 'true';
  }

  Object _decodePayload(String payloadText) {
    try {
      return jsonDecode(payloadText);
    } catch (_) {
      return {'raw': payloadText};
    }
  }

  Future<String?> _uploadLocalImageIfAvailable({
    required SupabaseClient client,
    required String storeId,
    required String sourceTable,
    required String? localId,
    required String? imagePath,
  }) async {
    final trimmedPath = imagePath?.trim() ?? '';
    if (trimmedPath.isEmpty) return null;
    if (trimmedPath.startsWith('http') ||
        trimmedPath.startsWith(cloudImagePrefix)) {
      return trimmedPath;
    }
    if (localId == null || localId.isEmpty) return trimmedPath;

    final imageFile = File(trimmedPath);
    if (!await imageFile.exists()) return null;

    final extension = _imageExtension(trimmedPath);
    final objectPath = '$storeId/sync_images/$sourceTable/$localId$extension';
    final bucket = _storageBucket;

    await client.storage
        .from(bucket)
        .uploadBinary(
          objectPath,
          await imageFile.readAsBytes(),
          fileOptions: FileOptions(
            contentType: _contentType(extension),
            upsert: true,
          ),
        );

    return '$cloudImagePrefix$bucket/$objectPath';
  }

  Future<Uint8List?> downloadCloudImage(String? imageReference) async {
    final parsed = _parseCloudImageReference(imageReference);
    if (parsed == null) return null;

    final client = await _authenticatedClient();
    return client.storage.from(parsed.bucket).download(parsed.objectPath);
  }

  String? cloudImageFileName(String? imageReference) {
    final parsed = _parseCloudImageReference(imageReference);
    if (parsed == null) return null;
    return p.basename(parsed.objectPath);
  }

  _CloudImageReference? _parseCloudImageReference(String? imageReference) {
    final trimmed = imageReference?.trim() ?? '';
    if (!trimmed.startsWith(cloudImagePrefix)) return null;

    final reference = trimmed.substring(cloudImagePrefix.length);
    final separatorIndex = reference.indexOf('/');
    if (separatorIndex <= 0 || separatorIndex == reference.length - 1) {
      return null;
    }

    return _CloudImageReference(
      bucket: reference.substring(0, separatorIndex),
      objectPath: reference.substring(separatorIndex + 1),
    );
  }

  String get _storageBucket {
    final bucket = EnvConfig.supabaseBackupBucket.trim();
    return bucket.isEmpty ? 'backupfiles' : bucket;
  }

  String _imageExtension(String imagePath) {
    final extension = p.extension(imagePath).toLowerCase();
    return switch (extension) {
      '.png' || '.jpg' || '.jpeg' || '.webp' || '.gif' => extension,
      _ => '.jpg',
    };
  }

  String _contentType(String extension) {
    return switch (extension) {
      '.png' => 'image/png',
      '.webp' => 'image/webp',
      '.gif' => 'image/gif',
      _ => 'image/jpeg',
    };
  }
}

class _CloudImageReference {
  const _CloudImageReference({required this.bucket, required this.objectPath});

  final String bucket;
  final String objectPath;
}

class SyncUploadResult {
  const SyncUploadResult._({
    required this.queueKey,
    required this.revision,
    required this.conflicted,
    this.message,
  });

  factory SyncUploadResult.applied({
    required String queueKey,
    required int revision,
  }) {
    return SyncUploadResult._(
      queueKey: queueKey,
      revision: revision,
      conflicted: false,
    );
  }

  factory SyncUploadResult.conflict({
    required String queueKey,
    required int revision,
    required String message,
  }) {
    return SyncUploadResult._(
      queueKey: queueKey,
      revision: revision,
      conflicted: true,
      message: message,
    );
  }

  final String queueKey;
  final int revision;
  final bool conflicted;
  final String? message;
}
