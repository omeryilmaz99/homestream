import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/events.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../state/app_state.dart';
import '../theme.dart';

class SoftCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final Gradient? gradient;
  final VoidCallback? onTap;
  final Border? border;
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    this.color,
    this.gradient,
    this.onTap,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return Container(
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? C.card) : null,
        gradient: gradient,
        borderRadius: r,
        boxShadow: C.shadow(),
        border: border,
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: r,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class GradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool busy;
  final double height;
  final Gradient gradient;
  const GradientButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.busy = false,
    this.height = 50,
    this.gradient = C.button,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Opacity(
      opacity: enabled || busy ? 1 : 0.5,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(height / 2.6),
          boxShadow: [
            BoxShadow(
              color: C.teal.withValues(alpha: 0.28),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(height / 2.6),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Text(
                            label,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15.5,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small rounded square button (the back / scan buttons in the design).
class SoftIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final Color? color;
  final Color? background;
  final bool active;
  const SoftIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 40,
    this.color,
    this.background,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final w = Material(
      color: active ? C.teal : (background ?? C.tint),
      borderRadius: BorderRadius.circular(size * 0.32),
      child: InkWell(
        borderRadius: BorderRadius.circular(size * 0.32),
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: size * 0.5,
            color: onPressed == null
                ? C.faint
                : (active ? Colors.white : (color ?? C.teal)),
          ),
        ),
      ),
    );
    return tooltip == null ? w : Tooltip(message: tooltip!, child: w);
  }
}

class GradientText extends StatelessWidget {
  final String text;
  final TextStyle style;
  const GradientText(this.text, {super.key, required this.style});
  @override
  Widget build(BuildContext context) => ShaderMask(
    shaderCallback: (r) => const LinearGradient(
      colors: [C.teal, C.blue],
    ).createShader(r),
    child: Text(text, style: style.copyWith(color: Colors.white)),
  );
}

/// Circular usage ring ("80% Storage Used").
class StorageRing extends StatelessWidget {
  final double value; // 0..1
  final double size;
  final String label;
  const StorageRing({
    super.key,
    required this.value,
    this.size = 120,
    this.label = 'Dolu',
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.clamp(0, 1)),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(v),
          child: Center(
            child: Container(
              width: size * 0.66,
              height: size * 0.66,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: C.shadow(1.4),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '%${(v * 100).round()}',
                    style: TextStyle(
                      fontSize: size * 0.17,
                      fontWeight: FontWeight.w800,
                      color: C.ink,
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: size * 0.07,
                      fontWeight: FontWeight.w600,
                      color: C.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double v;
  _RingPainter(this.v);
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 6;
    final bg = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11;
    canvas.drawCircle(c, r, bg);
    final rect = Rect.fromCircle(center: c, radius: r);
    final fg = Paint()
      ..shader = const SweepGradient(
        startAngle: -pi / 2,
        endAngle: 3 * pi / 2,
        colors: [Color(0xFF8FE3DA), C.teal, Color(0xFF1E9C9A)],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 11;
    canvas.drawArc(rect, -pi / 2, 2 * pi * v, false, fg);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.v != v;
}

class Bar extends StatelessWidget {
  final double value;
  final double height;
  final Color? color;
  final Gradient? gradient;
  const Bar({
    super.key,
    required this.value,
    this.height = 6,
    this.color,
    this.gradient = C.gradient,
  });
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(height),
    child: Container(
      height: height,
      color: C.line,
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: value.clamp(0, 1).toDouble(),
        child: Container(
          decoration: BoxDecoration(
            color: color,
            gradient: color == null ? gradient : null,
            borderRadius: BorderRadius.circular(height),
          ),
        ),
      ),
    ),
  );
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: C.ink,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? text;
  final Widget? action;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.text,
    this.action,
  });
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: C.tint,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 34, color: C.teal),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: C.ink,
            ),
          ),
          if (text != null) ...[
            const SizedBox(height: 6),
            Text(
              text!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: C.muted, height: 1.35),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    ),
  );
}

/// Icon (or image thumbnail) for a file.
class FileIcon extends StatelessWidget {
  final FileItem item;
  final double size;
  final String? thumbUrl; // server thumbnail
  final bool localThumb;
  const FileIcon({
    super.key,
    required this.item,
    this.size = 40,
    this.thumbUrl,
    this.localThumb = false,
  });

