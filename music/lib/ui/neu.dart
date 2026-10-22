import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

enum NeuStyle { raised, flat, inset }

/// Soft "extruded" shadows: light from the top-left, depth to the bottom-right.
List<BoxShadow> neuShadows({double depth = 1}) => [
  BoxShadow(
    color: C.dark.withValues(alpha: 0.9),
    offset: Offset(5 * depth, 5 * depth),
    blurRadius: 12 * depth,
  ),
  BoxShadow(
    color: C.light.withValues(alpha: 0.75),
    offset: Offset(-4 * depth, -4 * depth),
    blurRadius: 10 * depth,
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
  final r = circle ? null : (radius ?? BorderRadius.circular(18));
  switch (style) {
    case NeuStyle.raised:
      return BoxDecoration(
        shape: shape,
        borderRadius: r,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: color == null
              ? const [C.raisedTop, C.raisedBottom]
              : [Color.lerp(color, Colors.white, 0.08)!, color],
        ),
        boxShadow: neuShadows(depth: depth),
      );
    case NeuStyle.flat:
      return BoxDecoration(shape: shape, borderRadius: r, color: color ?? C.bg);
    case NeuStyle.inset:
      // Flutter has no inner shadows: a dark-to-light gradient and a hairline
      // edge read as a pressed-in surface.
      return BoxDecoration(
        shape: shape,
        borderRadius: r,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF16181B), Color(0xFF22252A)],
        ),
        border: Border.all(color: const Color(0x0DFFFFFF), width: 0.8),
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
      child: child,
    );
  }
}

/// A raised surface that sinks in while pressed.
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
    final pressed = _down || widget.active;
    final enabled = widget.onTap != null || widget.onLongPress != null;
    Widget box = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      width: widget.width,
      height: widget.height,
      padding: widget.padding,
      decoration: neuDecoration(
        style: pressed && widget.color == null
            ? NeuStyle.inset
            : NeuStyle.raised,
        radius: BorderRadius.circular(widget.radius),
        circle: widget.circle,
        depth: pressed ? 0.35 : widget.depth,
        color: widget.color,
      ),
      child: Center(widthFactor: 1, heightFactor: 1, child: widget.child),
    );
    box = AnimatedScale(
      scale: _down ? 0.95 : 1,
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

/// Round neumorphic icon button.
class NeuIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final bool accent; // green filled (play buttons)
  final bool active; // pressed in, green icon
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
  });

  @override
  Widget build(BuildContext context) {
    return NeuButton(
      circle: true,
      width: size,
      height: size,
      onTap: onTap,
      active: active,
      tooltip: tooltip,
      color: accent ? C.accent : null,
      child: Icon(
        icon,
        size: iconSize,
        color:
            iconColor ??
            (accent
                ? Colors.black
                : active
                ? C.accent
                : C.text),
      ),
    );
  }
}

/// Green pill button ("ÇAL").
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
            Icon(icon, color: Colors.black, size: 22),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

/// Neumorphic seek bar: an inset groove with a green fill and a raised knob.
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
    this.height = 8,
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
                  decoration: neuDecoration(
                    style: NeuStyle.inset,
                    radius: BorderRadius.circular(widget.height),
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
                    boxShadow: [
                      BoxShadow(
                        color: C.accent.withValues(alpha: 0.35),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: (w * v - (dragging ? 11 : 9)).clamp(-2, w - 16),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: dragging ? 22 : 18,
                    height: dragging ? 22 : 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFF4F6F8), Color(0xFFB8BEC6)],
                      ),
                      boxShadow: neuShadows(depth: 0.5),
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
