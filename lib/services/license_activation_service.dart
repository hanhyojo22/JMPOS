import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'device_identity_service.dart';
import 'env_config.dart';

class LicenseActivation {
  const LicenseActivation({
    required this.licenseKey,
    required this.installationId,
    required this.storeId,
    required this.activationToken,
    required this.lastVerifiedAt,
    this.storeName,
  });

  final String licenseKey;
  final String installationId;
  final String storeId;
  final String activationToken;
  final DateTime lastVerifiedAt;
  final String? storeName;
}

class LicenseActivationService {
  LicenseActivationService._();

  static final LicenseActivationService instance =
      LicenseActivationService._();

  static const _secureStorage = FlutterSecureStorage();
  static const _licenseKey = 'license_key';
  static const _installationIdKey = 'installation_id';
  static const _storeIdKey = 'store_id';
  static const _activationTokenKey = 'activation_token';
  static const _lastVerifiedAtKey = 'last_verified_at';
  static const _storeNameKey = 'store_name';
  static const _cloudEmailKey = 'cloud_sync_email';
  static const _cloudPasswordKey = 'cloud_sync_password';
  static const _offlineGracePeriod = Duration(days: 14);

  Future<String> getOrCreateInstallationId() async {
    final stableDeviceId = await DeviceIdentityService.stableDeviceId();
    if (stableDeviceId != null && stableDeviceId.isNotEmpty) {
      await _secureStorage.write(
        key: _installationIdKey,
        value: stableDeviceId,
      );
      return stableDeviceId;
    }

    final existing = await _secureStorage.read(key: _installationIdKey);
    if (existing != null && existing.trim().isNotEmpty) {
      return existing.trim();
    }

    final installationId = _createUuidV4();
    await _secureStorage.write(
      key: _installationIdKey,
      value: installationId,
    );
    return installationId;
  }

  Future<LicenseActivation?> readLocalActivation() async {
    final values = await Future.wait([
      _secureStorage.read(key: _licenseKey),
      _secureStorage.read(key: _installationIdKey),
      _secureStorage.read(key: _storeIdKey),
      _secureStorage.read(key: _activationTokenKey),
      _secureStorage.read(key: _lastVerifiedAtKey),
      _secureStorage.read(key: _storeNameKey),
    ]);

    final licenseKey = values[0]?.trim() ?? '';
    final installationId = values[1]?.trim() ?? '';
    final storeId = values[2]?.trim() ?? '';
    final activationToken = values[3]?.trim() ?? '';
    final lastVerifiedAt = DateTime.tryParse(values[4]?.trim() ?? '');

    if (installationId.isEmpty ||
        storeId.isEmpty ||
        activationToken.isEmpty ||
        lastVerifiedAt == null) {
      return null;
    }

    return LicenseActivation(
      licenseKey: licenseKey,
      installationId: installationId,
      storeId: storeId,
      activationToken: activationToken,
      lastVerifiedAt: lastVerifiedAt,
      storeName: values[5]?.trim(),
    );
  }

  Future<bool> hasValidLocalActivation() async {
    final activation = await readLocalActivation();
    if (activation == null) return false;
    return DateTime.now().difference(activation.lastVerifiedAt) <=
        _offlineGracePeriod;
  }

  Future<LicenseActivation?> recoverActivation() async {
    _ensureConfigured();
    final installationId = await getOrCreateInstallationId();
    final existingToken = await _secureStorage.read(key: _activationTokenKey);

    final response = await _postFunction(
      'validate-license',
      {
        'installationId': installationId,
        if (existingToken != null && existingToken.trim().isNotEmpty)
          'activationToken': existingToken.trim(),
      },
    );

    if (response == null) return null;
    await saveActivation(
      licenseKey: response['licenseKey']?.toString() ?? '',
      installationId: installationId,
      storeId: response['storeId']?.toString() ?? '',
      activationToken: response['activationToken']?.toString() ?? '',
      storeName: response['storeName']?.toString(),
    );
    return readLocalActivation();
  }

  Future<LicenseCheckResult> checkLicenseKey(String licenseKey) async {
    _ensureConfigured();
    final cleanedLicense = _sanitizeLicenseKey(licenseKey);
    if (cleanedLicense.isEmpty) {
      throw Exception('Enter a valid license code.');
    }

    final installationId = await getOrCreateInstallationId();
    final response = await _postFunction(
      'validate-license',
      {
        'installationId': installationId,
        'licenseKey': cleanedLicense,
      },
    );

    if (response == null) {
      throw Exception('License check returned an empty response.');
    }

    final activated = response['activated'] == true;
    if (activated) {
      await saveActivation(
        licenseKey: response['licenseKey']?.toString() ?? cleanedLicense,
        installationId: installationId,
        storeId: response['storeId']?.toString() ?? '',
        activationToken: response['activationToken']?.toString() ?? '',
        storeName: response['storeName']?.toString(),
      );
    }

    return LicenseCheckResult(
      licenseKey: cleanedLicense,
      exists: response['licenseExists'] == true,
      activated: activated,
      restored: response['restored'] == true,
      restoreAvailable: response['restoreAvailable'] == true,
      storeId: response['storeId']?.toString(),
      storeName: response['storeName']?.toString(),
      message: response['message']?.toString(),
    );
  }

