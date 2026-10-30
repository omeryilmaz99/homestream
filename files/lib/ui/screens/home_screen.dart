import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/platform.dart';
import '../../core/prefs.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/transfers_panel.dart';
import 'connect_screen.dart';

/// Dashboard: server storage, the big "Dosya Transferi" button, four tiles
/// and the recent transfers.
class HomeScreen extends StatefulWidget {
  final void Function(int tab, {int focus}) go;
  const HomeScreen({super.key, required this.go});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  SystemInfo? _sys;
  int _disks = 0;
  Timer? _timer;
  String? _serverId;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final api = app.api;
    if (api == null) return;
    try {
      final s = await api.system();
      final r = await api.roots();
      if (!mounted) return;
      setState(() {
        _sys = s;
        _disks = r.places.where((p) => p.kind == 'disk').length;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (app.server?.id != _serverId) {
      _serverId = app.server?.id;
      _sys = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
    final prefs = app.prefs;
    final wide = MediaQuery.sizeOf(context).width >= 860;
    final content = <Widget>[
      _header(app),
      const SizedBox(height: 18),
      _storageCard(app),
      Transform.translate(
        offset: const Offset(0, -26),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              boxShadow: C.shadow(),
            ),
            child: SizedBox(
              width: 260,
              child: GradientButton(
                label: 'Dosya Transferi',
                icon: Icons.swap_horiz_rounded,
                height: 48,
                onPressed: () => widget.go(1),
              ),
            ),
          ),
        ),
      ),
      _tiles(prefs),
      SectionTitle(
        'Son aktarımlar',
        trailing: TextButton(
          onPressed: () => showTransfers(context),
          child: const Text('Tümü'),
        ),
      ),
      _recent(app),
      const SizedBox(height: 24),
    ];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 16, vertical: 12),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: content),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(AppState app) {
    return Row(
      children: [
        const _Dots(),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const GradientText('Home Dosya', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700)),
              Text(
                app.online ? 'Tekrar hoş geldin!' : 'Bağlantı bekleniyor…',
                style: const TextStyle(color: C.text, fontSize: 13.5),
              ),
            ],
          ),
        ),
        Tooltip(
          message: 'Sunucu değiştir',
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => openServerPicker(context),
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: C.shadow(),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(gradient: C.gradient, shape: BoxShape.circle),
                    child: const Icon(Icons.dns_rounded, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Text(
                      app.server?.name ?? 'Sunucu',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, color: C.ink),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: app.online ? C.ok : C.warn, shape: BoxShape.circle),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _storageCard(AppState app) {
    final s = _sys;
    final total = s?.homeTotal ?? 0;
    final free = s?.homeFree ?? 0;
    final used = total <= 0 ? 0.0 : (total - free) / total;
    Widget stat(String k, String v) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(k, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
        const SizedBox(height: 2),
        Text(v, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600)),
      ],
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 18, 44),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6F9FDB), Color(0xFF6A98D6), Color(0xFF5FB4D3)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: C.shadow(1.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 24,
                  runSpacing: 8,
                  children: [
                    stat('Toplam', total > 0 ? formatBytes(total, digits: 0) : '—'),
                    stat('Boş', total > 0 ? formatBytes(free, digits: 0) : '—'),
                  ],
                ),
                const SizedBox(height: 16),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => widget.go(2),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      _disks > 0 ? 'Depolama · +$_disks disk' : 'Depolama',
                      style: const TextStyle(color: C.ink, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
          StorageRing(value: used, size: 128),
        ],
      ),
    );
  }

  Widget _tiles(Prefs prefs) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - 14) / 2;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            SizedBox(
              width: w,
              child: _Tile(
                filled: true,
                icon: Icons.send_rounded,
                title: 'Gönder',
                label: 'Toplam gönderilen',
                value: formatBytes(prefs.totalSent),
                onTap: () => widget.go(1, focus: 0),
              ),
            ),
            SizedBox(
              width: w,
              child: _Tile(
                icon: Icons.download_rounded,
                title: 'Al',
                label: 'Toplam alınan',
                value: formatBytes(prefs.totalReceived),
                onTap: () => widget.go(1, focus: 1),
              ),
            ),
            SizedBox(
              width: w,
              child: _Tile(
                icon: Icons.folder_copy_rounded,
                title: 'Dosya Yöneticisi',
                label: 'Aktarılan dosya',
                value: '${prefs.filesSent + prefs.filesReceived}',
                onTap: () => widget.go(1, focus: 1),
              ),
            ),
            SizedBox(
              width: w,
              child: _Tile(
                filled: true,
                icon: Icons.usb_rounded,
                title: 'Cihazlar',
                label: 'Diskler ve bağlantılar',
                value: _sys == null ? '—' : '${_disks + 1} depolama',
                onTap: () => widget.go(2),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _recent(AppState app) {
    final h = app.prefs.history.take(20).toList();
    if (h.isEmpty) {
      return const SoftCard(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(Icons.history_rounded, color: C.faint),
              SizedBox(width: 12),
              Expanded(
                child: Text('Henüz aktarım yok. "Dosya Transferi" ile başla.', style: TextStyle(color: C.muted)),
              ),
            ],
          ),
        ),
      );
    }
    return SizedBox(
      height: 158,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: h.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) => _RecentCard(entry: h[i], app: app),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots();
  @override
  Widget build(BuildContext context) {
    Widget d(Color c) => Container(width: 11, height: 11, decoration: BoxDecoration(color: c, shape: BoxShape.circle));
    return SizedBox(
      width: 30,
      height: 30,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [d(C.teal), d(const Color(0xFF9EE0DB))]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [d(const Color(0xFF9EE0DB)), d(C.teal)]),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final bool filled;
  final IconData icon;
  final String title, label, value;
  final VoidCallback onTap;
  const _Tile({
    this.filled = false,
    required this.icon,
    required this.title,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : C.teal;
    return SoftCard(
      gradient: filled
          ? const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF87C1EC), Color(0xFF3FC0BA)],
            )
          : null,
      border: filled ? null : Border.all(color: const Color(0xFFD5EEEC), width: 1.4),
      radius: 26,
      padding: const EdgeInsets.fromLTRB(14, 22, 14, 20),
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, size: 40, color: filled ? Colors.white : C.teal),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: fg)),
          const SizedBox(height: 6),
          Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: filled ? C.ink : C.text)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 12.5, color: filled ? Colors.white : C.muted)),
        ],
      ),
    );
  }
}

