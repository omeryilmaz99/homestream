import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

import 'audio/handler.dart';
import 'core/downloads.dart';
import 'core/prefs.dart';
import 'state/app_state.dart';
import 'ui/nav.dart';
import 'ui/screens/connect_screen.dart';
import 'ui/screens/profiles_screen.dart';
import 'ui/screens/shell.dart';
import 'ui/theme.dart';
import 'ui/widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: C.bg,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  // big covers: allow a larger in-memory image cache
  PaintingBinding.instance.imageCache.maximumSizeBytes = 120 << 20;

  try {
    MediaKit.ensureInitialized();
    final prefs = await Prefs.load();
    final player = await MusicHandler.create();
    final downloads = Downloads();
    final app = AppState(prefs, player, downloads);
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: app),
          ChangeNotifierProvider.value(value: downloads),
          Provider.value(value: player),
        ],
        child: const MusicApp(),
      ),
    );
    unawaited(app.start());
  } catch (e, st) {
    debugPrint('startup failed: $e\n$st');
    runApp(_StartupError(error: '$e'));
  }
}

class MusicApp extends StatefulWidget {
  const MusicApp({super.key});
  @override
  State<MusicApp> createState() => _MusicAppState();
}

class _MusicAppState extends State<MusicApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final app = context.read<AppState>();
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // remember the song and second right away (the app may be killed)
        app.player.saveNow();
      case AppLifecycleState.resumed:
        if (!app.online && app.api != null) app.ping();
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final stage = context.select<AppState, Stage>((s) => s.stage);
    Widget page;
    switch (stage) {
      case Stage.loading:
        page = const Scaffold(key: ValueKey('loading'), body: LoadingView());
      case Stage.setup:
        page = const ConnectScreen(key: ValueKey('setup'));
      case Stage.profiles:
        page = const ProfilesScreen(key: ValueKey('profiles'));
      case Stage.shell:
        page = const Shell(key: ValueKey('shell'));
    }
    return MaterialApp(
      title: 'Home Müzik',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      navigatorKey: ShellNav.rootKey,
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        child: page,
      ),
    );
  }
}

class _StartupError extends StatelessWidget {
  final String error;
  const _StartupError({required this.error});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: Scaffold(
        body: EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Uygulama başlatılamadı',
          message: '$error\n\nUygulamayı kapatıp yeniden açmayı dene.',
        ),
      ),
    );
  }
}