  Future<LicenseActivation> activateStore({
    required String licenseKey,
    required String storeName,
    required String ownerName,
    required String email,
    required String password,
  }) async {
    _ensureConfigured();
    final installationId = await getOrCreateInstallationId();
    final response = await _postFunction(
      'register-store-v2',
      {
        'storeName': storeName,
        'ownerName': ownerName,
        'email': email,
        'password': password,
        'inviteCode': licenseKey,
        'installationId': installationId,
      },
    );

    if (response == null) {
      throw Exception('Cloud registration returned an empty response.');
    }

    final storeId = response['storeId']?.toString() ?? '';
    final activationToken = response['activationToken']?.toString() ?? '';
    if (storeId.isEmpty || activationToken.isEmpty) {
      throw Exception('Cloud registration did not return activation data.');
    }

    await saveActivation(
      licenseKey: licenseKey,
      installationId: installationId,
      storeId: storeId,
      activationToken: activationToken,
      storeName: response['storeName']?.toString() ?? storeName,
    );

    final activation = await readLocalActivation();
    if (activation == null) {
      throw Exception('Could not save local activation.');
    }
    await saveCloudSyncCredentials(email: email, password: password);
    await ensureCloudSyncSignedIn();
    return activation;
  }

  Future<void> saveCloudSyncCredentials({
    required String email,
    required String password,
  }) async {
    final cleanedEmail = email.trim().toLowerCase();
    if (cleanedEmail.isEmpty || password.isEmpty) return;

    await Future.wait([
      _secureStorage.write(key: _cloudEmailKey, value: cleanedEmail),
      _secureStorage.write(key: _cloudPasswordKey, value: password),
    ]);
  }

  Future<bool> ensureCloudSyncSignedIn() async {
    try {
      if (Supabase.instance.client.auth.currentSession != null) return true;

      final values = await Future.wait([
        _secureStorage.read(key: _cloudEmailKey),
        _secureStorage.read(key: _cloudPasswordKey),
      ]);
      final email = values[0]?.trim().toLowerCase() ?? '';
      final password = values[1] ?? '';
      if (email.isEmpty || password.isEmpty) return false;

      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return Supabase.instance.client.auth.currentSession != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> saveActivation({
    required String licenseKey,
    required String installationId,
    required String storeId,
    required String activationToken,
    String? storeName,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await Future.wait([
      if (licenseKey.trim().isNotEmpty)
        _secureStorage.write(key: _licenseKey, value: licenseKey),
      _secureStorage.write(key: _installationIdKey, value: installationId),
      _secureStorage.write(key: _storeIdKey, value: storeId),
      _secureStorage.write(key: _activationTokenKey, value: activationToken),
      _secureStorage.write(key: _lastVerifiedAtKey, value: now),
      if (storeName != null && storeName.trim().isNotEmpty)
        _secureStorage.write(key: _storeNameKey, value: storeName.trim()),
    ]);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storeIdKey, storeId);
    if (storeName != null && storeName.trim().isNotEmpty) {
      await prefs.setString(_storeNameKey, storeName.trim());
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    final cleanedEmail = email.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(cleanedEmail)) {
      throw Exception('Enter a valid email.');
    }
    try {
      final redirectUrl = EnvConfig.supabasePasswordResetRedirectUrl;
      await Supabase.instance.client.auth.resetPasswordForEmail(
        cleanedEmail,
        redirectTo: redirectUrl.isEmpty ? null : redirectUrl,
      );
    } catch (e) {
      throw Exception('Could not send password reset email. $e');
    }
  }

  Future<Map<String, dynamic>?> _postFunction(
    String functionName,
    Map<String, Object?> body,
  ) async {
    final response = await http.post(
      Uri.parse('${EnvConfig.supabaseUrl}/functions/v1/$functionName'),
      headers: {
        'apikey': EnvConfig.supabaseAnonKey,
        'Authorization': 'Bearer ${EnvConfig.supabaseAnonKey}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    final decoded = _decodeJson(response.body);
    if (response.statusCode == 404) return null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map && decoded['error'] != null
          ? decoded['error'].toString()
          : response.body;
      throw Exception('Cloud license check failed (${response.statusCode}): $message');
    }
    if (decoded is Map && decoded['error'] != null) {
      throw Exception(decoded['error'].toString());
    }
    return decoded is Map<String, dynamic>
        ? decoded
        : decoded is Map
            ? decoded.map((key, value) => MapEntry(key.toString(), value))
            : null;
  }

  Object? _decodeJson(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return body;
    }
  }

  void _ensureConfigured() {
    if (EnvConfig.supabaseUrl.isEmpty || EnvConfig.supabaseAnonKey.isEmpty) {
      throw Exception(
        'Supabase is not configured. Add SUPABASE_URL and SUPABASE_ANON_KEY to .env.',
      );
    }
  }

  String _sanitizeLicenseKey(String value) {
    final cleaned = value.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9_-]{4,40}$').hasMatch(cleaned)) return '';
    return cleaned;
  }

  String _createUuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0'));
    final value = hex.join();
    return [
      value.substring(0, 8),
      value.substring(8, 12),
      value.substring(12, 16),
      value.substring(16, 20),
      value.substring(20),
    ].join('-');
  }
}

class LicenseCheckResult {
  const LicenseCheckResult({
    required this.licenseKey,
    required this.exists,
    required this.activated,
    required this.restored,
    this.restoreAvailable = false,
    this.storeId,
    this.storeName,
    this.message,
  });

  final String licenseKey;
  final bool exists;
  final bool activated;
  final bool restored;
  final bool restoreAvailable;
  final String? storeId;
  final String? storeName;
  final String? message;
}
