import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/prefs.dart';
import 'state/app_state.dart';
import 'ui/screens/transfer_screen.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  final prefs = await Prefs.load();
  final app = AppState(prefs);
  await app.init();
  runApp(HomeDosyaApp(app: app));
}

class HomeDosyaApp extends StatelessWidget {
  final AppState app;
  const HomeDosyaApp({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: app),
        ChangeNotifierProvider(create: (_) => Workspace(app)),
      ],
      child: MaterialApp(
        title: 'Home Dosya',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        locale: const Locale('tr'),
        home: const Root(),
      ),
    );
  }
}
