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
  if (AppPlatform.isTv) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  } else if (AppPlatform.isAndroid) {
    // phones keep the status bar; the player goes full screen on its own
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Color(0x00000000),
        systemNavigationBarColor: Color(0x00000000),
        statusBarIconBrightness: Brightness.light,
      ),
    );
  }
  if (AppPlatform.isDesktop) {
    await windowManager.ensureInitialized();
    // HS_FORCE_TV: a 960x540 window has the logical size of a 1080p TV
    final options = WindowOptions(
      size: AppPlatform.isTv
          ? const Size(960, 540)
          : AppPlatform.isPhone
          ? const Size(412, 860)
          : const Size(1440, 880),
      minimumSize: AppPlatform.isTv
          ? const Size(960, 540)
          : AppPlatform.isPhone
          ? const Size(320, 500)
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

  final Prefs prefs;
  try {
    prefs = await Prefs.load();
  } catch (e) {
    // never sit on the splash screen: show what went wrong instead
    runApp(_StartupError('$e'));
    return;
  }
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
      builder: AppPlatform.isTv
          ? _tvScale
          : (AppPlatform.isPhone && AppPlatform.isDesktop)
          ? _fakePhoneInsets
          : null,
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

/// Shown when the app cannot even load its settings.
class _StartupError extends StatelessWidget {
  final String message;
  const _StartupError(this.message);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Home Stream başlatılamadı.\n\n$message',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

/// Phone simulation on desktop: pretend there is a status and gesture bar.
Widget _fakePhoneInsets(BuildContext context, Widget? child) {
  final mq = MediaQuery.of(context);
  const pad = EdgeInsets.only(top: 32, bottom: 24);
  return MediaQuery(
    data: mq.copyWith(padding: pad, viewPadding: pad),
    child: child ?? const SizedBox(),
  );
}
