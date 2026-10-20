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
  static Color get accent => AppTheme.current.accent;
  static Color get accent2 => AppTheme.current.accent2;
  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);

  static LinearGradient get brandGradient => LinearGradient(
    colors: [accent, accent2],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

Color parseHexColor(String hex, [Color? fallback]) {
  var h = hex.replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return v == null ? (fallback ?? AppColors.accent) : Color(v);
}

/// A named accent colour pair.
class ThemePreset {
  final String id;
  final String name;
  final Color accent;
  final Color accent2;
  const ThemePreset(this.id, this.name, this.accent, this.accent2);
}

/// App-wide accent theme. Changing it rebuilds the whole widget tree.
class AppTheme {
  static const presets = [
    ThemePreset('violet', 'Mor Gece', Color(0xFF8B5CF6), Color(0xFFEC4899)),
    ThemePreset('ocean', 'Okyanus', Color(0xFF06B6D4), Color(0xFF3B82F6)),
    ThemePreset('sunset', 'Gün Batımı', Color(0xFFF97316), Color(0xFFEF4444)),
    ThemePreset('emerald', 'Zümrüt', Color(0xFF10B981), Color(0xFF84CC16)),
    ThemePreset(
      'cinema',
      'Sinema',
      Color(0xFFE50914),
      Color(0xFFFF5F6D),
    ),
    ThemePreset('gold', 'Altın Saat', Color(0xFFF59E0B), Color(0xFFF43F5E)),
    ThemePreset(
      'aurora',
      'Kuzey Işıkları',
      Color(0xFF22D3EE),
      Color(0xFFA78BFA),
    ),
    ThemePreset('rose', 'Gül Kurusu', Color(0xFFF472B6), Color(0xFFFB923C)),
  ];

  static ThemePreset current = presets.first;

  static ThemePreset byId(String? id) =>
      presets.firstWhere((p) => p.id == id, orElse: () => presets.first);

  static void apply(ThemePreset p) {
    if (p.id == current.id) return;
    current = p;
    void rebuild(Element e) {
      e.markNeedsBuild();
      e.visitChildren(rebuild);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(rebuild);
  }
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
        borderSide: BorderSide(color: AppColors.accent, width: 1.5),
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
    sliderTheme: SliderThemeData(
      activeTrackColor: AppColors.accent,
      thumbColor: Colors.white,
      inactiveTrackColor: const Color(0x33FFFFFF),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
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
          shaderCallback: (r) => LinearGradient(
            colors: [
              Colors.white,
              Color.lerp(Colors.white, AppColors.accent, 0.3)!,
            ],
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
