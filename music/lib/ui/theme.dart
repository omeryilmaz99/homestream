import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Dark neumorphic palette: every surface is the background colour, shaped
/// only by a light shadow (top-left) and a dark shadow (bottom-right).
class C {
  static const bg = Color(0xFF202328);
  static const bgDeep = Color(0xFF1A1C20);
  static const light = Color(0xFF2C3036); // highlight shadow
  static const dark = Color(0xFF131518); // depth shadow
  static const raisedTop = Color(0xFF262A2F);
  static const raisedBottom = Color(0xFF1D2024);
  static const accent = Color(0xFF1DB954);
  static const accentHi = Color(0xFF2EE06D);
  static const accentLo = Color(0xFF138A3D);
  static const text = Color(0xFFE9EBEE);
  static const textDim = Color(0xFF9BA1A8);
  static const textFaint = Color(0xFF666C74);
  static const danger = Color(0xFFFF5C6C);
  static const divider = Color(0x14FFFFFF);
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: C.accent,
    onPrimary: Colors.black,
    secondary: C.accent,
    surface: C.bg,
    onSurface: C.text,
    error: C.danger,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: C.bg,
    canvasColor: C.bg,
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: C.text, displayColor: C.text),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: C.bg,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: C.bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: C.bg,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: C.textFaint,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF2E3238),
      contentTextStyle: const TextStyle(color: C.text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.bgDeep,
      hintStyle: const TextStyle(color: C.textFaint),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: C.accent, width: 1.2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : C.textDim,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? C.accent : C.bgDeep,
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: C.accent,
      inactiveTrackColor: C.bgDeep,
      thumbColor: Colors.white,
      overlayColor: Color(0x221DB954),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: C.accent),
    dividerTheme: const DividerThemeData(color: C.divider, thickness: 1),
    listTileTheme: const ListTileThemeData(iconColor: C.textDim),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}

class T {
  static const h1 = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
    color: C.text,
  );
  static const h2 = TextStyle(
    fontSize: 21,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.3,
    color: C.text,
  );
  static const h3 = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: C.text,
  );
  static const body = TextStyle(fontSize: 14.5, color: C.text);
  static const dim = TextStyle(fontSize: 13, color: C.textDim);
  static const faint = TextStyle(fontSize: 12, color: C.textFaint);
}
