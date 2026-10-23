import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

// Surface primitives. The names come from the first (neumorphic) design;
// they now draw flat dark cards with a hairline edge.

enum NeuStyle { raised, flat, inset }

/// Soft drop shadow for floating elements (covers, mini player).
List<BoxShadow> neuShadows({double depth = 1}) => depth <= 0
    ? const []
    : [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.35),
          offset: Offset(0, 6 * depth),
          blurRadius: 18 * depth,
        ),
      ];

BoxDecoration neuDecoration({
  NeuStyle style = NeuStyle.raised,
  BorderRadius? radius,
  bool circle = false,
  double depth = 1,
  Color? color,
}) {
  final shape = circle ? BoxShape.circle : BoxShape.rectangle;
  final r = circle ? null : (radius ?? BorderRadius.circular(16));
  switch (style) {
    case NeuStyle.raised:
      return BoxDecoration(
        shape: shape,
        borderRadius: r,
        color: color ?? C.surface,
        border: color == null ? Border.all(color: C.border, width: 0.8) : null,
      );
    case NeuStyle.flat:
      return BoxDecoration(shape: shape, borderRadius: r, color: color ?? C.bg);
    case NeuStyle.inset:
      return BoxDecoration(
        shape: shape,
        borderRadius: r,
        color: color ?? C.surfaceHi,
      );
  }
}

class NeuBox extends StatelessWidget {
  final Widget? child;
  final NeuStyle style;
  final double radius;
  final bool circle;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;
  final double depth;
  final Color? color;
  const NeuBox({
    super.key,
    this.child,
    this.style = NeuStyle.raised,
    this.radius = 18,
    this.circle = false,
    this.padding,
    this.width,
    this.height,
    this.depth = 1,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: padding,
      decoration: neuDecoration(
        style: style,
        radius: BorderRadius.circular(radius),
        circle: circle,
        depth: depth,
        color: color,
      ),
      // own Material so list tiles and ink splashes inside stay visible
      child: child == null
          ? null
          : Material(type: MaterialType.transparency, child: child),
    );
  }
}

/// A card-like button that shrinks a little while pressed.
class NeuButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double radius;
  final bool circle;
  final EdgeInsetsGeometry padding;
  final double? width;
  final double? height;
  final bool active; // drawn pressed-in (e.g. selected tab)
  final Color? color;
  final double depth;
  final String? tooltip;
  const NeuButton({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.radius = 18,
    this.circle = false,
    this.padding = EdgeInsets.zero,
    this.width,
    this.height,
    this.active = false,
    this.color,
    this.depth = 1,
    this.tooltip,
  });

  @override
  State<NeuButton> createState() => _NeuButtonState();
}

class _NeuButtonState extends State<NeuButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    final base = widget.color ?? (widget.active ? null : C.surface);
    Widget box = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      width: widget.width,
      height: widget.height,
      padding: widget.padding,
      decoration: BoxDecoration(
        shape: widget.circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: widget.circle
            ? null
            : BorderRadius.circular(widget.radius),
        color: base == null
            ? C.accent.withValues(alpha: 0.16)
            : (_down ? Color.lerp(base, Colors.white, 0.06) : base),
        border: widget.color == null
            ? Border.all(
                color: widget.active
                    ? C.accent.withValues(alpha: 0.45)
                    : C.border,
                width: 0.8,
              )
            : null,
      ),
      child: Center(widthFactor: 1, heightFactor: 1, child: widget.child),
    );
    box = AnimatedScale(
      scale: _down ? 0.96 : 1,
      duration: const Duration(milliseconds: 120),
      child: box,
    );
    box = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTap: widget.onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress,
      child: Opacity(opacity: enabled ? 1 : 0.45, child: box),
    );
    if (widget.tooltip != null) {
      box = Tooltip(message: widget.tooltip!, child: box);
    }
    return Semantics(button: true, child: box);
  }
}

/// Round icon button.
class NeuIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final bool accent; // purple filled (play buttons)
  final bool active; // purple icon
  final bool plain; // no background (top bars)
  final Color? iconColor;
  final String? tooltip;
  const NeuIconButton(
    this.icon, {
    super.key,
    this.onTap,
    this.size = 46,
    this.iconSize = 22,
    this.accent = false,
    this.active = false,
    this.iconColor,
    this.tooltip,
    this.plain = false,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        iconColor ??
        (accent
            ? Colors.white
            : active
            ? C.accentHi
            : C.text);
    if (plain) {
      return SizedBox(
        width: size,
        height: size,
        child: IconButton(
          tooltip: tooltip,
          onPressed: onTap,
          padding: EdgeInsets.zero,
          icon: Icon(icon, size: iconSize, color: color),
        ),
      );
    }
    return NeuButton(
      circle: true,
      width: size,
      height: size,
      onTap: onTap,
      active: active,
      tooltip: tooltip,
      color: accent ? C.accent : null,
      child: Icon(icon, size: iconSize, color: color),
    );
  }
}

/// Purple pill button ("Oyna").
class AccentPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  const AccentPill(this.label, {super.key, this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return NeuButton(
      onTap: onTap,
      radius: 30,
      color: C.accent,
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

/// Thin seek bar: grey track, purple fill, white knob.
class NeuSeekBar extends StatefulWidget {
  final double value; // 0..1
  final double buffered; // 0..1
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final double height;
  const NeuSeekBar({
    super.key,
    required this.value,
    this.buffered = 0,
    this.onChanged,
    this.onChangeEnd,
    this.height = 4,
  });

  @override
  State<NeuSeekBar> createState() => _NeuSeekBarState();
}

class _NeuSeekBarState extends State<NeuSeekBar> {
  double? _drag;

  double _at(Offset local, double width) => (local.dx / width).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final v = (_drag ?? widget.value).clamp(0.0, 1.0);
        final dragging = _drag != null;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: widget.onChanged == null
              ? null
              : (d) => setState(() => _drag = _at(d.localPosition, w)),
          onHorizontalDragUpdate: widget.onChanged == null
              ? null
              : (d) {
                  setState(() => _drag = _at(d.localPosition, w));
                  widget.onChanged!(_drag!);
                },
          onHorizontalDragEnd: widget.onChanged == null
              ? null
              : (_) {
                  final x = _drag ?? v;
                  setState(() => _drag = null);
                  widget.onChangeEnd?.call(x);
                },
          onTapUp: widget.onChangeEnd == null
              ? null
              : (d) => widget.onChangeEnd!(_at(d.localPosition, w)),
          child: SizedBox(
            height: 28,
            child: Stack(
              alignment: Alignment.centerLeft,
              clipBehavior: Clip.none,
              children: [
                Container(
                  height: widget.height,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(widget.height),
                  ),
                ),
                if (widget.buffered > 0)
                  Container(
                    width: w * widget.buffered.clamp(0.0, 1.0),
                    height: widget.height,
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(widget.height),
                    ),
                  ),
                Container(
                  width: w * v,
                  height: widget.height,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [C.accentLo, C.accent, C.accentHi],
                    ),
                    borderRadius: BorderRadius.circular(widget.height),
                  ),
                ),
                Positioned(
                  left: (w * v - (dragging ? 9 : 7)).clamp(-2, w - 12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: dragging ? 18 : 14,
                    height: dragging ? 18 : 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: C.accent, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: C.accent.withValues(alpha: 0.45),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
