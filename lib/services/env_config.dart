import 'package:flutter/services.dart';

class EnvConfig {
  EnvConfig._();

  static const _supabaseUrlDefine = String.fromEnvironment('SUPABASE_URL');
  static const _supabaseAnonKeyDefine = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );
  static const _supabaseBackupBucketDefine = String.fromEnvironment(
    'SUPABASE_BACKUP_BUCKET',
    defaultValue: 'backupfiles',
  );

  static final Map<String, String> _values = {};

  static Future<void> load() async {
    try {
      final contents = await rootBundle.loadString('.env');
      _values
        ..clear()
        ..addAll(_parse(contents));
    } catch (_) {
      _values.clear();
    }
  }

  static String get supabaseUrl => _value('SUPABASE_URL', _supabaseUrlDefine);

  static String get supabaseAnonKey =>
      _value('SUPABASE_ANON_KEY', _supabaseAnonKeyDefine);

  static String get supabaseBackupBucket =>
      _value('SUPABASE_BACKUP_BUCKET', _supabaseBackupBucketDefine);

  static String _value(String key, String dartDefineValue) {
    final fromDartDefine = dartDefineValue.trim();
    if (fromDartDefine.isNotEmpty) return fromDartDefine;
    return (_values[key] ?? '').trim();
  }

  static Map<String, String> _parse(String contents) {
    final parsed = <String, String>{};

    for (final rawLine in contents.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      final separatorIndex = line.indexOf('=');
      if (separatorIndex <= 0) continue;

      final key = line.substring(0, separatorIndex).trim();
      final value = _unquote(line.substring(separatorIndex + 1).trim());
      if (key.isNotEmpty) parsed[key] = value;
    }

    return parsed;
  }

  static String _unquote(String value) {
    if (value.length < 2) return value;

    final first = value[0];
    final last = value[value.length - 1];
    if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
      return value.substring(1, value.length - 1);
    }

    return value;
  }
}
