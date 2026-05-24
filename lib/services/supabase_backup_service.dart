import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseBackupConfig {
  const SupabaseBackupConfig({
    required this.projectUrl,
    required this.anonKey,
    required this.bucket,
  });

  final String projectUrl;
  final String anonKey;
  final String bucket;

  bool get isComplete =>
      projectUrl.trim().isNotEmpty &&
      anonKey.trim().isNotEmpty &&
      bucket.trim().isNotEmpty;
}

class SupabaseBackupResult {
  const SupabaseBackupResult({required this.objectPath, required this.bytes});

  final String objectPath;
  final int bytes;
}

class SupabaseBackupService {
  const SupabaseBackupService();

  Future<SupabaseBackupResult> uploadBackup({
    required SupabaseBackupConfig config,
    required String backupPath,
    required String storeName,
  }) async {
    final file = File(backupPath);
    if (!await file.exists()) {
      throw Exception('Backup file was not found.');
    }

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw Exception('Backup file is empty.');
    }

    final normalizedUrl = _normalizeProjectUrl(config.projectUrl);
    final bucket = _sanitizePathSegment(config.bucket, fallback: 'backupfiles');
    final store = _sanitizePathSegment(storeName, fallback: 'store');
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    final extension = p.extension(backupPath).isEmpty
        ? '.posbackup'
        : p.extension(backupPath);
    final objectPath = '$store/pos_backup_$timestamp$extension';

    final client = SupabaseClient(normalizedUrl, config.anonKey.trim());
    try {
      await client.storage
          .from(bucket)
          .uploadBinary(
            objectPath,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'application/zip',
              upsert: false,
            ),
          );
      return SupabaseBackupResult(objectPath: objectPath, bytes: bytes.length);
    } on StorageException catch (e) {
      throw Exception(_uploadErrorMessage(e.statusCode, e.message, bucket));
    }
  }

  String _normalizeProjectUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) throw Exception('Supabase URL is required.');
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw Exception('Enter a valid Supabase project URL.');
    }
    return trimmed.replaceFirst(RegExp(r'/+$'), '');
  }

  String _sanitizePathSegment(String value, {required String fallback}) {
    final sanitized = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return sanitized.isEmpty ? fallback : sanitized;
  }

  String _uploadErrorMessage(Object? statusCode, String body, String bucket) {
    final code = statusCode?.toString();
    if (code == '401' || code == '403') {
      return 'Supabase rejected the backup. Check the anon key and Storage policy for "$bucket".';
    }
    if (code == '404') {
      return 'Supabase bucket "$bucket" was not found. Create it in Supabase Storage first.';
    }
    if (code == '409') {
      return 'A backup with the same name already exists. Try again.';
    }
    return 'Supabase upload failed (${code ?? 'unknown'}): $body';
  }
}
