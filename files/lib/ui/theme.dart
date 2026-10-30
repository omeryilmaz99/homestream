import 'package:flutter/material.dart';

/// Light, airy look from the design: mint background, white cards,
/// blue → teal gradients.
class C {
  static const teal = Color(0xFF2BB3B1);
  static const tealDark = Color(0xFF1E9C9A);
  static const blue = Color(0xFF6C9FDF);
  static const sky = Color(0xFF8CC3EE);
  static const ink = Color(0xFF1D3640);
  static const text = Color(0xFF2E4A54);
  static const muted = Color(0xFF7D939B);
  static const faint = Color(0xFFB8C7CC);
  static const line = Color(0xFFE3EEF0);
  static const card = Colors.white;
  static const bg = Color(0xFFEFF8F7);
  static const bg2 = Color(0xFFE4F1F4);
  static const tint = Color(0xFFE6F6F5);
  static const danger = Color(0xFFE5677A);
  static const warn = Color(0xFFE9A23B);
  static const ok = Color(0xFF3CB97F);

  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7FB1E9), Color(0xFF39C1BA)],
  );
  static const gradientSoft = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF9BC6F0), Color(0xFF5ACBC4)],
  );
  static const button = LinearGradient(
    colors: [Color(0xFF34BDB8), Color(0xFF27AAA8)],
  );
  static const page = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE6F7F1), Color(0xFFF4FAFC), Color(0xFFE5F1F6)],
  );

  static List<BoxShadow> shadow([double o = 1]) => [
    BoxShadow(
      color: const Color(0xFF2B6F7A).withValues(alpha: 0.08 * o),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: C.teal,
      primary: C.teal,
      secondary: C.blue,
      surface: C.card,
      error: C.danger,
    ),
    scaffoldBackgroundColor: C.bg,
    visualDensity: VisualDensity.standard,
  );
  final t = base.textTheme.apply(bodyColor: C.text, displayColor: C.ink);
  return base.copyWith(
    textTheme: t.copyWith(
      titleLarge: t.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: C.ink,
      ),
      titleMedium: t.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: C.ink,
      ),
    ),
    dividerTheme: const DividerThemeData(color: C.line, space: 1),
    iconTheme: const IconThemeData(color: C.text),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF3F8F9),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: C.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: C.teal, width: 1.6),
      ),
      hintStyle: const TextStyle(color: C.faint),
      labelStyle: const TextStyle(color: C.muted),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: const TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        color: C.ink,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 6,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: C.ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : null,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? C.teal : null,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? C.teal : null,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: C.teal,
      linearTrackColor: C.line,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: C.ink.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
      ),
      waitDuration: const Duration(milliseconds: 500),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(C.faint.withValues(alpha: 0.6)),
      radius: const Radius.circular(8),
      thickness: WidgetStateProperty.all(6),
    ),
  );
}
