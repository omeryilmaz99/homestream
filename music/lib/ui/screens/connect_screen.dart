import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/discovery.dart';
import '../../state/app_state.dart';
import '../neu.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// First start / no connection: find or type the server address.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});
  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _url = TextEditingController();
  List<DiscoveredServer> _found = [];
  bool _searching = false;
  bool _connecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _url.text = app.server?.url ?? '';
    _error = app.error;
    _discover();
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _discover() async {
    setState(() => _searching = true);
    final r = await context.read<AppState>().discover();
    if (!mounted) return;
    setState(() {
      _found = r;
      _searching = false;
    });
  }

  Future<void> _connect(String url, {String? name}) async {
    if (_connecting) return;
    setState(() {
      _connecting = true;
      _error = null;
    });
    final err = await context.read<AppState>().addServer(url, name: name);
    if (!mounted) return;
    setState(() {
      _connecting = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final saved = app.prefs.servers;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 30, 24, 30),
          children: [
            const FadeSlideIn(child: Center(child: _Logo())),
            const SizedBox(height: 26),
            const Text('Home Müzik', style: T.h1, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            const Text(
              'Evdeki Home Stream sunucuna bağlan.',
              style: T.dim,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            Row(
              children: [
                const Expanded(child: Text('Ağdaki sunucular', style: T.h3)),
                if (_searching)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    onPressed: _discover,
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Yeniden ara',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_found.isEmpty && !_searching)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Sunucu bulunamadı. Telefonun aynı Wi-Fi ağında olduğundan emin ol ya da adresi aşağıya yaz.',
                  style: T.dim,
                ),
              ),
            for (final s in _found)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: NeuButton(
                  radius: 16,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  onTap: _connecting
                      ? null
                      : () => _connect(s.url, name: s.name),
                  child: Row(
                    children: [
                      const Icon(Icons.dns_rounded, color: C.accent),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.name, style: T.h3),
                            Text(s.url, style: T.faint),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: C.textDim),
                    ],
                  ),
                ),
              ),
            if (saved.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Kayıtlı sunucular', style: T.h3),
              const SizedBox(height: 8),
              for (final s in saved)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.history_rounded),
                  title: Text(s.name.isEmpty ? s.url : s.name, style: T.body),
                  subtitle: Text(s.url, style: T.faint),
                  onTap: _connecting
                      ? null
                      : () => _connect(s.url, name: s.name),
                  trailing: IconButton(
                    tooltip: 'Unut',
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => app.forgetServer(s),
                  ),
                ),
            ],
            const SizedBox(height: 20),
            const Text('Adresle bağlan', style: T.h3),
            const SizedBox(height: 10),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(hintText: '192.168.1.20:8420'),
              onSubmitted: (v) => _connect(v),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: C.danger)),
            ],
            const SizedBox(height: 18),
            Center(
              child: _connecting
                  ? const LoadingView()
                  : AccentPill(
                      'Bağlan',
                      icon: Icons.link_rounded,
                      onTap: () => _connect(_url.text),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();
  @override
  Widget build(BuildContext context) {
    return NeuBox(
      circle: true,
      width: 120,
      height: 120,
      depth: 1.4,
      child: Center(
        child: Container(
          width: 76,
          height: 76,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [C.accentHi, C.accentLo],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Icon(
            Icons.music_note_rounded,
            size: 42,
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}
