import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/platform.dart';
import '../../core/prefs.dart';
import '../../state/app_state.dart';
import '../layout.dart';
import '../settings_lock.dart';
import '../theme.dart';
import 'browse_screen.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'play_launcher.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import '../widgets/profile_avatar.dart';

/// Main layout: transparent top navigation over the active page.
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => ShellState();
}

class ShellState extends State<Shell> {
  int _index = 0;
  final _searchKey = GlobalKey<SearchScreenState>();
  final _browseKey = GlobalKey<BrowseScreenState>();
  final homeNavFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _testPlay();
  }

  @override
  void dispose() {
    homeNavFocus.dispose();
    super.dispose();
  }

  /// Emulator test only (HS_TEST_PLAY="title|title"): plays the titles one
  /// after another, each when the previous player has been closed.
  Future<void> _testPlay() async {
    const titles = String.fromEnvironment('HS_TEST_PLAY');
    if (titles.isEmpty) return;
    final state = context.read<AppState>();
    state.prefs.playerMode = PlayerMode.internal;
    for (final q in titles.split('|')) {
      await Future.delayed(const Duration(seconds: 4));
      final api = state.api;
      if (!mounted || api == null) return;
      try {
        final it = (await api.search(q)).movies.firstOrNull;
        debugPrint('HSTEST play "$q": ${it?.displayTitle}');
        if (it != null && mounted) await playItem(context, it);
      } catch (e) {
        debugPrint('HSTEST error $e');
      }
    }
    debugPrint('HSTEST done');
  }

  static const _tabs = ['Ana Sayfa', 'Filmler', 'Diziler', 'Klasörler'];

  void go(int i) {
    setState(() => _index = i);
    if (i == 4) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _searchKey.currentState?.focus(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const HomeScreen(),
      const LibraryScreen(series: false),
      const LibraryScreen(series: true),
      BrowseScreen(key: _browseKey),
      SearchScreen(key: _searchKey),
      const SettingsScreen(),
    ];
    final compact = isCompact(context);
    // Back (phone, TV remote): folders go up one level, other pages return
    // to the home tab; only the home tab leaves the app
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_index == 3 && _browseKey.currentState?.goUp() == true) return;
        go(0);
        // the page that had focus is hidden now; with a remote, continue
        // from the "Ana Sayfa" tab
        if (AppPlatform.isTv) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => homeNavFocus.requestFocus(),
          );
        }
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
              go(4),
        },
        child: Scaffold(
          extendBody: true,
          bottomNavigationBar: compact ? _BottomNav(shell: this) : null,
          body: Stack(
            children: [
              Positioned.fill(
                child: IndexedStack(
                  index: _index,
                  children: [
                    for (var i = 0; i < pages.length; i++)
                      TickerMode(enabled: i == _index, child: pages[i]),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: compact
                    ? _CompactTopBar(shell: this)
                    : _TopBar(shell: this),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Phone navigation: Home, Movies, Series, Folders, Search.
class _BottomNav extends StatelessWidget {
  final ShellState shell;
  const _BottomNav({required this.shell});

  @override
  Widget build(BuildContext context) {
    // settings (5) has no tab; keep the last tab highlighted from the top bar
    final sel = shell._index > 4 ? 0 : shell._index;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xE60A0A0F), Color(0xFA0A0A0F)],
        ),
      ),
      child: NavigationBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.accent.withValues(alpha: 0.25),
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        selectedIndex: shell._index > 4 ? sel : shell._index,
        onDestinationSelected: shell.go,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Ana Sayfa',
          ),
          NavigationDestination(
            icon: Icon(Icons.movie_outlined),
            selectedIcon: Icon(Icons.movie_rounded),
            label: 'Filmler',
          ),
          NavigationDestination(
            icon: Icon(Icons.live_tv_outlined),
            selectedIcon: Icon(Icons.live_tv_rounded),
            label: 'Diziler',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder_rounded),
            label: 'Klasörler',
          ),
          NavigationDestination(icon: Icon(Icons.search_rounded), label: 'Ara'),
        ],
      ),
    );
  }
}

