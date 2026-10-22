import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Small Android helpers (MainActivity.kt).
class AppPlatform {
  static const _ch = MethodChannel('homemusic/platform');

  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  static bool _awake = false;
  static DateTime _awakeAt = DateTime(0);

  /// Keeps the CPU and Wi-Fi awake while streaming with the screen off.
  static Future<void> keepAwake(bool on) async {
    if (!isAndroid) return;
    // the wake lock has a 30 min timeout: renew it every 10 min
    if (on == _awake &&
        (!on || DateTime.now().difference(_awakeAt).inMinutes < 10)) {
      return;
    }
    _awake = on;
    if (on) _awakeAt = DateTime.now();
    try {
      await _ch.invokeMethod('keepAwake', {'on': on});
    } catch (_) {}
  }

  static Future<bool> ignoringBatteryOptimizations() async {
    if (!isAndroid) return true;
    try {
      return await _ch.invokeMethod<bool>('ignoringBatteryOptimizations') ??
          true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> requestIgnoreBatteryOptimizations() async {
    if (!isAndroid) return;
    try {
      await _ch.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (_) {}
  }

  /// Sends the app to the background (like the home button).
  static Future<void> moveToBack() async {
    if (!isAndroid) {
      await SystemNavigator.pop();
      return;
    }
    try {
      final ok = await _ch.invokeMethod<bool>('moveToBack');
      if (ok != true) await SystemNavigator.pop();
    } catch (_) {
      await SystemNavigator.pop();
    }
  }
}
