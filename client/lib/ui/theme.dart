import 'package:flutter/material.dart';

class AppColors {
  static const bg = Color(0xFF0A0A0F);
  static const surface = Color(0xFF14141C);
  static const surface2 = Color(0xFF1C1C27);
  static const surface3 = Color(0xFF262634);
  static const border = Color(0x1FFFFFFF);
  static const text = Color(0xFFF5F5F7);
  static const textDim = Color(0xFFB4B4C2);
  static const textMuted = Color(0xFF7C7C8E);
  static const accent = Color(0xFF8B5CF6);
  static const accent2 = Color(0xFFEC4899);
  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);

  static const brandGradient = LinearGradient(
    colors: [accent, accent2],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

Color parseHexColor(String hex, [Color fallback = AppColors.accent]) {
  var h = hex.replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return v == null ? fallback : Color(v);
}

ThemeData buildTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.dark,
      surface: AppColors.surface,
      primary: AppColors.accent,
      secondary: AppColors.accent2,
    ),
    scaffoldBackgroundColor: AppColors.bg,
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surface2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.surface3,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: const TextStyle(color: AppColors.text, fontSize: 12),
      waitDuration: const Duration(milliseconds: 500),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface2,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
      ),
      hintStyle: const TextStyle(color: AppColors.textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surface3,
      contentTextStyle: const TextStyle(color: AppColors.text),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      width: 420,
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: AppColors.accent,
      thumbColor: Colors.white,
      inactiveTrackColor: Color(0x33FFFFFF),
      overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? Colors.white
            : AppColors.textMuted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? AppColors.accent
            : AppColors.surface3,
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(const Color(0x33FFFFFF)),
      radius: const Radius.circular(8),
      thickness: WidgetStateProperty.all(6),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}

/// The Home Stream wordmark.
class BrandLogo extends StatelessWidget {
  final double size;
  const BrandLogo({super.key, this.size = 22});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size * 1.35,
          height: size * 1.35,
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(size * 0.38),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withValues(alpha: 0.45),
                blurRadius: size * 0.8,
              ),
            ],
          ),
          child: Icon(
            Icons.play_arrow_rounded,
            color: Colors.white,
            size: size,
          ),
        ),
        SizedBox(width: size * 0.45),
        ShaderMask(
          shaderCallback: (r) => const LinearGradient(
            colors: [Colors.white, Color(0xFFE9D5FF)],
          ).createShader(r),
          child: Text(
            'Home Stream',
            style: TextStyle(
              fontSize: size,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

/// Primary (white) and secondary (glass) pill buttons used across the app.
class PillButton extends StatefulWidget {
  final IconData? icon;
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final bool autofocus;
  final double height;
  const PillButton({
    super.key,
    this.icon,
    required this.label,
    this.onPressed,
    this.primary = false,
    this.autofocus = false,
    this.height = 46,
  });

  @override
  State<PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<PillButton> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final active = _hover || _focus;
    final bg = widget.primary
        ? (active ? const Color(0xFFE8E8EE) : Colors.white)
        : (active ? const Color(0x40FFFFFF) : const Color(0x26FFFFFF));
    final fg = widget.primary ? Colors.black : Colors.white;
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      enabled: enabled,
      mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onShowHoverHighlight: (v) => setState(() => _hover = v),
      onShowFocusHighlight: (v) => setState(() => _focus = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => widget.onPressed?.call(),
        ),
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: active ? 1.04 : 1,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: widget.height,
            padding: EdgeInsets.symmetric(horizontal: widget.height * 0.5),
            decoration: BoxDecoration(
              color: enabled ? bg : bg.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(widget.height / 2),
              border: _focus
                  ? Border.all(color: AppColors.accent, width: 2)
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, color: fg, size: widget.height * 0.55),
                  const SizedBox(width: 8),
                ],
                Text(
                  widget.label,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w700,
                    fontSize: widget.height * 0.34,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Round icon button with hover glow.
class CircleIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final bool active;
  const CircleIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 44,
    this.active = false,
  });

  @override
  State<CircleIconButton> createState() => _CircleIconButtonState();
}

class _CircleIconButtonState extends State<CircleIconButton> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final btn = FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      onShowHoverHighlight: (v) => setState(() => _hover = v),
      onShowFocusHighlight: (v) => setState(() => _hover = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => widget.onPressed?.call(),
        ),
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.active
                ? Colors.white
                : (_hover ? const Color(0x40FFFFFF) : const Color(0x1AFFFFFF)),
            border: Border.all(color: const Color(0x55FFFFFF), width: 1.2),
          ),
          child: Icon(
            widget.icon,
            size: widget.size * 0.5,
            color: widget.active ? Colors.black : Colors.white,
          ),
        ),
      ),
    );
    return widget.tooltip == null
        ? btn
        : Tooltip(message: widget.tooltip!, child: btn);
  }
}
