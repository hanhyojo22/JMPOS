import 'package:flutter/services.dart';

class DeviceIdentityService {
  DeviceIdentityService._();

  static const _channel = MethodChannel('jmsolution.posapp/device_identity');

  static Future<String?> stableDeviceId() async {
    try {
      final value = await _channel.invokeMethod<String>('getDeviceId');
      final deviceId = value?.trim();
      if (deviceId == null || deviceId.isEmpty) return null;
      return 'android:$deviceId';
    } catch (_) {
      return null;
    }
  }

  static Future<String> deviceName() async {
    try {
      final value = await _channel.invokeMethod<String>('getDeviceName');
      final name = value?.trim();
      if (name != null && name.isNotEmpty) return name;
    } catch (_) {
      // Fall back to a friendly generic label on unsupported platforms.
    }
    return 'POS Device';
  }
}
