import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/discovery.dart';
import '../../core/prefs.dart';
import '../../state/app_state.dart';
import '../../core/platform.dart';
import '../theme.dart';

/// First-run / "add server" screen: auto discovery + manual address.
class ServerSetupScreen extends StatefulWidget {
  const ServerSetupScreen({super.key});
  @override
  State<ServerSetupScreen> createState() => _ServerSetupScreenState();
}

class _ServerSetupScreenState extends State<ServerSetupScreen> {
  final _address = TextEditingController();
  final _name = TextEditingController();
  List<DiscoveredServer> _found = [];
  bool _searching = false;
  bool _testing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _discover();
  }

  @override
  void dispose() {
    _address.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _discover() async {
    setState(() => _searching = true);
    final res = await discoverServers();
    if (!mounted) return;
    setState(() {
      _found = res;
      _searching = false;
    });
  }

  Future<void> _connectTo(String name, String url) async {
    setState(() {
      _testing = true;
      _error = null;
    });
    final normalized = normalizeServerUrl(url);
    final client = ApiClient(normalized);
    try {
      final info = await client.info(timeout: const Duration(seconds: 6));
      if (!mounted) return;
      final state = context.read<AppState>();
      final s = state.addServer(name.isNotEmpty ? name : info.name, normalized);
      await state.connect(s, forceProfilePicker: true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      client.close();
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final saved = state.servers;
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: AnimatedBackdrop()),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: BrandLogo(size: 36)),
                    const SizedBox(height: 14),
                    const Text(
                      'Ev sunucundaki filmler ve diziler, tek yerde.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textDim, fontSize: 16),
                    ),
                    const SizedBox(height: 32),
                    _Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'Ağdaki sunucular',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Spacer(),
                              if (_searching)
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              else
                                IconButton(
                                  tooltip: 'Yeniden ara',
                                  onPressed: _discover,
                                  icon: const Icon(Icons.refresh_rounded),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if (!_searching && _found.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                'Otomatik bulunamadı. Aşağıya sunucunun adresini yazabilirsin.',
                                style: TextStyle(color: AppColors.textMuted),
                              ),
                            ),
                          for (final (i, d) in _found.indexed)
                            _ServerTile(
                              autofocus: i == 0,
                              icon: Icons.dns_rounded,
                              title: d.name,
                              subtitle: d.url,
                              onTap: _testing
                                  ? null
                                  : () => _connectTo(d.name, d.url),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Adresle bağlan',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _address,
                            // on TV this would pop the keyboard right away
                            autofocus: _found.isEmpty && AppPlatform.isDesktop && !AppPlatform.isPhone,
                            decoration: const InputDecoration(
                              hintText: 'Örnek: 192.168.50.200',
                              prefixIcon: Icon(Icons.link_rounded),
                            ),
                            onSubmitted: (_) =>
                                _connectTo(_name.text.trim(), _address.text),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _name,
                            decoration: const InputDecoration(
                              hintText:
                                  'İsim (isteğe bağlı), örnek: Ev Sunucusu',
                              prefixIcon: Icon(Icons.label_outline_rounded),
                            ),
                            onSubmitted: (_) =>
                                _connectTo(_name.text.trim(), _address.text),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              style: const TextStyle(color: AppColors.danger),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Align(
                            alignment: Alignment.centerRight,
                            child: PillButton(
                              primary: true,
                              icon: _testing
                                  ? null
                                  : Icons.arrow_forward_rounded,
                              label: _testing ? 'Bağlanıyor…' : 'Bağlan',
                              onPressed: _testing
                                  ? null
                                  : () => _connectTo(
                                      _name.text.trim(),
                                      _address.text,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (saved.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Kayıtlı sunucular',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ...saved.map(
                              (s) => _ServerTile(
                                icon: Icons.bookmark_rounded,
                                title: s.name.isNotEmpty ? s.name : s.url,
                                subtitle: s.url,
                                onTap: () =>
                                    state.connect(s, forceProfilePicker: true),
                                trailing: IconButton(
                                  tooltip: 'Kaldır',
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: AppColors.textMuted,
                                  ),
                                  onPressed: () => _confirmRemove(s),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemove(ServerConfig s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sunucu kaldırılsın mı?'),
        content: Text(
          '${s.name.isNotEmpty ? s.name : s.url} bu cihazdan kaldırılacak. Sunucudaki hiçbir şey silinmez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Kaldır'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      final state = context.read<AppState>();
      state.prefs.servers = state.prefs.servers
          .where((e) => e.id != s.id)
          .toList();
      state.prefs.setLastProfile(s.id, null);
      setState(() {});
    }
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: AppColors.surface.withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.border),
    ),
    child: child,
  );
}

class _ServerTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool autofocus;
  const _ServerTile({
    this.autofocus = false,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
  });
  @override
  State<_ServerTile> createState() => _ServerTileState();
}

class _ServerTileState extends State<_ServerTile> {
  bool _hover = false;
  bool _focused = false;
  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      mouseCursor: SystemMouseCursors.click,
      onShowHoverHighlight: (v) => setState(() => _hover = v),
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => widget.onTap?.call(),
        ),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _hover || _focused ? AppColors.surface3 : AppColors.surface2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _focused ? Colors.white : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(widget.icon, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      widget.subtitle,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              widget.trailing ??
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textMuted,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Slowly drifting colored blobs behind the setup / profile screens.
/// Soft colour blobs behind the setup and profile screens. Painted once
/// (static) so an idle screen renders no frames at all.
class AnimatedBackdrop extends StatelessWidget {
  const AnimatedBackdrop({super.key});

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _BlobPainter(AppColors.accent, AppColors.accent2),
      child: const SizedBox.expand(),
    ),
  );
}

class _BlobPainter extends CustomPainter {
  final Color a, b;
  _BlobPainter(this.a, this.b);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.bg);
    void blob(Color c, double fx, double fy, double r) {
      final center = Offset(size.width * fx, size.height * fy);
      final radius = size.shortestSide * r;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [c.withValues(alpha: 0.35), c.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    blob(a, 0.18, 0.2, 0.75);
    blob(b, 0.85, 0.8, 0.6);
    blob(const Color(0xFF3B82F6), 0.75, 0.15, 0.5);
  }

  @override
  bool shouldRepaint(covariant _BlobPainter old) => old.a != a || old.b != b;
}
