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
    this.licenseExpiresAt,
    this.licenseStatus = 'active',
  });

  final String licenseKey;
  final String installationId;
  final String storeId;
  final String activationToken;
  final DateTime lastVerifiedAt;
  final String? storeName;
  final DateTime? licenseExpiresAt;
  final String licenseStatus;

  bool get isExpired =>
      licenseExpiresAt != null && !licenseExpiresAt!.isAfter(DateTime.now());
  bool get isSuspended => licenseStatus == 'suspended';

  int? get daysRemaining {
    final expiry = licenseExpiresAt;
    if (expiry == null) return null;
    return expiry.difference(DateTime.now()).inDays.clamp(0, 999999);
  }
}

class LicenseDevice {
  const LicenseDevice({
    required this.id,
    required this.name,
    required this.isCurrent,
    required this.activatedAt,
    required this.lastSeenAt,
    this.revokedAt,
  });

  final String id;
  final String name;
  final bool isCurrent;
  final DateTime? activatedAt;
  final DateTime? lastSeenAt;
  final DateTime? revokedAt;

  bool get isRevoked => revokedAt != null;
}

class LicenseDeviceSummary {
  const LicenseDeviceSummary({
    required this.slotLimit,
    required this.activeDeviceCount,
    required this.devices,
  });

  final int slotLimit;
  final int activeDeviceCount;
  final List<LicenseDevice> devices;
}

class LicenseActivationService {
  LicenseActivationService._();

  static final LicenseActivationService instance = LicenseActivationService._();

  Future<LicenseActivation?>? _recoveryInFlight;

