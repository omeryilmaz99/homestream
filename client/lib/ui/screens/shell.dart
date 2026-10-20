import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../theme.dart';
import 'browse_screen.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

/// Main layout: transparent top navigation over the active page.
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => ShellState();
}

class ShellState extends State<Shell> {
  int _index = 0;
  final _searchKey = GlobalKey<SearchScreenState>();

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
      const BrowseScreen(),
      SearchScreen(key: _searchKey),
      const SettingsScreen(),
    ];
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            go(4),
      },
      child: Scaffold(
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
            Positioned(left: 0, right: 0, top: 0, child: _TopBar(shell: this)),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final ShellState shell;
  const _TopBar({required this.shell});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = state.profile;
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
          PopupMenuButton<String>(
            tooltip: 'Profil',
            offset: const Offset(0, 52),
            onSelected: (v) {
              if (v == 'switch') state.switchProfile();
              if (v == 'settings') shell.go(5);
              if (v == 'server') state.showServerSetup();
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
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: LinearGradient(
                  colors: [
                    parseHexColor(p?.color ?? ''),
                    Color.lerp(
                      parseHexColor(p?.color ?? ''),
                      Colors.black,
                      0.45,
                    )!,
                  ],
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                p?.avatar.isNotEmpty == true
                    ? p!.avatar
                    : (p?.name.isNotEmpty == true
                          ? p!.name.characters.first
                          : '?'),
                style: const TextStyle(fontSize: 20),
              ),
            ),
          ),
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
  const _NavItem({
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
