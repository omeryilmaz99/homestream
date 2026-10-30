import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'connect_screen.dart';

/// Server status: system, disks (eject / mount), connected devices, trash.
class ServerScreen extends StatefulWidget {
  final bool visible;
  final VoidCallback? onOpenFolder;
  const ServerScreen({super.key, this.visible = true, this.onOpenFolder});
  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  SystemInfo? _sys;
  List<DiskInfo> _disks = [];
  List<SessionInfo> _sessions = [];
  ({List<TrashItem> items, int size})? _trash;
  String? _error;
  Timer? _poll;
  StreamSubscription? _sub;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _sub = context.read<AppState>().events.listen((e) {
      if (e.name == 'disks' || e.name == 'sessions' || e.name == 'reconnected') {
        _loadDevices();
      }
    });
    _poll = Timer.periodic(const Duration(seconds: 3), (_) {
      if (widget.visible && mounted) _loadSystem();
    });
    _all();
  }

  @override
  void didUpdateWidget(ServerScreen old) {
    super.didUpdateWidget(old);
    if (widget.visible && !old.visible) _all();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  FilesApi? get _api => context.read<AppState>().api;

  Future<void> _all() async {
    await Future.wait([_loadSystem(), _loadDevices(), _loadTrash()]);
  }

  Future<void> _loadSystem() async {
    try {
      final s = await _api?.system();
      if (mounted && s != null) setState(() => _sys = s);
    } catch (_) {}
  }

  Future<void> _loadDevices() async {
    try {
      final d = await _api?.devices();
      if (mounted && d != null) {
        setState(() {
          _disks = d.disks;
          _sessions = d.sessions;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _loadTrash() async {
    try {
      final t = await _api?.trash();
      if (mounted && t != null) setState(() => _trash = t);
    } catch (_) {}
  }

  Future<void> _run(String key, Future<void> Function() f, String done) async {
    setState(() => _busy.add(key));
    try {
      await f();
      if (mounted) toast(context, done);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(key));
      _loadDevices();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final wide = MediaQuery.sizeOf(context).width >= 860;
    final sections = [
      _systemCard(app),
      SectionTitle('Diskler', trailing: IconButton(onPressed: _loadDevices, icon: const Icon(Icons.refresh_rounded, color: C.teal))),
      if (_error != null) Text(_error!, style: const TextStyle(color: C.danger)),
      for (final d in _disks) Padding(padding: const EdgeInsets.only(bottom: 10), child: _diskCard(d)),
      if (_disks.isEmpty && _error == null) const Text('Disk bilgisi alınıyor…', style: TextStyle(color: C.muted)),
      const SectionTitle('Bağlı cihazlar'),
      SoftCard(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(children: [for (final s in _sessions) _sessionTile(s)]),
      ),
      SectionTitle(
        'Çöp kutusu',
        trailing: _trash != null && _trash!.items.isNotEmpty
            ? TextButton(
                onPressed: () async {
                  if (await confirm(context, title: 'Çöp kutusu boşaltılsın mı?', text: '${_trash!.items.length} öğe (${formatBytes(_trash!.size)}) kalıcı olarak silinecek.', ok: 'Boşalt', danger: true)) {
                    await _api?.deleteTrash(all: true);
                    _loadTrash();
                  }
                },
                child: const Text('Boşalt'),
              )
            : null,
      ),
      _trashCard(),
      const SizedBox(height: 30),
    ];
    return RefreshIndicator(
      onRefresh: _all,
      child: ListView(
        padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 16, vertical: 12),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: GradientText('Sunucu', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700)),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => openServerPicker(context),
                        icon: const Icon(Icons.swap_horiz_rounded),
                        label: const Text('Sunucu değiştir'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...sections,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _systemCard(AppState app) {
    final s = _sys;
    Widget gauge(String label, String value, double v, IconData icon) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Colors.white.withValues(alpha: 0.9)),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12.5)),
            ],
          ),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Bar(value: v, height: 5, color: Colors.white),
        ],
      ),
    );
    final mem = s == null || s.memTotal == 0 ? 0.0 : 1 - s.memAvailable / s.memTotal;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(gradient: C.gradient, borderRadius: BorderRadius.circular(26), boxShadow: C.shadow(1.4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.dns_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(app.server?.name ?? '', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                    Text(
                      s == null ? (app.server?.url ?? '') : '${s.os} · ${s.ips.isEmpty ? app.server?.host : s.ips.join(', ')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(20)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: app.online ? const Color(0xFFA4F5C9) : C.warn, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(app.online ? 'Canlı' : 'Bağlantı yok', style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              gauge('İşlemci', s == null ? '—' : '%${s.cpu.round()}', (s?.cpu ?? 0) / 100, Icons.memory_rounded),
              const SizedBox(width: 16),
              gauge('Bellek', s == null ? '—' : '${formatBytes(s.memTotal - s.memAvailable, digits: 1)} / ${formatBytes(s.memTotal, digits: 0)}', mem, Icons.developer_board_rounded),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 18,
            runSpacing: 6,
            children: [
              _chip(Icons.thermostat_rounded, s == null || s.temperature <= 0 ? '—' : '${s.temperature.round()}°C'),
              _chip(Icons.schedule_rounded, s == null ? '—' : 'Açık: ${formatDuration(Duration(seconds: s.uptime.round()))}'),
              _chip(Icons.south_rounded, s == null ? '—' : formatSpeed(s.rxRate)),
              _chip(Icons.north_rounded, s == null ? '—' : formatSpeed(s.txRate)),
              if (s != null && s.load.isNotEmpty) _chip(Icons.speed_rounded, 'Yük ${s.load.map((e) => e.toStringAsFixed(2)).join(' ')}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData i, String t) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(i, size: 15, color: Colors.white),
      const SizedBox(width: 4),
      Text(t, style: const TextStyle(color: Colors.white, fontSize: 12.5)),
    ],
  );

  Widget _diskCard(DiskInfo d) {
    final icon = d.removable ? Icons.usb_rounded : (d.transport == 'nvme' ? Icons.memory_rounded : Icons.storage_rounded);
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: C.tint, borderRadius: BorderRadius.circular(13)),
                child: Icon(icon, color: C.teal),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.title, style: const TextStyle(fontWeight: FontWeight.w600, color: C.ink)),
                    Text(
                      [
                        formatBytes(d.size, digits: 0),
                        if (d.transport.isNotEmpty) d.transport.toUpperCase(),
                        if (d.removable) 'çıkarılabilir',
                        if (d.system) 'sistem diski',
                      ].join(' · '),
                      style: const TextStyle(fontSize: 12, color: C.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          for (final p in d.partitions)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                p.title,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(p.fs.toUpperCase(), style: const TextStyle(fontSize: 11, color: C.muted)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (p.mountpoint.isNotEmpty && p.total > 0) ...[
                          Bar(value: (p.total - p.free) / p.total, height: 5),
                          const SizedBox(height: 3),
                          Text(
                            '${formatBytes(p.free)} boş / ${formatBytes(p.total)} · ${p.mountpoint}',
                            style: const TextStyle(fontSize: 11.5, color: C.muted),
                          ),
                        ] else
                          Text(
                            p.mountpoint.isEmpty ? 'Bağlı değil · ${formatBytes(p.size)}' : p.mountpoint,
                            style: const TextStyle(fontSize: 11.5, color: C.muted),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (p.canEject)
                    _busy.contains(p.path)
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                        : TextButton.icon(
                            onPressed: () async {
                              if (await confirm(context, title: '"${p.title}" çıkarılsın mı?', text: 'Diske yazma bittiyse güvenle çıkarılır. Tekrar takınca kendiliğinden bağlanır.', ok: 'Çıkar')) {
                                _run(p.path, () => _api!.eject(p.mountpoint), 'Disk çıkarıldı, artık çekebilirsin');
                              }
                            },
                            icon: const Icon(Icons.eject_rounded),
                            label: const Text('Çıkar'),
                          )
                  else if (p.canMount)
                    _busy.contains(p.path)
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                        : TextButton.icon(
                            onPressed: () => _run(p.path, () => _api!.mountDisk(p.path), 'Disk bağlandı'),
                            icon: const Icon(Icons.power_rounded),
                            label: const Text('Bağla'),
                          ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _sessionTile(SessionInfo s) {
    return ListTile(
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: C.tint, borderRadius: BorderRadius.circular(12)),
            child: Icon(s.icon, color: C.teal),
          ),
          if (s.online)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: C.ok, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
              ),
            ),
        ],
      ),
      title: Row(
        children: [
          Flexible(child: Text(s.device, overflow: TextOverflow.ellipsis)),
          if (s.current)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: C.tint, borderRadius: BorderRadius.circular(8)),
              child: const Text('Bu cihaz', style: TextStyle(fontSize: 11, color: C.teal)),
            ),
        ],
      ),
      subtitle: Text(
        '${s.platform.isEmpty ? '' : '${s.platform} · '}${s.lastIp} · ${s.online ? 'şu an bağlı' : 'son görülme ${formatAgo(s.lastSeen)}'}',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: IconButton(
        tooltip: 'Oturumu kapat',
        icon: const Icon(Icons.logout_rounded, color: C.muted),
        onPressed: () async {
          final ok = await confirm(
            context,
            title: '${s.device} oturumu kapatılsın mı?',
            text: s.current ? 'Bu cihazda tekrar şifre girmen gerekecek.' : 'O cihaz bir daha bağlanmak için şifre girmek zorunda kalacak.',
            ok: 'Oturumu kapat',
            danger: true,
          );
          if (!ok || !mounted) return;
          if (s.current) {
            await context.read<AppState>().logout();
          } else {
            _run(s.id, () => _api!.revoke(s.id), 'Oturum kapatıldı');
          }
        },
      ),
    );
  }

  Widget _trashCard() {
    final t = _trash;
    if (t == null) return const SizedBox.shrink();
    if (t.items.isEmpty) {
      return const SoftCard(
        child: Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: C.faint),
            SizedBox(width: 12),
            Text('Çöp kutusu boş', style: TextStyle(color: C.muted)),
          ],
        ),
      );
    }
    return SoftCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          for (final it in t.items.take(50))
            ListTile(
              dense: true,
              leading: Icon(it.isDir ? Icons.folder_rounded : kindIcon(kindOf(it.name)), color: C.teal),
              title: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${formatBytes(it.size)} · ${formatAgo(it.deleted)} · ${it.orig}', maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Geri al',
                    icon: const Icon(Icons.restore_rounded, color: C.teal),
                    onPressed: () async {
                      try {
                        await _api!.restore([it.id]);
                        if (mounted) toast(context, '"${it.name}" geri alındı');
                      } on ApiException catch (e) {
                        if (mounted) toast(context, e.message, error: true);
                      }
                      _loadTrash();
                    },
                  ),
                  IconButton(
                    tooltip: 'Kalıcı sil',
                    icon: const Icon(Icons.delete_forever_rounded, color: C.danger),
                    onPressed: () async {
                      await _api!.deleteTrash(ids: [it.id]);
                      _loadTrash();
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
