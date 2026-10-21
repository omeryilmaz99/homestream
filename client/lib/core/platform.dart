import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Platform facts used to adapt the UI (desktop, Android TV, phone).
class AppPlatform {
  static const _ch = MethodChannel('homestream/platform');

  static bool get isAndroid => !kIsWeb && Platform.isAndroid;
  static bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// True on Android TV / Google TV (or any Android device without touch).
  /// `HS_FORCE_TV=1` simulates TV mode on desktop for testing.
  static bool isTv = false;

  /// Android phone or tablet (touch screen). `HS_FORCE_PHONE=1` simulates it.
  static bool isPhone = false;

  /// Server changes (folders, scans) are only offered on the PC app.
  static bool get canManageServer => isDesktop && !isPhone && !isTv;

  static Future<void> init() async {
    if (isAndroid) {
      try {
        isTv = await _ch.invokeMethod<bool>('isTv') ?? false;
      } catch (_) {}
    } else if (isDesktop && Platform.environment['HS_FORCE_TV'] == '1') {
      isTv = true;
    } else if (isDesktop && Platform.environment['HS_FORCE_PHONE'] == '1') {
      isPhone = true;
    }
    if (isAndroid && !isTv) isPhone = true;
  }

  static Future<void> keepScreenOn(bool on) async {
    if (!isAndroid) return;
    try {
      await _ch.invokeMethod('keepScreenOn', {'on': on});
    } catch (_) {}
  }

  /// Opens a video URL in another Android app. [package] picks a specific app,
  /// otherwise Android shows its chooser. Returns false if nothing can play it.
  static Future<bool> openExternal(
    String url,
    String title, {
    String? package,
    int startMs = 0,
    List<String> subtitles = const [],
  }) async {
    try {
      return await _ch.invokeMethod<bool>('openExternal', {
            'url': url,
            'title': title,
            'package': package,
            'startMs': startMs,
            'subtitles': subtitles,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Installed Android video players as (label, package).
  static Future<List<(String, String)>> videoPlayers() async {
    try {
      final list = await _ch.invokeMethod<List<dynamic>>('videoPlayers') ?? [];
      return [
        for (final e in list)
          if (e is List && e.length == 2) ('${e[0]}', '${e[1]}'),
      ];
    } catch (_) {
      return [];
    }
  }
}
