import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/discovery.dart';
import '../../core/prefs.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// "Yakındaki Sunucular": radar of servers found on the network, the servers
/// used before, and a manual address field.
class ConnectScreen extends StatefulWidget {
  final bool canClose;
  const ConnectScreen({super.key, this.canClose = false});
  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );
  List<DiscoveredServer> _found = [];
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    _spin.repeat();
    final r = await discoverServers(timeout: const Duration(seconds: 3));
    if (!mounted) return;
    _spin.stop();
    setState(() {
      _found = r;
      _scanning = false;
    });
  }

  Future<void> _open(String url, {String? name, ServerConfig? known}) async {
    final app = context.read<AppState>();
    if (known != null && app.tokenFor(known) != null) {
      if (known.url != url) {
        known.url = url;
      }
      await app.connect(known);
      if (mounted && widget.canClose && app.phase == Phase.ready) {
        Navigator.of(context).pop();
      }
      return;
    }
    final ok = await showLoginSheet(context, url: url, name: name ?? known?.name);
    if (ok && mounted && widget.canClose) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final servers = app.servers;
    final wide = MediaQuery.sizeOf(context).width > 900;
    final radar = _Radar(
      spin: _spin,
      found: _found,
      scanning: _scanning,
      onScan: _scan,
      onTap: (d) {
        final known = servers.where((s) => s.id == d.id).firstOrNull;
        _open(d.url, name: d.name, known: known);
      },
    );
    final list = _ServerList(
      servers: servers,
      found: _found,
      onOpen: (s) {
        final f = _found.where((d) => d.id == s.id).firstOrNull;
        _open(f?.url ?? s.url, known: s);
      },
      onAdd: () async {
        final url = await prompt(
          context,
          title: 'Sunucu adresi',
          hint: '192.168.1.20',
          ok: 'Devam',
        );
        if (url != null && mounted) _open(normalizeServerUrl(url));
      },
    );
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: C.page),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    if (widget.canClose)
                      SoftIconButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        onPressed: () => Navigator.of(context).pop(),
                        tooltip: 'Geri',
                      )
                    else
                      const SizedBox(width: 40),
                    const Expanded(
                      child: Center(
                        child: GradientText(
                          'Yakındaki Sunucular',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    SoftIconButton(
                      icon: Icons.add_link_rounded,
                      tooltip: 'Adresle ekle',
                      onPressed: () => list.onAdd(),
                    ),
                  ],
                ),
              ),
              if (app.error != null && app.phase == Phase.needLogin)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _Notice(text: app.error!),
                ),
              Expanded(
                child: wide
                    ? Row(
                        children: [
                          Expanded(flex: 5, child: radar),
                          Expanded(
                            flex: 4,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(8, 24, 32, 24),
                              child: list,
                            ),
                          ),
                        ],
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        children: [
                          SizedBox(height: 380, child: radar),
                          list,
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;
  const _Notice({required this.text});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: C.warn.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline_rounded, color: C.warn),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _Radar extends StatelessWidget {
  final AnimationController spin;
  final List<DiscoveredServer> found;
  final bool scanning;
  final VoidCallback onScan;
  final void Function(DiscoveredServer) onTap;
  const _Radar({
    required this.spin,
    required this.found,
    required this.scanning,
    required this.onScan,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final s = min(c.maxWidth, c.maxHeight) * 0.92;
        final center = Offset(c.maxWidth / 2, c.maxHeight / 2);
        final pins = <Widget>[];
        for (var i = 0; i < found.length; i++) {
          final d = found[i];
          // spread the servers over the rings
          final ring = 0.62 + 0.3 * ((i % 3) / 2);
          final ang = -pi / 2 + i * 2.4;
          final pos =
              center + Offset(cos(ang), sin(ang)) * (s / 2) * ring * 0.92;
          pins.add(
            Positioned(
              left: pos.dx - 60,
              top: pos.dy - 30,
              width: 120,
              child: _Pin(server: d, onTap: () => onTap(d)),
            ),
          );
        }
        return Stack(
          children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: spin,
                builder: (_, _) => CustomPaint(
                  painter: _RingsPainter(
                    s / 2,
                    scanning ? spin.value : -1,
                  ),
                ),
              ),
            ),
            Positioned(
              left: center.dx - 50,
              top: center.dy - 50,
              child: _Center(scanning: scanning, onTap: onScan),
            ),
            ...pins,
            if (!scanning && found.isEmpty)
              Positioned(
                left: 0,
                right: 0,
                top: center.dy + 64,
                child: const Text(
                  'Ağda sunucu bulunamadı.\nOrtadaki düğmeyle tekrar ara ya da adresle ekle.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: C.muted, height: 1.4),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Center extends StatelessWidget {
  final bool scanning;
  final VoidCallback onTap;
  const _Center({required this.scanning, required this.onTap});
  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Ağı tara',
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: C.gradient,
          boxShadow: [
            BoxShadow(
              color: C.teal.withValues(alpha: 0.35),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Icon(
          scanning ? Icons.radar_rounded : Icons.swap_horiz_rounded,
          color: Colors.white,
          size: 44,
        ),
      ),
    ),
  );
}

class _RingsPainter extends CustomPainter {
  final double radius;
  final double sweep; // 0..1, -1 = no sweep
  _RingsPainter(this.radius, this.sweep);
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (var i = 1; i <= 5; i++) {
      final r = radius * (0.3 + i * 0.14);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3
          ..color = C.teal.withValues(alpha: 0.55 - i * 0.08),
      );
    }
    if (sweep >= 0) {
      final rect = Rect.fromCircle(center: c, radius: radius);
      final a = sweep * 2 * pi;
      canvas.drawArc(
        rect,
        a - 0.9,
        0.9,
        true,
        Paint()
          ..shader = SweepGradient(
            startAngle: a - 0.9,
            endAngle: a,
            colors: [
              C.teal.withValues(alpha: 0),
              C.teal.withValues(alpha: 0.22),
            ],
            transform: const GradientRotation(0),
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) =>
      old.sweep != sweep || old.radius != radius;
}

class _Pin extends StatelessWidget {
  final DiscoveredServer server;
  final VoidCallback onTap;
  const _Pin({required this.server, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: C.shadow(1.6),
          ),
          child: const Icon(Icons.dns_rounded, color: C.teal),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: C.shadow(),
          ),
          child: Text(
            server.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: C.ink,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ServerList extends StatelessWidget {
  final List<ServerConfig> servers;
  final List<DiscoveredServer> found;
  final void Function(ServerConfig) onOpen;
  final VoidCallback onAdd;
  const _ServerList({
    required this.servers,
    required this.found,
    required this.onOpen,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Son bağlananlar'),
        if (servers.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Henüz bir sunucuya bağlanmadın. Yukarıdaki radarda bulunan sunucuya dokun ya da adresini ekle.',
              style: TextStyle(color: C.muted, height: 1.4),
            ),
          ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final s in servers)
              SizedBox(
                width: 168,
                child: _ServerCard(
                  server: s,
                  nearby: found.any((d) => d.id == s.id),
                  remembered: app.remembered(s),
                  active: app.server?.id == s.id && app.phase == Phase.ready,
                  onOpen: () => onOpen(s),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Adresle sunucu ekle'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ],
    );
  }
}

class _ServerCard extends StatelessWidget {
  final ServerConfig server;
  final bool nearby, remembered, active;
  final VoidCallback onOpen;
  const _ServerCard({
    required this.server,
    required this.nearby,
    required this.remembered,
    required this.active,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      border: active ? Border.all(color: C.teal, width: 2) : null,
      onTap: onOpen,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: const BoxDecoration(
                  gradient: C.gradientSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.dns_rounded, color: Colors.white),
              ),
              if (nearby)
                Positioned(
                  right: -2,
                  bottom: 0,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: C.ok,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            server.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, color: C.ink),
          ),
          const SizedBox(height: 2),
          Text(
            server.host,
            maxLines: 1,
            style: const TextStyle(fontSize: 12, color: C.muted),
          ),
          const SizedBox(height: 10),
          GradientButton(
            label: active ? 'Bağlı' : (remembered ? 'Bağlan' : 'Giriş yap'),
            height: 34,
            gradient: C.gradient,
            onPressed: onOpen,
          ),
        ],
      ),
    );
  }
}

/// Password sheet with "Beni hatırla". Returns true when logged in.
Future<bool> showLoginSheet(
  BuildContext context, {
  required String url,
  String? name,
}) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (c) => _LoginSheet(url: url, name: name),
  );
  return r ?? false;
}

class _LoginSheet extends StatefulWidget {
  final String url;
  final String? name;
  const _LoginSheet({required this.url, this.name});
  @override
  State<_LoginSheet> createState() => _LoginSheetState();
}

class _LoginSheetState extends State<_LoginSheet> {
  final _pw = TextEditingController();
  late final _url = TextEditingController(text: widget.url);
  bool _remember = true;
  bool _busy = false;
  bool _show = false;
  String? _err;

  Future<void> _go() async {
    if (_pw.text.trim().isEmpty) {
      setState(() => _err = 'Şifreyi yaz');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await context.read<AppState>().login(
        _url.text,
        _pw.text,
        remember: _remember,
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.name ?? 'Sunucuya giriş',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: C.ink,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Home Stream ayar şifresiyle giriş yap.',
                style: TextStyle(color: C.muted),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _url,
                decoration: const InputDecoration(
                  labelText: 'Adres',
                  prefixIcon: Icon(Icons.dns_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pw,
                autofocus: true,
                obscureText: !_show,
                onSubmitted: (_) => _go(),
                decoration: InputDecoration(
                  labelText: 'Şifre',
                  prefixIcon: const Icon(Icons.lock_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _show
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                    ),
                    onPressed: () => setState(() => _show = !_show),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              CheckboxListTile(
                value: _remember,
                onChanged: (v) => setState(() => _remember = v ?? true),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Beni hatırla'),
                subtitle: const Text(
                  'Bu cihazda bir daha şifre sorulmaz. İstediğin zaman sunucunun "Bağlı cihazlar" listesinden kapatabilirsin.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              if (_err != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    _err!,
                    style: const TextStyle(color: C.danger),
                  ),
                ),
              GradientButton(
                label: 'Bağlan',
                icon: Icons.login_rounded,
                busy: _busy,
                onPressed: _go,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown while a remembered server cannot be reached.
class UnreachableScreen extends StatelessWidget {
  const UnreachableScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.server;
    final pending = app.transfers.activeCount;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: C.page),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    EmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: '${s?.name ?? 'Sunucu'} şu an ulaşılamıyor',
                      text:
                          '${app.error ?? ''}\n${s?.url ?? ''}\n\nSunucu açılınca ya da ağa dönünce kendiliğinden bağlanacak.'
                          '${pending > 0 ? '\n$pending aktarım bekliyor, kaldığı yerden devam edecek.' : ''}',
                    ),
                    const SizedBox(height: 8),
                    GradientButton(
                      label: 'Tekrar dene',
                      icon: Icons.refresh_rounded,
                      busy: app.phase == Phase.connecting,
                      onPressed: app.retryNow,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => app.disconnect(),
                      icon: const Icon(Icons.dns_rounded),
                      label: const Text('Başka sunucu seç'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small helper used by other screens.
Future<void> openServerPicker(BuildContext context) => Navigator.of(context)
    .push(MaterialPageRoute(builder: (_) => const ConnectScreen(canClose: true)));
