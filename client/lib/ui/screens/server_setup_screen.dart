import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/discovery.dart';
import '../../core/prefs.dart';
import '../../state/app_state.dart';
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
                          ..._found.map(
                            (d) => _ServerTile(
                              icon: Icons.dns_rounded,
                              title: d.name,
                              subtitle: d.url,
                              onTap: _testing
                                  ? null
                                  : () => _connectTo(d.name, d.url),
                            ),
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
                            autofocus: _found.isEmpty,
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
  const _ServerTile({
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
  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      onShowHoverHighlight: (v) => setState(() => _hover = v),
      onShowFocusHighlight: (v) => setState(() => _hover = v),
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
            color: _hover ? AppColors.surface3 : AppColors.surface2,
            borderRadius: BorderRadius.circular(12),
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
class AnimatedBackdrop extends StatefulWidget {
  const AnimatedBackdrop({super.key});
  @override
  State<AnimatedBackdrop> createState() => AnimatedBackdropState();
}

/// Soft drifting colour blobs. Each blob is painted once into its own layer
/// (RepaintBoundary) and only moved with a Transform, so the animation costs
/// a layer offset per frame instead of repainting full-screen gradients.
class AnimatedBackdropState extends State<AnimatedBackdrop>
    with SingleTickerProviderStateMixin {
  static const _variant = String.fromEnvironment('HS_TEST_VARIANT');
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 30),
  );

  @override
  void initState() {
    super.initState();
    if (_variant != 'static') _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth, h = box.maxHeight;
          final side = min(w, h);
          Widget blob(Color c, double phase, double rx, double ry, double r) {
            final d = side * r * 2;
            final child = RepaintBoundary(
              child: SizedBox(
                width: d,
                height: d,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        c.withValues(alpha: 0.35),
                        c.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            );
            return AnimatedBuilder(
              animation: _c,
              child: child,
              builder: (context, child) {
                final a = 2 * pi * (_c.value + phase);
                final cx = w * (0.5 + rx * cos(a));
                final cy = h * (0.5 + ry * sin(a * 1.3));
                return Transform.translate(
                  offset: Offset(cx - d / 2, cy - d / 2),
                  child: child,
                );
              },
            );
          }

          return ClipRect(
            child: ColoredBox(
              color: AppColors.bg,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  const SizedBox.expand(),
                  blob(AppColors.accent, 0, 0.32, 0.28, 0.75),
                  blob(AppColors.accent2, 0.33, 0.35, 0.3, 0.6),
                  blob(const Color(0xFF3B82F6), 0.66, 0.3, 0.32, 0.55),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
