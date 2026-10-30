import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/platform.dart';

/// Android TV: the video is shown by the TV box itself, on its video plane
/// under the (transparent) app, like its built-in player shows USB files.
/// mpv's hardware decoder renders straight into that layer, so there are no
/// per-frame copies (smooth 1080p/4K) and the picture keeps its full
/// resolution, HDR and the box's picture processing. See VideoLayer.kt.
class VideoLayer {
  static const _ch = MethodChannel('homestream/video');

  /// The app was started with a transparent surface, so the layer can be
  /// seen. Turning the setting on later takes effect at the next start.
  static bool available = false;

  /// mpv's handle of the layer's surface; 0 while there is none (not shown
  /// yet, or the app is in the background).
  static final ValueNotifier<int> surface = ValueNotifier(0);

  static int _owner = 0;

  static Future<void> init() async {
    if (!AppPlatform.isAndroid || !AppPlatform.isTv) return;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'surface') {
        final args = call.arguments;
        surface.value = args is Map ? (args['wid'] as num?)?.toInt() ?? 0 : 0;
      }
    });
    try {
      available = await _ch.invokeMethod<bool>('available') ?? false;
    } catch (_) {}
  }

  /// Shows the layer and returns a token for [hide]. The surface arrives in
  /// [surface] (right away if the layer is already there).
  static Future<int> show() async {
    final token = ++_owner;
    try {
      await _ch.invokeMethod('show');
    } catch (_) {}
    return token;
  }

  /// Removes the layer, unless a newer player has taken it over.
  static Future<void> hide(int token) async {
    if (token != _owner) return;
    try {
      await _ch.invokeMethod('hide');
    } catch (_) {}
  }

  /// The video's display size, so the layer keeps its aspect ratio.
  static Future<void> setVideoSize(int w, int h) async {
    try {
      await _ch.invokeMethod('size', {'w': w, 'h': h});
    } catch (_) {}
  }
}