class _RecentCard extends StatelessWidget {
  final HistoryEntry entry;
  final AppState app;
  const _RecentCard({required this.entry, required this.app});

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final k = kindOf(e.name);
    Widget thumb;
    final localExists = e.localPath.isNotEmpty && File(e.localPath).existsSync();
    if (k == FileKind.image && canThumb(e.name) && localExists) {
      thumb = Image(
        image: ResizeImage(FileImage(File(e.localPath)), width: 300, policy: ResizeImagePolicy.fit),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _icon(k),
      );
    } else if (k == FileKind.image && canThumb(e.name) && app.api != null && e.serverId == app.server?.id) {
      thumb = Image.network(app.api!.thumbUrl(e.remotePath, width: 300), fit: BoxFit.cover, errorBuilder: (_, _, _) => _icon(k));
    } else {
      thumb = _icon(k);
    }
    return SizedBox(
      width: 132,
      child: SoftCard(
        padding: EdgeInsets.zero,
        radius: 20,
        onTap: localExists
            ? () async {
                final err = await AppPlatform.openFile(e.localPath);
                if (err != null && context.mounted) toast(context, err, error: true);
              }
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  thumb,
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: e.upload ? C.teal : C.blue, shape: BoxShape.circle),
                      child: Icon(e.upload ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 12, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: C.ink)),
                  Text(
                    '${formatBytes(e.size)} · ${formatAgo(DateTime.fromMillisecondsSinceEpoch(e.at))}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: C.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _icon(FileKind k) => Container(
    color: kindColor(k).withValues(alpha: 0.12),
    child: Icon(kindIcon(k), color: kindColor(k), size: 36),
  );
}