  @override
  Widget build(BuildContext context) {
    final k = item.kind;
    final color = kindColor(k);
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(kindIcon(k), color: color, size: size * 0.56),
    );
    if (k == FileKind.image && canThumb(item.name)) {
      final px = (size * MediaQuery.devicePixelRatioOf(context)).round();
      ImageProvider? img;
      if (thumbUrl != null) {
        img = ResizeImage(NetworkImage(thumbUrl!), width: px, policy: ResizeImagePolicy.fit);
      } else if (localThumb && item.size < 40 * 1024 * 1024) {
        img = ResizeImage(FileImage(File(item.path)), width: px, policy: ResizeImagePolicy.fit);
      }
      if (img != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.3),
          child: Image(
            image: img,
            width: size,
            height: size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => fallback,
            frameBuilder: (_, child, frame, sync) =>
                frame == null && !sync ? fallback : child,
          ),
        );
      }
    }
    if (item.link) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          fallback,
          const Positioned(
            right: -2,
            bottom: -2,
            child: Icon(Icons.shortcut_rounded, size: 14, color: C.muted),
          ),
        ],
      );
    }
    return fallback;
  }
}

/// Connection status strip: shown when the live link to the server is down.
class LinkBanner extends StatelessWidget {
  const LinkBanner({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (app.phase != Phase.ready) return const SizedBox.shrink();
    final s = app.link;
    if (s == LinkState.online) return const SizedBox.shrink();
    final since = app.offlineSince;
    final waiting = app.transfers.activeCount;
    final text = s == LinkState.connecting
        ? 'Sunucuya bağlanılıyor…'
        : 'Sunucu bağlantısı koptu${since == null ? '' : ' (${formatAgo(since)})'}. '
              '${waiting > 0 ? 'Aktarımlar duraklatıldı, bağlantı gelince kaldığı yerden devam edecek.' : 'Tekrar bağlanmaya çalışılıyor.'}';
    return Material(
      color: s == LinkState.connecting
          ? C.tint
          : C.warn.withValues(alpha: 0.16),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              s == LinkState.connecting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_off_rounded, color: C.warn, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(fontSize: 13, color: C.text),
                ),
              ),
              if (s == LinkState.offline)
                TextButton(
                  onPressed: app.retryNow,
                  child: const Text('Şimdi dene'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- dialogs & toasts ----

void toast(BuildContext context, String text, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(
            error ? Icons.error_outline_rounded : Icons.check_circle_rounded,
            color: error ? const Color(0xFFFF9AA8) : const Color(0xFF8FE3DA),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
      duration: Duration(seconds: error ? 5 : 3),
    ),
  );
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  String? text,
  String ok = 'Tamam',
  bool danger = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: text == null ? null : Text(text, style: const TextStyle(height: 1.4)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: danger ? C.danger : C.teal,
          ),
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> prompt(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '',
  String ok = 'Kaydet',
  String? Function(String)? validate,
  bool selectStem = false,
}) {
  final ctl = TextEditingController(text: initial);
  if (selectStem && initial.isNotEmpty) {
    final dot = initial.lastIndexOf('.');
    ctl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: dot > 0 ? dot : initial.length,
    );
  } else {
    ctl.selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  }
  String? err;
  return showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) {
        void submit() {
          final v = ctl.text.trim();
          final e = v.isEmpty ? 'Boş olamaz' : validate?.call(v);
          if (e != null) {
            set(() => err = e);
            return;
          }
          Navigator.pop(c, v);
        }

        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: ctl,
            autofocus: true,
            decoration: InputDecoration(hintText: hint, errorText: err),
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Vazgeç'),
            ),
            FilledButton(onPressed: submit, child: Text(ok)),
          ],
        );
      },
    ),
  );
}

/// Valid single file name on every system we deal with.
String? nameError(String v) {
  if (v == '.' || v == '..') return 'Geçersiz ad';
  if (v.contains('/') || v.contains('\\')) return '/ ve \\ kullanılamaz';
  if (RegExp(r'[<>:"|?*]').hasMatch(v)) {
    return 'Şu karakterler kullanılamaz: < > : " | ? *';
  }
  if (v.length > 255) return 'Ad çok uzun';
  return null;
}
