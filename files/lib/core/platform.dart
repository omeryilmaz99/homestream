import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';

class AppPlatform {
  static const _ch = MethodChannel('homedosya/platform');

  static bool get isAndroid => !kIsWeb && Platform.isAndroid;
  static bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  static String get platformName {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isMacOS) return 'macOS';
    return Platform.operatingSystem;
  }

  /// "Ömer-PC" on desktop, "Samsung SM-A525F" on a phone.
  static Future<String> defaultDeviceName() async {
    try {
      if (isAndroid) {
        final a = await DeviceInfoPlugin().androidInfo;
        final brand = a.brand.isEmpty
            ? ''
            : a.brand[0].toUpperCase() + a.brand.substring(1);
        return '$brand ${a.model}'.trim();
      }
      if (Platform.isWindows) {
        final w = await DeviceInfoPlugin().windowsInfo;
        if (w.computerName.isNotEmpty) return w.computerName;
      }
      final h = Platform.localHostname;
      if (h.isNotEmpty && h != 'localhost') return h;
    } catch (_) {}
    return platformName;
  }

  static bool _fgOn = false;
  static DateTime _fgAt = DateTime(0);
  static String _fgText = '';

  /// Keeps transfers running with the screen off (Android foreground service).
  static Future<void> transferNotice(
    bool on, {
    String title = '',
    String text = '',
    int progress = -1,
  }) async {
    if (!isAndroid) return;
    final now = DateTime.now();
    if (on &&
        _fgOn &&
        text == _fgText &&
        now.difference(_fgAt).inSeconds < 2) {
      return;
    }
    if (on && _fgOn && now.difference(_fgAt).inMilliseconds < 1500) return;
    if (!on && !_fgOn) return;
    _fgOn = on;
    _fgAt = now;
    _fgText = text;
    try {
      await _ch.invokeMethod('transfer', {
        'on': on,
        'title': title,
        'text': text,
        'progress': progress,
      });
    } catch (_) {}
  }

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

  static Future<int> sdkInt() async {
    if (!isAndroid) return 0;
    try {
      return await _ch.invokeMethod<int>('sdkInt') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Whether the app may read and write the phone's storage.
  static Future<bool> hasStorageAccess() async {
    if (!isAndroid) return true;
    if (await sdkInt() >= 30) {
      return Permission.manageExternalStorage.isGranted;
    }
    return Permission.storage.isGranted;
  }

  /// Asks for storage access (Android 11+: opens the "All files access" page).
  static Future<bool> requestStorageAccess() async {
    if (!isAndroid) return true;
    if (await sdkInt() >= 30) {
      final s = await Permission.manageExternalStorage.request();
      return s.isGranted;
    }
    final s = await Permission.storage.request();
    return s.isGranted;
  }

  static Future<void> requestNotifications() async {
    if (!isAndroid) return;
    try {
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
    } catch (_) {}
  }

  /// Opens a local file with the default app. Returns an error text or null.
  static Future<String?> openFile(String path) async {
    try {
      if (Platform.isWindows) {
        await Process.start('explorer', [path], runInShell: false);
        return null;
      }
      if (Platform.isLinux) {
        await Process.start('xdg-open', [path]);
        return null;
      }
      if (Platform.isMacOS) {
        await Process.start('open', [path]);
        return null;
      }
      final r = await OpenFilex.open(path);
      if (r.type == ResultType.done) return null;
      if (r.type == ResultType.noAppToOpen) {
        return 'Bu dosyayı açacak uygulama yok.';
      }
      return r.message;
    } catch (e) {
      return 'Açılamadı: $e';
    }
  }

  /// Shows a file in the file manager (desktop).
  static Future<void> reveal(String path) async {
    try {
      if (Platform.isWindows) {
        await Process.start('explorer', ['/select,', path]);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [File(path).parent.path]);
      } else if (Platform.isMacOS) {
        await Process.start('open', ['-R', path]);
      }
    } catch (_) {}
  }
}
