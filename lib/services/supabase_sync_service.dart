import 'dart:convert';

import 'package:pos_app/services/env_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseSyncService {
  const SupabaseSyncService();

  Future<void> uploadEvents(List<Map<String, Object?>> events) async {
    if (events.isEmpty) return;

    final url = EnvConfig.supabaseUrl;
    final anonKey = EnvConfig.supabaseAnonKey;
    if (url.isEmpty || anonKey.isEmpty) {
      throw Exception('Supabase URL or anon key is missing.');
    }

    final client = SupabaseClient(url, anonKey);
    for (final event in events) {
      await _uploadMirrorRow(client, event);
    }
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
      await client.from(targetTable).delete().eq('local_id', localId);
      return;
    }

    await client
        .from(targetTable)
        .upsert(_toMirrorRow(event), onConflict: 'local_id');
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

  Map<String, Object?> _toMirrorRow(Map<String, Object?> event) {
    final payloadText = event['payload']?.toString() ?? '{}';
    Object payload;
    try {
      payload = jsonDecode(payloadText);
    } catch (_) {
      payload = {'raw': payloadText};
    }

    return {
      'local_id': event['local_id']?.toString(),
      'source_table': event['table_name']?.toString(),
      'sync_event_id': event['queue_key']?.toString(),
      'operation': event['operation']?.toString(),
      'payload': payload,
      'local_updated_at': event['updated_at']?.toString(),
      'cloud_updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }
}
