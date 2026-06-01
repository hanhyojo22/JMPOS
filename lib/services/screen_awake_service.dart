import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class ScreenAwakeService {
  ScreenAwakeService._();

  static final ScreenAwakeService instance = ScreenAwakeService._();

  static const preferenceKey = 'keep_screen_on';

  bool _keepScreenOn = false;
  int _temporaryHoldCount = 0;

  bool get keepScreenOn => _keepScreenOn;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _keepScreenOn = prefs.getBool(preferenceKey) ?? false;
    await _apply();
  }

  Future<void> setKeepScreenOn(bool value) async {
    _keepScreenOn = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(preferenceKey, value);
    await _apply();
  }

  Future<void> acquireTemporaryHold() async {
    _temporaryHoldCount += 1;
    await _apply();
  }

  Future<void> releaseTemporaryHold() async {
    if (_temporaryHoldCount > 0) {
      _temporaryHoldCount -= 1;
    }
    await _apply();
  }

  Future<void> _apply() {
    return WakelockPlus.toggle(
      enable: _keepScreenOn || _temporaryHoldCount > 0,
    );
  }
}
