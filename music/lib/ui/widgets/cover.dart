import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/downloads.dart';
import '../../core/image_cache.dart';
import '../../state/app_state.dart';
import '../theme.dart';

/// Same palettes as the server's generated covers.
const coverPalettes = [
  [Color(0xFF1DB954), Color(0xFF0B2E1A)],
  [Color(0xFF7B2FF7), Color(0xFF1E0B45)],
  [Color(0xFFFF4E8A), Color(0xFF4A0D2B)],
  [Color(0xFFFF8A3D), Color(0xFF4D2108)],
  [Color(0xFF18C6C1), Color(0xFF08333A)],
  [Color(0xFF3D7BFF), Color(0xFF0C184D)],
  [Color(0xFFF5C518), Color(0xFF4A3705)],
  [Color(0xFFFF4D4D), Color(0xFF420A0A)],
];

int _seed(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}

/// Shown while a cover loads, or when it can't be loaded (offline).
class CoverPlaceholder extends StatelessWidget {
  final String seed;
  final IconData icon;
  const CoverPlaceholder(
    this.seed, {
    super.key,
    this.icon = Icons.music_note_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final p = coverPalettes[_seed(seed) % coverPalettes.length];
    return LayoutBuilder(
      builder: (context, c) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: p,
          ),
        ),
        child: Center(
          child: Icon(
            icon,
            size: math.max(14, c.biggest.shortestSide * 0.38),
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
      ),
    );
  }
}

/// Album / song cover: downloaded file, cached server image or placeholder.
class CoverImage extends StatelessWidget {
  final String cover; // server path ("/api/music/covers/<id>?v=..")
  final String coverId;
  final double radius;
  final bool circle;
  final int width; // requested pixel width
  final IconData placeholderIcon;
  const CoverImage({
    super.key,
    required this.cover,
    this.coverId = '',
    this.radius = 10,
    this.circle = false,
    this.width = 320,
    this.placeholderIcon = Icons.music_note_rounded,
  });

  static String idFromPath(String cover) {
    final m = RegExp(r'/covers/([^/?]+)').firstMatch(cover);
    return m?.group(1) ?? cover;
  }

  @override
  Widget build(BuildContext context) {
    final api = context.select<AppState, ApiClient?>((s) => s.api);
    final dl = context.read<Downloads>();
    final id = coverId.isNotEmpty ? coverId : idFromPath(cover);
    final ph = CoverPlaceholder(id, icon: placeholderIcon);
    Widget child;
    final local = dl.coverFile(id);
    if (local != null) {
      child = Image.file(
        File(local),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        cacheWidth: width,
        errorBuilder: (_, _, _) => ph,
      );
    } else if (api != null && cover.isNotEmpty) {
      child = Image(
        image: CachedNetImage(api.coverUrl(cover, width: width)),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        frameBuilder: (context, child, frame, sync) {
          if (sync) return child;
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            layoutBuilder: (cur, prev) =>
                Stack(fit: StackFit.expand, children: [...prev, ?cur]),
            child: frame == null ? ph : child,
          );
        },
        errorBuilder: (_, _, _) => ph,
      );
    } else {
      child = ph;
    }
    return ClipRRect(
      borderRadius: circle
          ? BorderRadius.circular(10000)
          : BorderRadius.circular(radius),
      child: child,
    );
  }
}

/// Playlist picture: 2x2 grid of song covers.
class MosaicCover extends StatelessWidget {
  final List<String> covers;
  final String seed;
  final double radius;
  final int width;
  const MosaicCover({
    super.key,
    required this.covers,
    required this.seed,
    this.radius = 10,
    this.width = 320,
  });

  @override
  Widget build(BuildContext context) {
    if (covers.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: CoverPlaceholder(seed, icon: Icons.queue_music_rounded),
      );
    }
    if (covers.length < 4) {
      return CoverImage(cover: covers.first, radius: radius, width: width);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: GridView.count(
        crossAxisCount: 2,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          for (final c in covers.take(4))
            CoverImage(cover: c, radius: 0, width: width ~/ 2),
        ],
      ),
    );
  }
}

