import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'core/prefs.dart';
import 'state/app_state.dart';
import 'ui/root.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1440, 880),
      minimumSize: Size(960, 600),
      center: true,
      backgroundColor: AppColors.bg,
      title: 'Home Stream',
    );
    windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  // Posters are small (server-resized); allow a generous in-memory cache.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 400 << 20;
  PaintingBinding.instance.imageCache.maximumSize = 2000;

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
      home: const Root(),
    );
  }
}