/// Phone top bar: logo, settings and the profile menu.
class _CompactTopBar extends StatelessWidget {
  final ShellState shell;
  const _CompactTopBar({required this.shell});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      height: top + 60,
      padding: EdgeInsets.fromLTRB(16, top, 12, 0),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xF00A0A0F), Color(0x000A0A0F)],
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => shell.go(0),
            child: const BrandLogo(size: 20),
          ),
          const Spacer(),
          _NavIcon(
            icon: Icons.settings_rounded,
            tooltip: 'Ayarlar',
            selected: shell._index == 5,
            onTap: () => shell.go(5),
          ),
          const SizedBox(width: 4),
          _ProfileMenu(shell: shell, size: 34),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final ShellState shell;
  const _TopBar({required this.shell});

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 1100;
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xF00A0A0F), Color(0x000A0A0F)],
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => shell.go(0),
            child: const MouseRegion(
              cursor: SystemMouseCursors.click,
              child: BrandLogo(size: 22),
            ),
          ),
          const SizedBox(width: 36),
          for (var i = 0; i < ShellState._tabs.length; i++)
            _NavItem(
              focusNode: i == 0 ? shell.homeNavFocus : null,
              label: ShellState._tabs[i],
              icon: const [
                Icons.home_rounded,
                Icons.movie_rounded,
                Icons.live_tv_rounded,
                Icons.folder_rounded,
              ][i],
              showLabel: wide || true,
              selected: shell._index == i,
              onTap: () => shell.go(i),
            ),
          const Spacer(),
          _NavIcon(
            icon: Icons.search_rounded,
            tooltip: 'Ara (Ctrl+F)',
            selected: shell._index == 4,
            onTap: () => shell.go(4),
          ),
          const SizedBox(width: 6),
          _NavIcon(
            icon: Icons.settings_rounded,
            tooltip: 'Ayarlar',
            selected: shell._index == 5,
            onTap: () => shell.go(5),
          ),
          const SizedBox(width: 14),
          _ProfileMenu(shell: shell),
        ],
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool showLabel;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  const _NavItem({
    this.focusNode,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.showLabel = true,
  });
  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;
  bool _focused = false;
  @override
  Widget build(BuildContext context) {
    final color = _focused
        ? Colors.black
        : widget.selected
        ? Colors.white
        : (_hover ? const Color(0xFFE5E5EA) : AppColors.textDim);
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      mouseCursor: SystemMouseCursors.click,
      onShowHoverHighlight: (v) => setState(() => _hover = v),
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => widget.onTap(),
        ),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(vertical: 18),
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          decoration: BoxDecoration(
            color: _focused ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.label,
                style: TextStyle(
                  color: color,
                  fontSize: 15,
                  fontWeight: widget.selected
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
              ),
              const SizedBox(height: 5),
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                height: 3,
                width: widget.selected ? 22 : 0,
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;
  const _NavIcon({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onTap,
    icon: Icon(
      icon,
      color: selected ? Colors.white : AppColors.textDim,
      size: 26,
    ),
  );
}

class _ProfileMenu extends StatelessWidget {
  final ShellState shell;
  final double size;
  const _ProfileMenu({required this.shell, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = state.profile;
    return PopupMenuButton<String>(
      tooltip: 'Profil',
      offset: const Offset(0, 52),
      onSelected: (v) {
        if (v == 'switch') state.switchProfile();
        if (v == 'settings') shell.go(5);
        if (v == 'server') {
          SettingsLock.ensureUnlocked(context, state.prefs).then((ok) {
            if (ok) state.showServerSetup();
          });
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: Text(
            p?.name ?? '',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'switch',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.people_alt_rounded),
            title: Text('Profil değiştir'),
          ),
        ),
        const PopupMenuItem(
          value: 'server',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.dns_rounded),
            title: Text('Sunucu değiştir'),
          ),
        ),
        const PopupMenuItem(
          value: 'settings',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.settings_rounded),
            title: Text('Ayarlar'),
          ),
        ),
      ],
      child: ProfileAvatar.of(p, size: size, radius: 10),
    );
  }
}
