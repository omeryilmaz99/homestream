import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Dark palette with a purple accent: flat surfaces a little lighter than
/// the background, soft gradients only on covers and highlights.
class C {
  static const bg = Color(0xFF0F0F13);
  static const bgDeep = Color(0xFF0A0A0D);
  static const surface = Color(0xFF18181E); // cards, list rows
  static const surfaceHi = Color(0xFF222229); // buttons, pressed cards
  static const border = Color(0x12FFFFFF);
  // kept for older call sites
  static const light = surfaceHi;
  static const dark = Color(0xFF000000);
  static const raisedTop = surfaceHi;
  static const raisedBottom = surface;
  static const accent = Color(0xFF7C6CF6);
  static const accentHi = Color(0xFFA698FF);
  static const accentLo = Color(0xFF5A48D8);
  static const pink = Color(0xFFE56FAE);
  static const text = Color(0xFFF4F4F8);
  static const textDim = Color(0xFFA3A3B2);
  static const textFaint = Color(0xFF6C6C7A);
  static const danger = Color(0xFFFF5C7A);
  static const divider = Color(0x0FFFFFFF);
}

/// Purple-pink gradient used for highlights (hero card, liked songs).
const accentGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF4B3FD0), Color(0xFF8B6CF0), Color(0xFFE77FB8)],
  stops: [0, 0.55, 1],
);

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: C.accent,
    onPrimary: Colors.white,
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
      backgroundColor: C.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: C.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: C.textFaint,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: C.surfaceHi,
      contentTextStyle: const TextStyle(color: C.text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.surface,
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
        (s) => s.contains(WidgetState.selected) ? C.accent : C.surfaceHi,
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: C.accent,
      inactiveTrackColor: C.surfaceHi,
      thumbColor: Colors.white,
      overlayColor: Color(0x227C6CF6),
      trackHeight: 4,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: C.accent,
        foregroundColor: Colors.white,
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: C.accentHi),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? C.accent : C.textFaint,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: C.surfaceHi,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: C.surfaceHi,
      side: BorderSide.none,
      shape: StadiumBorder(),
      labelStyle: TextStyle(color: C.text),
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
    fontSize: 27,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
    color: C.text,
  );
  static const h2 = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.2,
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
  static const link = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
    color: C.accentHi,
  );
}