/// "Beğenilen Şarkılar" picture.
class LikedCover extends StatelessWidget {
  final double radius;
  const LikedCover({super.key, this.radius = 10});
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: LayoutBuilder(
        builder: (context, c) => DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF4527D9), Color(0xFF8C7CF6), Color(0xFFB9E5CF)],
              stops: [0, 0.6, 1],
            ),
          ),
          child: Center(
            child: Icon(
              Icons.favorite_rounded,
              color: Colors.white,
              size: math.max(14, c.biggest.shortestSide * 0.4),
            ),
          ),
        ),
      ),
    );
  }
}

/// Picture of a downloaded folder / generic collection.
class FolderCover extends StatelessWidget {
  final String cover;
  final double radius;
  const FolderCover({super.key, required this.cover, this.radius = 10});
  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CoverImage(
          cover: cover,
          radius: radius,
          placeholderIcon: Icons.folder_rounded,
        ),
        Positioned(
          right: 4,
          bottom: 4,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.folder_rounded, size: 14, color: C.text),
          ),
        ),
      ],
    );
  }
}

// ---------- dominant colour (player background) ----------

final Map<String, Color> _colorCache = {};

/// The main colour of a cover (cached), for tinted backgrounds.
Future<Color?> dominantColor(ImageProvider provider, String key) async {
  if (_colorCache.containsKey(key)) return _colorCache[key];
  final c = Completer<ui.Image?>();
  final stream = ResizeImage(
    provider,
    width: 24,
    height: 24,
  ).resolve(ImageConfiguration.empty);
  late ImageStreamListener l;
  l = ImageStreamListener(
    (info, _) {
      if (!c.isCompleted) c.complete(info.image.clone());
      stream.removeListener(l);
    },
    onError: (_, _) {
      if (!c.isCompleted) c.complete(null);
      stream.removeListener(l);
    },
  );
  stream.addListener(l);
  final img = await c.future.timeout(
    const Duration(seconds: 8),
    onTimeout: () => null,
  );
  if (img == null) return null;
  final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  img.dispose();
  if (data == null) return null;
  double r = 0, g = 0, b = 0, wsum = 0;
  for (var i = 0; i + 3 < data.lengthInBytes; i += 4) {
    final pr = data.getUint8(i) / 255,
        pg = data.getUint8(i + 1) / 255,
        pb = data.getUint8(i + 2) / 255;
    final mx = math.max(pr, math.max(pg, pb)),
        mn = math.min(pr, math.min(pg, pb));
    final sat = mx == 0 ? 0 : (mx - mn) / mx;
    // vivid, mid-bright pixels count most
    final w = 0.05 + sat * sat * (1 - (mx - 0.6).abs());
    r += pr * w;
    g += pg * w;
    b += pb * w;
    wsum += w;
  }
  if (wsum == 0) return null;
  var col = Color.fromARGB(
    255,
    (r / wsum * 255).round(),
    (g / wsum * 255).round(),
    (b / wsum * 255).round(),
  );
  final hsl = HSLColor.fromColor(col);
  col = hsl
      .withLightness(hsl.lightness.clamp(0.28, 0.5))
      .withSaturation(math.min(1, hsl.saturation * 1.15))
      .toColor();
  _colorCache[key] = col;
  return col;
}

/// ImageProvider for a track cover (for colour extraction).
ImageProvider? coverProvider(
  BuildContext context,
  String cover,
  String coverId,
) {
  final dl = context.read<Downloads>();
  final api = context.read<AppState>().api;
  final id = coverId.isNotEmpty ? coverId : CoverImage.idFromPath(cover);
  final local = dl.coverFile(id);
  if (local != null) return FileImage(File(local));
  if (api != null && cover.isNotEmpty) {
    return CachedNetImage(api.coverUrl(cover, width: 640));
  }
  return null;
}