  static const _secureStorage = FlutterSecureStorage();
  static const _licenseKey = 'license_key';
  static const _installationIdKey = 'installation_id';
  static const _storeIdKey = 'store_id';
  static const _activationTokenKey = 'activation_token';
  static const _lastVerifiedAtKey = 'last_verified_at';
  static const _storeNameKey = 'store_name';
  static const _licenseExpiresAtKey = 'license_expires_at';
  static const _licenseStatusKey = 'license_status';
  static const _cloudEmailKey = 'cloud_sync_email';
  static const _cloudPasswordKey = 'cloud_sync_password';
  static const _localOwnerStoreIdKey = 'local_owner_store_id';
  static const _offlineGracePeriod = Duration(days: 14);
  static const _manageDevicesFunction = 'manage-license-devices';

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
    await _secureStorage.write(key: _installationIdKey, value: installationId);
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
      _secureStorage.read(key: _licenseExpiresAtKey),
      _secureStorage.read(key: _licenseStatusKey),
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
      licenseExpiresAt: DateTime.tryParse(values[6]?.trim() ?? ''),
      licenseStatus: values[7]?.trim().toLowerCase() ?? 'active',
    );
  }

  Future<bool> hasValidLocalActivation() async {
    final activation = await readLocalActivation();
    if (activation == null) return false;
    return !activation.isExpired &&
        !activation.isSuspended &&
        DateTime.now().difference(activation.lastVerifiedAt) <=
            _offlineGracePeriod;
  }

  Future<LicenseActivation?> recoverActivation() async {
    final existingRecovery = _recoveryInFlight;
    if (existingRecovery != null) return existingRecovery;

    final recovery = _recoverActivation();
    _recoveryInFlight = recovery;
    try {
      return await recovery;
    } finally {
      if (identical(_recoveryInFlight, recovery)) {
        _recoveryInFlight = null;
      }
    }
  }

  Future<LicenseActivation?> _recoverActivation() async {
    _ensureConfigured();
    final installationId = await getOrCreateInstallationId();
    final existingToken = await _secureStorage.read(key: _activationTokenKey);
    final existingLicenseKey = await _secureStorage.read(key: _licenseKey);

    Map<String, dynamic>? response;
    try {
      response = await _postFunction('validate-license', {
        'installationId': installationId,
        if (existingToken != null && existingToken.trim().isNotEmpty)
          'activationToken': existingToken.trim(),
      });
    } catch (error) {
      final licenseKey = existingLicenseKey?.trim() ?? '';
      if (licenseKey.isEmpty || !_shouldRetryRecoveryWithLicenseKey(error)) {
        rethrow;
      }
      response = await _postFunction('validate-license', {
        'installationId': installationId,
        'licenseKey': licenseKey,
      });
    }

    if (response == null) return null;
    await saveActivation(
      licenseKey: response['licenseKey']?.toString() ?? '',
      installationId: installationId,
      storeId: response['storeId']?.toString() ?? '',
      activationToken: response['activationToken']?.toString() ?? '',
      storeName: response['storeName']?.toString(),
      licenseExpiresAt: _responseExpiry(response),
    );
    return readLocalActivation();
  }

  bool _shouldRetryRecoveryWithLicenseKey(Object error) {
    final message = error.toString().toLowerCase();
    return !message.contains('expired') &&
        !message.contains('suspended') &&
        !message.contains('could not reach') &&
        !message.contains('temporarily unavailable') &&
        !message.contains('too many attempts');
  }

  Future<LicenseActivation?> refreshLicenseStatus() async {
    try {
      return await recoverActivation();
    } catch (e) {
      if (!e.toString().toLowerCase().contains('suspended')) rethrow;
      await _secureStorage.write(key: _licenseStatusKey, value: 'suspended');
      return readLocalActivation();
    }
  }

  Future<LicenseCheckResult> checkLicenseKey(String licenseKey) async {
    _ensureConfigured();
    final cleanedLicense = _sanitizeLicenseKey(licenseKey);
    if (cleanedLicense.isEmpty) {
      throw Exception('Enter a valid license code.');
    }

    final installationId = await getOrCreateInstallationId();
    final existingToken = await _secureStorage.read(key: _activationTokenKey);
    final response = await _postFunction('validate-license', {
      'installationId': installationId,
      'licenseKey': cleanedLicense,
      if (existingToken != null && existingToken.trim().isNotEmpty)
        'activationToken': existingToken.trim(),
    });

    if (response == null) {
      throw Exception(
        'Could not verify this license. Please check the code and try again.',
      );
    }

    final activated = response['activated'] == true;
    if (activated) {
      await saveActivation(
        licenseKey: response['licenseKey']?.toString() ?? cleanedLicense,
        installationId: installationId,
        storeId: response['storeId']?.toString() ?? '',
        activationToken: response['activationToken']?.toString() ?? '',
        storeName: response['storeName']?.toString(),
        licenseExpiresAt: _responseExpiry(response),
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
    final existingToken = await _secureStorage.read(key: _activationTokenKey);
    final deviceName = await DeviceIdentityService.deviceName();
    final response = await _postFunction('register-store-v2', {
      'storeName': storeName,
      'ownerName': ownerName,
      'email': email,
      'password': password,
      'inviteCode': licenseKey,
      'installationId': installationId,
      if (existingToken != null && existingToken.trim().isNotEmpty)
        'activationToken': existingToken.trim(),
      'deviceName': deviceName,
    });

    if (response == null) {
      throw Exception('Cloud registration returned an empty response.');
    }

    final storeId = response['storeId']?.toString() ?? '';
    final activationToken = response['activationToken']?.toString() ?? '';
    if (storeId.isEmpty || activationToken.isEmpty) {
      throw Exception('Cloud registration did not return activation data.');
    }

    await saveActivation(
      licenseKey: response['licenseKey']?.toString() ?? licenseKey,
      clearLicenseKeyWhenEmpty: response['persistLicenseKey'] == false,
      installationId: installationId,
      storeId: storeId,
      activationToken: activationToken,
      storeName: response['storeName']?.toString() ?? storeName,
      licenseExpiresAt: _responseExpiry(response),
    );

    final activation = await readLocalActivation();
    if (activation == null) {
      throw Exception('Could not save local activation.');
    }
    await saveCloudSyncCredentials(email: email, password: password);
    await ensureCloudSyncSignedIn();
    return activation;
  }

  Future<LicenseDeviceSummary> listLicenseDevices() async {
    final activation = await readLocalActivation();
    if (activation == null) {
      throw Exception('Activate this device before managing license devices.');
    }

    final response = await _postAuthenticatedFunction(_manageDevicesFunction, {
      'action': 'list',
      'storeId': activation.storeId,
      'installationId': activation.installationId,
    });
    final rows = response['devices'];
    final devices = rows is List
        ? rows
              .whereType<Map>()
              .map(
                (row) => LicenseDevice(
                  id: row['id']?.toString() ?? '',
                  name: row['name']?.toString().trim().isNotEmpty == true
                      ? row['name'].toString().trim()
                      : 'POS Device',
                  isCurrent: row['isCurrent'] == true,
                  activatedAt: DateTime.tryParse(
                    row['activatedAt']?.toString() ?? '',
                  ),
                  lastSeenAt: DateTime.tryParse(
                    row['lastSeenAt']?.toString() ?? '',
                  ),
                  revokedAt: DateTime.tryParse(
                    row['revokedAt']?.toString() ?? '',
                  ),
                ),
              )
              .where((device) => device.id.isNotEmpty)
              .toList(growable: false)
        : const <LicenseDevice>[];

    return LicenseDeviceSummary(
      slotLimit: (response['slotLimit'] as num?)?.toInt() ?? 1,
      activeDeviceCount: (response['activeDeviceCount'] as num?)?.toInt() ?? 0,
      devices: devices,
    );
  }

  Future<void> revokeLicenseDevice(String deviceId) async {
    final activation = await readLocalActivation();
    if (activation == null) {
      throw Exception('Activate this device before managing license devices.');
    }

    await _postAuthenticatedFunction(_manageDevicesFunction, {
      'action': 'revoke',
      'storeId': activation.storeId,
      'installationId': activation.installationId,
      'deviceId': deviceId,
    });
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

  Future<bool> connectCloudSyncCredentials({
    required String email,
    required String password,
  }) async {
    final cleanedEmail = email.trim().toLowerCase();
    if (cleanedEmail.isEmpty || password.isEmpty) return false;

    final previous = await Future.wait([
      _secureStorage.read(key: _cloudEmailKey),
      _secureStorage.read(key: _cloudPasswordKey),
    ]);
    final client = Supabase.instance.client;
    await client.auth.signOut();
    await saveCloudSyncCredentials(email: cleanedEmail, password: password);
    if (await ensureCloudSyncSignedIn()) return true;

    await Future.wait([
      if (previous[0]?.isNotEmpty == true)
        _secureStorage.write(key: _cloudEmailKey, value: previous[0]!)
      else
        _secureStorage.delete(key: _cloudEmailKey),
      if (previous[1]?.isNotEmpty == true)
        _secureStorage.write(key: _cloudPasswordKey, value: previous[1]!)
      else
        _secureStorage.delete(key: _cloudPasswordKey),
    ]);
    await ensureCloudSyncSignedIn();
    return false;
  }

  Future<String?> readLocalOwnerStoreId() async {
    final storeId = await _secureStorage.read(key: _localOwnerStoreIdKey);
    final trimmed = storeId?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> saveLocalOwnerStoreId(String storeId) async {
    final trimmed = storeId.trim();
    if (trimmed.isEmpty) return;
    await _secureStorage.write(key: _localOwnerStoreIdKey, value: trimmed);
  }

  Future<bool> localOwnerMatchesStore(String storeId) async {
    final localStoreId = await readLocalOwnerStoreId();
    return localStoreId != null && localStoreId == storeId.trim();
  }

  Future<bool> ensureCloudSyncSignedIn() async {
    try {
      final values = await Future.wait([
        _secureStorage.read(key: _cloudEmailKey),
        _secureStorage.read(key: _cloudPasswordKey),
      ]);
      final email = values[0]?.trim().toLowerCase() ?? '';
      final password = values[1] ?? '';

      final client = Supabase.instance.client;
      final currentEmail = client.auth.currentUser?.email?.trim().toLowerCase();
      if (client.auth.currentSession != null) {
        if (email.isEmpty || currentEmail == email) {
          if (await _authorizeCloudSyncSession(client)) return true;
          if (email.isEmpty || password.isEmpty) return false;
        }
        await client.auth.signOut();
      }

      if (email.isEmpty || password.isEmpty) return false;

      await client.auth.signInWithPassword(email: email, password: password);
      return client.auth.currentSession != null &&
          await _authorizeCloudSyncSession(client);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _authorizeCloudSyncSession(SupabaseClient client) async {
    final activation = await readLocalActivation();
    final accessToken = client.auth.currentSession?.accessToken;
    if (activation == null || accessToken == null || accessToken.isEmpty) {
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse(
          '${EnvConfig.supabaseUrl}/functions/v1/$_manageDevicesFunction',
        ),
        headers: {
          'apikey': EnvConfig.supabaseAnonKey,
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'action': 'authorize-sync',
          'storeId': activation.storeId,
          'installationId': activation.installationId,
          'activationToken': activation.activationToken,
        }),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) return true;
      if (response.statusCode == 401 ||
          response.statusCode == 403 ||
          response.statusCode == 409) {
        await client.auth.signOut();
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> saveActivation({
    required String licenseKey,
    required String installationId,
    required String storeId,
    required String activationToken,
    bool clearLicenseKeyWhenEmpty = false,
    String? storeName,
    DateTime? licenseExpiresAt,
    String licenseStatus = 'active',
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await Future.wait([
      if (licenseKey.trim().isNotEmpty)
        _secureStorage.write(key: _licenseKey, value: licenseKey),
      if (licenseKey.trim().isEmpty && clearLicenseKeyWhenEmpty)
        _secureStorage.delete(key: _licenseKey),
      _secureStorage.write(key: _installationIdKey, value: installationId),
      _secureStorage.write(key: _storeIdKey, value: storeId),
      _secureStorage.write(key: _activationTokenKey, value: activationToken),
      _secureStorage.write(key: _lastVerifiedAtKey, value: now),
      if (storeName != null && storeName.trim().isNotEmpty)
        _secureStorage.write(key: _storeNameKey, value: storeName.trim()),
      if (licenseExpiresAt != null)
        _secureStorage.write(
          key: _licenseExpiresAtKey,
          value: licenseExpiresAt.toUtc().toIso8601String(),
        ),
      _secureStorage.write(key: _licenseStatusKey, value: licenseStatus),
    ]);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storeIdKey, storeId);
    if (storeName != null && storeName.trim().isNotEmpty) {
      await prefs.setString(_storeNameKey, storeName.trim());
    }
  }

  Future<void> sendMagicLinkEmail(String email) async {
    final cleanedEmail = email.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(cleanedEmail)) {
      throw Exception('Enter a valid email.');
    }
    try {
      final redirectUrl = EnvConfig.supabaseMagicLinkRedirectUrl;
      await Supabase.instance.client.auth.signInWithOtp(
        email: cleanedEmail,
        emailRedirectTo: redirectUrl.isEmpty ? null : redirectUrl,
        shouldCreateUser: false,
      );
    } on AuthException catch (e) {
      throw Exception(_magicLinkErrorMessage(e));
    } catch (e) {
      throw Exception(_magicLinkErrorMessage(e));
    }
  }

  String _magicLinkErrorMessage(Object error) {
    if (error is AuthException && _isRateLimitError(error)) {
      final waitSeconds = _waitSecondsFromMessage(error.message);
      if (waitSeconds != null) {
        return 'Too many requests. Please wait $waitSeconds seconds before sending another magic link.';
      }
      return 'Too many requests. Please wait a minute before sending another magic link.';
    }

    if (_isRateLimitMessage(error.toString())) {
      return 'Too many requests. Please wait a minute before sending another magic link.';
    }

    return 'Could not send the magic link. Please check the email and try again.';
  }

  bool _isRateLimitError(AuthException error) {
    return error.statusCode == '429' ||
        _isRateLimitMessage(error.code ?? '') ||
        _isRateLimitMessage(error.message);
  }

  bool _isRateLimitMessage(String value) {
    final normalized = value.toLowerCase();
    return normalized.contains('rate limit') ||
        normalized.contains('rate_limit') ||
        normalized.contains('too many') ||
        normalized.contains('429');
  }

  String? _waitSecondsFromMessage(String message) {
    return RegExp(
      r'(\d+)\s*seconds?',
      caseSensitive: false,
    ).firstMatch(message)?.group(1);
  }

  Future<Map<String, dynamic>?> _postFunction(
    String functionName,
    Map<String, Object?> body,
  ) async {
    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('${EnvConfig.supabaseUrl}/functions/v1/$functionName'),
        headers: {
          'apikey': EnvConfig.supabaseAnonKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
    } catch (_) {
      throw Exception(
        'Could not reach the license server. Check your internet connection and try again.',
      );
    }

    final decoded = _decodeJson(response.body);
    if (response.statusCode == 404) {
      if (functionName == 'validate-license' &&
          body.containsKey('licenseKey')) {
        throw Exception(
          _licenseActivationErrorMessage(
            functionName: functionName,
            statusCode: response.statusCode,
            message: 'License not found.',
          ),
        );
      }
      if (functionName == 'register-store-v2') {
        throw Exception(
          'The license activation service is unavailable. Please try again in a few minutes.',
        );
      }
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map && decoded['error'] != null
          ? decoded['error'].toString()
          : response.body;
      throw Exception(
        _licenseActivationErrorMessage(
          functionName: functionName,
          statusCode: response.statusCode,
          message: message,
        ),
      );
    }
    if (decoded is Map && decoded['error'] != null) {
      throw Exception(
        _licenseActivationErrorMessage(
          functionName: functionName,
          message: decoded['error'].toString(),
        ),
      );
    }
    return decoded is Map<String, dynamic>
        ? decoded
        : decoded is Map
        ? decoded.map((key, value) => MapEntry(key.toString(), value))
        : null;
  }

  Future<Map<String, dynamic>> _postAuthenticatedFunction(
    String functionName,
    Map<String, Object?> body,
  ) async {
    _ensureConfigured();
    final signedIn = await ensureCloudSyncSignedIn();
    final accessToken =
        Supabase.instance.client.auth.currentSession?.accessToken;
    if (!signedIn || accessToken == null || accessToken.isEmpty) {
      throw Exception('Sign in with the owner account to manage devices.');
    }

    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('${EnvConfig.supabaseUrl}/functions/v1/$functionName'),
        headers: {
          'apikey': EnvConfig.supabaseAnonKey,
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
    } catch (_) {
      throw Exception(
        'Could not reach the license server. Check your internet connection and try again.',
      );
    }

    final decoded = _decodeJson(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map && decoded['error'] != null
          ? decoded['error'].toString()
          : response.body;
      throw Exception(message);
    }
    if (decoded is! Map) {
      throw Exception('License server returned an invalid response.');
    }
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }

  String _licenseActivationErrorMessage({
    required String functionName,
    int? statusCode,
    required String message,
  }) {
    final normalized = message.toLowerCase();

    if (normalized.contains('device slots')) {
      return 'All device slots are in use. Revoke an old device in Settings or contact support.';
    }

    if (normalized.contains('already activated for another license')) {
      return 'This device is already activated for another license. Ask the admin to revoke its previous activation before using a different license.';
    }

    if (statusCode == 429 || _isRateLimitMessage(message)) {
      return 'Too many attempts. Please wait a minute before trying again.';
    }

    if (statusCode != null && statusCode >= 500) {
      return 'The license server is temporarily unavailable. Please try again in a few minutes.';
    }

    if (functionName == 'register-store-v2' &&
        normalized.contains('email') &&
        normalized.contains('does not match')) {
      return 'This email does not match the existing license account.';
    }

    if (functionName == 'register-store-v2' &&
        (normalized.contains('already registered') ||
            normalized.contains('original owner') ||
            normalized.contains('owner account'))) {
      return 'This email or password does not match the existing license account.';
    }

    if (normalized.contains('not found') ||
        normalized.contains('invalid') ||
        normalized.contains('invite') && normalized.contains('code')) {
      return 'We could not find that license code. Check the code and try again.';
    }

    if (normalized.contains('expired')) {
      return 'This license has expired. Contact support to renew it.';
    }

    if (normalized.contains('suspended')) {
      return 'This license is suspended. Contact support for assistance.';
    }

    if (normalized.contains('already') &&
        (normalized.contains('activated') ||
            normalized.contains('used') ||
            normalized.contains('store'))) {
      return 'This license is already active. Sign in with the owner account to restore this device.';
    }

    if (functionName == 'register-store-v2' &&
        (normalized.contains('email') ||
            normalized.contains('user') ||
            normalized.contains('duplicate'))) {
      return 'That owner email is already registered. Sign in with the owner account or use a different email.';
    }

    if (functionName == 'register-store-v2' &&
        normalized.contains('password')) {
      return 'Use a stronger owner password and try again.';
    }

    if (statusCode == 401 || statusCode == 403) {
      return 'The license server rejected the request. Please check your Supabase settings or contact support.';
    }

    return functionName == 'register-store-v2'
        ? 'Could not activate this license. Please check your details and try again.'
        : 'Could not verify this license. Please check the code and try again.';
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

  DateTime? _responseExpiry(Map<String, dynamic> response) {
    return DateTime.tryParse(response['licenseExpiresAt']?.toString() ?? '');
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
