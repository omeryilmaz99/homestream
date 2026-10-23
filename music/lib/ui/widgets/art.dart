import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Colours of the generated cover art: sky top, middle, horizon glow.
/// The server draws its placeholder covers from the same list.
const artPalettes = [
  [Color(0xFF1B1A4A), Color(0xFF6A4FD8), Color(0xFFF08BC0)],
  [Color(0xFF0F1C4D), Color(0xFF3B5BDB), Color(0xFFB78CF5)],
  [Color(0xFF2A1036), Color(0xFF9B3FA8), Color(0xFFFF9A7A)],
  [Color(0xFF0E2340), Color(0xFF2F7FA8), Color(0xFF9EE6E0)],
  [Color(0xFF24114A), Color(0xFF8E44F0), Color(0xFFFFB86B)],
  [Color(0xFF1A0F2E), Color(0xFFC2477F), Color(0xFFFFC2D6)],
  [Color(0xFF121A3A), Color(0xFF5A6CF0), Color(0xFFE6A3FF)],
  [Color(0xFF301634), Color(0xFFE0567A), Color(0xFFFFD08A)],
];

int artSeed(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}

List<Color> artPalette(String seed) =>
    artPalettes[artSeed(seed) % artPalettes.length];

/// Abstract gradient picture (misty mountains or silk waves), picked by seed.
/// Used for covers that can't be loaded and for decorative cards.
class GradientArt extends StatelessWidget {
  final String seed;
  final Widget? child;
  const GradientArt(this.seed, {super.key, this.child});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ArtPainter(artSeed(seed)),
      child: child ?? const SizedBox.expand(),
    );
  }
}

class _ArtPainter extends CustomPainter {
  final int h;
  _ArtPainter(this.h);

  double _r(int shift, double lo, double hi) =>
      lo + ((h >> shift) & 0xff) / 255 * (hi - lo);

  @override
  void paint(Canvas canvas, Size size) {
    final p = artPalettes[h % artPalettes.length];
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [p[0], p[1], p[2]],
          stops: const [0, 0.5, 0.78],
        ).createShader(rect),
    );
    // glow (setting sun)
    final gx = _r(3, 0.3, 0.7);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(gx * 2 - 1, 0.25),
          radius: 0.7,
          colors: [p[2].withValues(alpha: 0.75), p[2].withValues(alpha: 0)],
        ).createShader(rect),
    );
    if ((h >> 11) % 2 == 0) {
      _mountains(canvas, size, p);
    } else {
      _waves(canvas, size, p);
    }
    // soft vignette
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          radius: 0.95,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.28)],
        ).createShader(rect),
    );
  }

  void _mountains(Canvas canvas, Size size, List<Color> p) {
    final w = size.width, ht = size.height;
    const layers = 3;
    for (var k = 0; k < layers; k++) {
      final base = ht * (0.56 + k * 0.13);
      final amp = ht * (0.13 - k * 0.025);
      final f1 = _r(5 + k * 3, 1.2, 2.6);
      final f2 = _r(9 + k * 2, 3.0, 5.5);
      final ph = _r(13 + k, 0, 6.28);
      final path = Path()..moveTo(0, ht);
      const steps = 40;
      for (var i = 0; i <= steps; i++) {
        final x = i / steps;
        final y =
            base -
            amp *
                (0.65 * math.sin(x * f1 * math.pi + ph) +
                    0.35 * math.sin(x * f2 * math.pi + ph * 1.7));
        path.lineTo(x * w, y);
      }
      path
        ..lineTo(w, ht)
        ..close();
      final top = Color.lerp(p[1], p[0], 0.25 + k * 0.25)!;
      final bottom = Color.lerp(p[0], Colors.black, 0.35 + k * 0.2)!;
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [top.withValues(alpha: 0.92), bottom],
          ).createShader(Rect.fromLTWH(0, base - amp, w, ht - base + amp)),
      );
    }
  }

  void _waves(Canvas canvas, Size size, List<Color> p) {
    final w = size.width, ht = size.height;
    const bands = 5;
    final tilt = _r(5, -0.35, 0.35);
    for (var k = 0; k < bands; k++) {
      final base = ht * (0.22 + k * 0.17);
      final amp = ht * _r(7 + k, 0.06, 0.14);
      final ph = _r(9 + k * 2, 0, 6.28);
      final path = Path()..moveTo(0, ht);
      const steps = 40;
      for (var i = 0; i <= steps; i++) {
        final x = i / steps;
        final y =
            base +
            tilt * (x - 0.5) * ht +
            amp * math.sin(x * 2.2 * math.pi + ph);
        path.lineTo(x * w, y);
      }
      path
        ..lineTo(w, ht)
        ..close();
      final light = k.isEven;
      final c = light
          ? Color.lerp(p[2], Colors.white, 0.15)!
          : Color.lerp(p[0], Colors.black, 0.2)!;
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              c.withValues(alpha: light ? 0.32 : 0.45),
              c.withValues(alpha: 0.0),
            ],
          ).createShader(Rect.fromLTWH(0, base - amp, w, ht * 0.35)),
      );
    }
  }

  @override
  bool shouldRepaint(_ArtPainter old) => old.h != h;
}
