import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'core/platform.dart';
import 'core/prefs.dart';
import 'state/app_state.dart';
import 'ui/root.dart';
import 'ui/theme.dart';
import 'ui/tv_focus.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await AppPlatform.init();
  if (AppPlatform.isTv) {
    // remote control: always show where the focus is
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    installTvFocusFallback();
  }
  if (AppPlatform.isAndroid) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }
  if (AppPlatform.isDesktop) {
    await windowManager.ensureInitialized();
    // HS_FORCE_TV: a 960x540 window has the logical size of a 1080p TV
    final options = WindowOptions(
      size: AppPlatform.isTv ? const Size(960, 540) : const Size(1440, 880),
      minimumSize: AppPlatform.isTv
          ? const Size(960, 540)
          : const Size(960, 600),
      center: true,
      backgroundColor: AppColors.bg,
      title: 'Home Stream',
    );
    windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  // Posters are small (server-resized); allow a generous in-memory cache
  // (smaller on TV boxes, which have little RAM).
  PaintingBinding.instance.imageCache.maximumSizeBytes =
      (AppPlatform.isAndroid ? 160 : 400) << 20;
  PaintingBinding.instance.imageCache.maximumSize = AppPlatform.isAndroid
      ? 600
      : 2000;

  final prefs = await Prefs.load();
  AppTheme.current = AppTheme.byId(prefs.theme);
  final state = AppState(prefs);
  runApp(
    ChangeNotifierProvider.value(value: state, child: const HomeStreamApp()),
  );
  state.start();
  _startTestFrameLog();
}

/// CI memory test only: write the number of rendered frames to a file.
void _startTestFrameLog() {
  const path = String.fromEnvironment('HS_TEST_FRAMELOG');
  if (path.isEmpty) return;
  var frames = 0;
  SchedulerBinding.instance.addTimingsCallback((t) => frames += t.length);
  Timer.periodic(const Duration(seconds: 5), (_) {
    File(path).writeAsStringSync('$frames');
  });
}

class HomeStreamApp extends StatelessWidget {
  const HomeStreamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Home Stream',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      darkTheme: buildTheme(),
      themeMode: ThemeMode.dark,
      shortcuts: {
        ...WidgetsApp.defaultShortcuts,
        // remote control OK / gamepad A
        const SingleActivator(LogicalKeyboardKey.select):
            const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.gameButtonA):
            const ActivateIntent(),
      },
      builder: AppPlatform.isTv ? _tvScale : null,
      home: const Root(),
    );
  }
}

/// TVs report a small logical size (960x540 for 1080p). Lay the app out at a
/// 1280-wide design size and scale it to the screen, so desktop layouts fit.
Widget _tvScale(BuildContext context, Widget? child) {
  const designWidth = 1280.0;
  final mq = MediaQuery.of(context);
  final size = mq.size;
  if (size.width <= 0 || (size.width - designWidth).abs() < 1) {
    return child ?? const SizedBox();
  }
  final s = size.width / designWidth;
  final logical = Size(designWidth, size.height / s);
  return MediaQuery(
    data: mq.copyWith(
      size: logical,
      devicePixelRatio: mq.devicePixelRatio * s,
      padding: mq.padding / s,
      viewPadding: mq.viewPadding / s,
      viewInsets: mq.viewInsets / s,
    ),
    child: FittedBox(
      fit: BoxFit.fill,
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: logical.width,
        height: logical.height,
        child: child,
      ),
    ),
  );
}
