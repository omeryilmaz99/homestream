import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Disk + memory cached network image. Covers are fetched once and then
/// served from disk, so scrolling stays smooth and works offline.
class DiskCache {
  static Directory? _dir;
  static final http.Client _client = http.Client();
  static final Map<String, Future<Uint8List?>> _inflight = {};
  static int _active = 0;
  static final List<Completer<void>> _queue = [];

  static Future<Directory> dir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}${Platform.pathSeparator}image_cache');
    if (!await d.exists()) await d.create(recursive: true);
    _dir = d;
    return d;
  }

  static Future<void> _acquire() async {
    if (_active < 6) {
      _active++;
      return;
    }
    final c = Completer<void>();
    _queue.add(c);
    await c.future;
    _active++;
  }

  static void _release() {
    _active--;
    if (_queue.isNotEmpty) _queue.removeAt(0).complete();
  }

  static Future<File> _fileOf(String url) async {
    final d = await dir();
    final name = sha1.convert(url.codeUnits).toString();
    return File('${d.path}${Platform.pathSeparator}$name');
  }

  /// The cached file of url, downloading it first (null when it fails).
  static Future<File?> fileFor(String url) async {
    final f = await _fileOf(url);
    if (await f.exists()) return f;
    final bytes = await load(url);
    if (bytes == null) return null;
    return await f.exists() ? f : null;
  }

  /// The cached file of url if it is already on disk.
  static Future<File?> cachedFile(String url) async {
    final f = await _fileOf(url);
    return await f.exists() ? f : null;
  }

  static Future<Uint8List?> load(String url) {
    return _inflight.putIfAbsent(url, () async {
      try {
        final d = await dir();
        final name = sha1.convert(url.codeUnits).toString();
        final f = File('${d.path}${Platform.pathSeparator}$name');
        if (await f.exists()) {
          final bytes = await f.readAsBytes();
          if (bytes.isNotEmpty) return bytes;
        }
        await _acquire();
        try {
          final resp = await _client
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 30));
          if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) return null;
          final tmp = File('${f.path}.tmp');
          await tmp.writeAsBytes(resp.bodyBytes, flush: false);
          try {
            await tmp.rename(f.path);
          } catch (_) {}
          return resp.bodyBytes;
        } finally {
          _release();
        }
      } catch (_) {
        return null;
      } finally {
        // ignore: unawaited_futures
        Future.microtask(() => _inflight.remove(url));
      }
    });
  }

  static Future<int> sizeBytes() async {
    var total = 0;
    try {
      await for (final e in (await dir()).list()) {
        if (e is File) total += await e.length();
      }
    } catch (_) {}
    return total;
  }

  static Future<void> clear() async {
    try {
      final d = await dir();
      await d.delete(recursive: true);
      _dir = null;
    } catch (_) {}
    PaintingBinding.instance.imageCache.clear();
  }
}

@immutable
class CachedNetImage extends ImageProvider<CachedNetImage> {
  final String url;
  const CachedNetImage(this.url);

  @override
  Future<CachedNetImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    CachedNetImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _load(decode),
      scale: 1.0,
      debugLabel: url,
    );
  }

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await DiskCache.load(url);
    if (bytes == null) throw StateError('image failed: $url');
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) => other is CachedNetImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
}
