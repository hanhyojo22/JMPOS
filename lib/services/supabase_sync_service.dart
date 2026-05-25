import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseSyncService {
  const SupabaseSyncService();

  Future<void> uploadEvents(List<Map<String, Object?>> events) async {
    if (events.isEmpty) return;

    final client = _authenticatedClient();
    final rows = events.map(_toSupabaseRow).toList(growable: false);
    await client.from('pos_sync_events').upsert(rows, onConflict: 'event_id');

    for (final event in events) {
      await _uploadMirrorRow(client, event);
    }
  }

  SupabaseClient _authenticatedClient() {
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentSession == null) {
        throw Exception('Sign in to Supabase Cloud Sync first.');
      }
      return client;
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Supabase is not configured.');
    }
  }

  Map<String, Object?> _toSupabaseRow(Map<String, Object?> event) {
    return {
      'event_id': event['queue_key']?.toString(),
      'local_queue_id': event['id'],
      'table_name': event['table_name']?.toString(),
      'local_id': event['local_id']?.toString(),
      'operation': event['operation']?.toString(),
      'payload': event['payload']?.toString(),
      'created_at': event['created_at']?.toString(),
      'updated_at': event['updated_at']?.toString(),
    };
  }

  Future<void> _uploadMirrorRow(
    SupabaseClient client,
    Map<String, Object?> event,
  ) async {
    final sourceTable = event['table_name']?.toString();
    final targetTable = _targetTable(sourceTable);
    if (targetTable == null) return;

    final localId = event['local_id']?.toString();
    if (localId == null || localId.isEmpty) return;

    final operation = event['operation']?.toString() ?? 'upsert';
    if (operation == 'delete') {
      await client.from(targetTable).delete().eq(
        _deleteColumn(sourceTable),
        _deleteValue(sourceTable, event) ?? localId,
      );
      return;
    }

    await client.from(targetTable).upsert(
      _toMirrorRow(event),
      onConflict: _conflictColumn(sourceTable),
    );
  }

  String? _targetTable(String? sourceTable) {
    switch (sourceTable) {
      case 'products':
        return 'products';
      case 'sales':
        return 'sales';
      case 'users':
        return 'users';
      case 'audit_logs':
        return 'audit_logs';
      default:
        return null;
    }
  }

  String _conflictColumn(String? sourceTable) {
    return 'local_id';
  }

  String _deleteColumn(String? sourceTable) {
    return 'local_id';
  }

  Object? _deleteValue(String? sourceTable, Map<String, Object?> event) {
    return null;
  }

  Map<String, Object?> _toMirrorRow(Map<String, Object?> event) {
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

    return {
      ...payloadMap,
      'local_id': event['local_id']?.toString(),
      'source_table': sourceTable,
      'sync_event_id': event['queue_key']?.toString(),
      'operation': event['operation']?.toString(),
      'payload': payload,
      'local_updated_at': event['updated_at']?.toString(),
      'cloud_updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Object _decodePayload(String payloadText) {
    try {
      return jsonDecode(payloadText);
    } catch (_) {
      return {'raw': payloadText};
    }
  }
}
