import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'screens/profile_screen.dart';
import 'screens/server_setup_screen.dart';
import 'screens/shell.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// Switches between setup, connecting, profile picker and the main shell.
class Root extends StatelessWidget {
  const Root({super.key});

  @override
  Widget build(BuildContext context) {
    final stage = context.select<AppState, AppStage>((s) => s.stage);
    Widget child;
    switch (stage) {
      case AppStage.noServer:
        child = const ServerSetupScreen();
      case AppStage.connecting:
        child = const _Connecting();
      case AppStage.connectError:
        child = const _ConnectError();
      case AppStage.chooseProfile:
        child = const ProfileScreen();
      case AppStage.ready:
        child = const Shell();
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: (c, a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: Tween(begin: 0.985, end: 1.0).animate(a),
          child: c,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(stage), child: child),
    );
  }
}

class _Connecting extends StatelessWidget {
  const _Connecting();
  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandLogo(size: 34),
            const SizedBox(height: 36),
            const SizedBox(
              width: 160,
              child: LinearProgressIndicator(minHeight: 3),
            ),
            const SizedBox(height: 16),
            Text(
              '${s.server?.name.isNotEmpty == true ? s.server!.name : s.server?.url ?? ''} sunucusuna bağlanılıyor…',
              style: const TextStyle(color: AppColors.textDim),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectError extends StatelessWidget {
  const _ConnectError();
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      body: EmptyState(
        icon: Icons.wifi_off_rounded,
        title: 'Sunucuya bağlanılamadı',
        message:
            '${s.server?.url ?? ''}\n\n${s.error ?? ''}\n\nSunucunun açık olduğundan ve bu bilgisayarla aynı ağda olduğundan emin ol.',
        action: Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            PillButton(
              primary: true,
              autofocus: true,
              icon: Icons.refresh_rounded,
              label: 'Tekrar dene',
              onPressed: s.retry,
            ),
            PillButton(
              icon: Icons.dns_rounded,
              label: 'Sunucu ayarları',
              onPressed: s.showServerSetup,
            ),
          ],
        ),
      ),
    );
  }
}
