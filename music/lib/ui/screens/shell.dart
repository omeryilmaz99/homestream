import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../audio/handler.dart';
import '../../core/downloads.dart';
import '../../core/platform.dart';
import '../../state/app_state.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/mini_player.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';

class _TabInfo {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final Widget page;
  const _TabInfo(this.icon, this.activeIcon, this.label, this.page);
}

const _tabs = [
  _TabInfo(Icons.home_outlined, Icons.home_rounded, 'Ana Sayfa', HomeScreen()),
  _TabInfo(
    Icons.search_rounded,
    Icons.search_rounded,
    'Keşfet',
    SearchScreen(),
  ),
  _TabInfo(
    Icons.library_music_outlined,
    Icons.library_music_rounded,
    'Kitaplık',
    LibraryScreen(),
  ),
  _TabInfo(
    Icons.person_outline_rounded,
    Icons.person_rounded,
    'Profil',
    ProfileScreen(),
  ),
];

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final _built = <int>{0};
  final _subs = <StreamSubscription<String>>[];

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    void show(String m) {
      if (mounted) showToast(context, m);
    }

    _subs.add(app.messages.listen(show));
    _subs.add(context.read<MusicHandler>().messages.listen(show));
    _subs.add(context.read<Downloads>().messages.listen(show));
    ShellNav.tab.addListener(_onTab);
    WidgetsBinding.instance.addPostFrameCallback((_) => _askBattery());
  }

  void _onTab() {
    setState(() => _built.add(ShellNav.tab.value));
  }

  /// Android may stop background playback to save battery: ask once.
  Future<void> _askBattery() async {
    final app = context.read<AppState>();
    if (!AppPlatform.isAndroid || app.prefs.askedBattery) return;
    if (await AppPlatform.ignoringBatteryOptimizations()) {
      app.prefs.askedBattery = true;
      return;
    }
    if (!mounted) return;
    app.prefs.askedBattery = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Arka planda kesintisiz çalma'),
        content: const Text(
          'Ekran kapalıyken müziğin durmaması için uygulamanın pil kısıtlamasından muaf tutulması önerilir. '
          'Bunu daha sonra Ayarlar\'dan da yapabilirsin.',
          style: T.dim,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Şimdi değil'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('İzin ver'),
          ),
        ],
      ),
    );
    if (ok == true) await AppPlatform.requestIgnoreBatteryOptimizations();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    ShellNav.tab.removeListener(_onTab);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tab = ShellNav.tab.value;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final nav = ShellNav.current;
        if (nav != null && nav.canPop()) {
          nav.pop();
        } else if (ShellNav.tab.value != 0) {
          ShellNav.select(0);
        } else {
          // home tab root: hide the app, the music keeps playing
          AppPlatform.moveToBack();
        }
      },
      child: Scaffold(
        body: Column(
          children: [
            Expanded(
              child: IndexedStack(
                index: tab,
                children: [
                  for (var i = 0; i < _tabs.length; i++)
                    _built.contains(i)
                        ? HeroControllerScope.none(
                            child: Navigator(
                              key: ShellNav.tabKeys[i],
                              onGenerateRoute: (_) =>
                                  ShellNav.route(_tabs[i].page),
                            ),
                          )
                        : const SizedBox.shrink(),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const OfflineBanner(),
            const ColoredBox(color: C.bg, child: MiniPlayer()),
            _NavBar(tab: tab),
          ],
        ),
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  final int tab;
  const _NavBar({required this.tab});
  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(8, 8, 8, bottom + 6),
      decoration: const BoxDecoration(
        color: C.bg,
        border: Border(top: BorderSide(color: C.divider)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _tabs.length; i++)
            Expanded(
              child: _NavItem(
                info: _tabs[i],
                active: i == tab,
                onTap: () => ShellNav.select(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final _TabInfo info;
  final bool active;
  final VoidCallback onTap;
  const _NavItem({
    required this.info,
    required this.active,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final color = active ? C.accentHi : C.textFaint;
    return Semantics(
      button: true,
      selected: active,
      label: info.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: active ? 1.08 : 1,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                active ? info.activeIcon : info.icon,
                color: color,
                size: 25,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              info.label,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: TextStyle(
                fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
