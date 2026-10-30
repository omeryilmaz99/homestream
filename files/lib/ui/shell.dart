import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/events.dart';
import '../core/platform.dart';
import '../state/app_state.dart';
import 'item_actions.dart';
import 'screens/connect_screen.dart';
import 'screens/home_screen.dart';
import 'screens/server_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/transfer_screen.dart';
import 'theme.dart';
import 'widgets/common.dart';
import 'widgets/transfers_panel.dart';

/// Chooses between the server picker, the "unreachable" page and the app.
class Root extends StatelessWidget {
  const Root({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    switch (app.phase) {
      case Phase.start:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case Phase.connecting:
        if (app.api == null) {
          return Scaffold(
            body: Container(
              decoration: const BoxDecoration(gradient: C.page),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text('${app.server?.name ?? 'Sunucu'} bağlanıyor…', style: const TextStyle(color: C.muted)),
                  ],
                ),
              ),
            ),
          );
        }
        return const Shell();
      case Phase.needLogin:
        return const ConnectScreen();
      case Phase.unreachable:
        return const UnreachableScreen();
      case Phase.ready:
        return const Shell();
    }
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final tm = context.read<AppState>().transfers;
    tm.onConflict = (info) async {
      if (!mounted) return null;
      return askConflict(context, info);
    };
    AppPlatform.requestNotifications();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<AppState>().resumed();
    }
  }

  void _go(int tab, {int focus = -1}) {
    if (tab == 1) context.read<Workspace>().setFocus(focus);
    setState(() => _tab = tab);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 860;
    final pages = [
      HomeScreen(go: _go),
      const TransferScreen(),
      ServerScreen(visible: _tab == 2),
      const SettingsScreen(),
    ];
    final body = Column(
      children: [
        const LinkBanner(),
        Expanded(
          child: SafeArea(
            top: context.watch<AppState>().link == LinkState.online,
            bottom: false,
            child: IndexedStack(index: _tab, children: pages),
          ),
        ),
      ],
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_tab == 1) {
          final ws = context.read<Workspace>();
          // back = one folder up in the focused pane, then home
          final c = ws.focus == 0 ? ws.local : ws.remote;
          if (c.selected.isNotEmpty) {
            c.clearSelection();
            return;
          }
          if (c.parentPath != null && c.canBack) {
            c.goBack();
            return;
          }
        }
        if (_tab != 0) {
          setState(() => _tab = 0);
          return;
        }
        if (context.read<AppState>().transfers.hasActive) {
          AppPlatform.moveToBack();
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: C.page),
          child: wide ? Row(children: [_Rail(tab: _tab, onTab: _go), Expanded(child: body)]) : body,
        ),
        extendBody: true,
        bottomNavigationBar: wide ? null : _BottomBar(tab: _tab, onTab: _go),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  final int tab;
  final void Function(int) onTab;
  const _Rail({required this.tab, required this.onTab});
  @override
  Widget build(BuildContext context) {
    final tm = context.watch<AppState>().transfers;
    Widget item(int i, IconData icon, String label) {
      final sel = tab == i;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Tooltip(
          message: label,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => onTab(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 64,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                gradient: sel ? C.gradient : null,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Icon(icon, color: sel ? Colors.white : C.teal),
                  const SizedBox(height: 3),
                  Text(label, style: TextStyle(fontSize: 11, color: sel ? Colors.white : C.text)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      width: 88,
      margin: const EdgeInsets.fromLTRB(12, 12, 0, 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: C.shadow()),
      child: Column(
        children: [
          const SizedBox(height: 16),
          ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.asset('assets/icon.png', width: 44, height: 44)),
          const SizedBox(height: 18),
          item(0, Icons.home_rounded, 'Ana sayfa'),
          item(1, Icons.swap_horiz_rounded, 'Aktarım'),
          item(2, Icons.dns_rounded, 'Sunucu'),
          item(3, Icons.settings_rounded, 'Ayarlar'),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Badge(
              isLabelVisible: tm.activeCount > 0,
              label: Text('${tm.activeCount}'),
              backgroundColor: C.teal,
              child: IconButton(
                tooltip: 'Aktarımlar',
                onPressed: () => showTransfers(context),
                icon: const Icon(Icons.swap_vert_rounded, color: C.teal),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom bar from the design: a notch with the round transfer button.
class _BottomBar extends StatelessWidget {
  final int tab;
  final void Function(int) onTab;
  const _BottomBar({required this.tab, required this.onTab});
  @override
  Widget build(BuildContext context) {
    final tm = context.watch<AppState>().transfers;
    final active = tm.activeCount;
    Widget item(int i, IconData icon, IconData outline, String label) => Expanded(
      child: InkResponse(
        onTap: () => onTab(i),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(tab == i ? icon : outline, color: C.teal, size: 27),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: tab == i ? C.teal : C.muted)),
          ],
        ),
      ),
    );
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 86,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            Positioned.fill(
              top: 18,
              child: CustomPaint(painter: _NotchPainter()),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 8,
              child: Row(
                children: [
                  item(0, Icons.home_rounded, Icons.home_outlined, 'Ana sayfa'),
                  item(2, Icons.dns_rounded, Icons.dns_outlined, 'Sunucu'),
                  const SizedBox(width: 84),
                  Expanded(
                    child: InkResponse(
                      onTap: () => showTransfers(context),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Badge(
                            isLabelVisible: active > 0,
                            label: Text('$active'),
                            backgroundColor: C.teal,
                            child: const Icon(Icons.swap_vert_rounded, color: C.teal, size: 27),
                          ),
                          const SizedBox(height: 2),
                          const Text('Kuyruk', style: TextStyle(fontSize: 11, color: C.muted)),
                        ],
                      ),
                    ),
                  ),
                  item(3, Icons.person_rounded, Icons.person_outline_rounded, 'Ayarlar'),
                ],
              ),
            ),
            Positioned(
              top: 0,
              child: GestureDetector(
                onTap: () => onTab(1),
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: tab == 1 ? C.button : C.gradient,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                    boxShadow: [BoxShadow(color: C.teal.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))],
                  ),
                  child: const Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 30),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, cx = w / 2;
    final path = Path()
      ..moveTo(0, 22)
      ..quadraticBezierTo(0, 0, 22, 0)
      ..lineTo(cx - 62, 0)
      ..cubicTo(cx - 40, 0, cx - 40, 30, cx, 30)
      ..cubicTo(cx + 40, 30, cx + 40, 0, cx + 62, 0)
      ..lineTo(w - 22, 0)
      ..quadraticBezierTo(w, 0, w, 22)
      ..lineTo(w, h + 40)
      ..lineTo(0, h + 40)
      ..close();
    canvas.drawShadow(path, const Color(0x332B6F7A), 10, false);
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

