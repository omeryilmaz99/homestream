import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/local_fs.dart';
import '../../core/models.dart';
import '../../core/platform.dart';
import '../../core/transfers.dart';
import '../../state/app_state.dart';
import '../../state/pane.dart';
import '../item_actions.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/file_pane.dart';
import '../widgets/transfers_panel.dart';

/// Holds both panes for the whole app run (they keep their folders when you
/// switch tabs).
class Workspace extends ChangeNotifier {
  final AppState app;
  late final PaneController local = PaneController(remote: false, app: app);
  late final PaneController remote = PaneController(remote: true, app: app);
  String? _serverId;
  StreamSubscription? _sub;
  bool storageOk = true;
  final Map<String, ServerJob> jobs = {};

  /// Server clipboard (copy / cut).
  List<String> clip = [];
  bool clipCut = false;

  /// Which pane the phone layout focuses on (-1 both).
  int focus = -1;
  void setFocus(int f) {
    focus = f;
    notifyListeners();
  }

  Workspace(this.app) {
    app.addListener(_onApp);
    _sub = app.events.listen(_onEvent);
    app.transfers.onFinished = _onFinished;
    _checkStorage();
    _onApp();
  }

  Future<void> _checkStorage() async {
    storageOk = await AppPlatform.hasStorageAccess();
    if (storageOk) {
      await local.init();
    }
    notifyListeners();
  }

  Future<void> askStorage() async {
    await AppPlatform.requestStorageAccess();
    await _checkStorage();
  }

  void _onApp() {
    final id = app.phase == Phase.ready ? app.server?.id : null;
    if (id != _serverId) {
      _serverId = id;
      clip = [];
      jobs.clear();
      if (id != null) {
        remote.path = null;
        remote.init();
      }
      notifyListeners();
    }
  }

  void _onEvent(dynamic e) {
    switch (e.name) {
      case 'change':
        final dir = e.data is Map ? '${e.data['dir']}' : '';
        if (dir == remote.path) remote.refresh(quiet: true);
      case 'reconnected':
        remote.refresh(quiet: true);
        remote.loadPlaces();
      case 'disks':
        remote.loadPlaces();
        // the folder may be on a disk that was removed
        if (remote.path != null) remote.refresh(quiet: true);
      case 'job':
        if (e.data is Map<String, dynamic>) {
          final j = ServerJob.fromJson(e.data as Map<String, dynamic>);
          jobs[j.id] = j;
          if (!j.running) {
            Timer(const Duration(seconds: 6), () {
              jobs.remove(j.id);
              notifyListeners();
            });
          }
          notifyListeners();
        }
    }
  }

  void _onFinished(TransferTask t) {
    if (t.kind == TransferKind.download) {
      final dir = File(t.localPath).parent.path;
      if (dir == local.path) _debounce(local);
    } else {
      final i = t.remotePath.lastIndexOf('/');
      final dir = i <= 0 ? '/' : t.remotePath.substring(0, i);
      if (dir == remote.path) _debounce(remote);
    }
  }

  final Map<PaneController, Timer> _timers = {};
  void _debounce(PaneController c) {
    _timers[c]?.cancel();
    _timers[c] = Timer(const Duration(milliseconds: 600), () => c.refresh(quiet: true));
  }

  @override
  void dispose() {
    app.removeListener(_onApp);
    _sub?.cancel();
    local.dispose();
    remote.dispose();
    super.dispose();
  }
}

class TransferScreen extends StatefulWidget {
  const TransferScreen({super.key});
  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> implements PaneHost {
  Workspace get ws => context.read<Workspace>();
  AppState get app => context.read<AppState>();
  double? _ratio;

  // ---- PaneHost ----

  @override
  Future<void> send(PaneController from, List<FileItem> items, {String? intoDir}) async {
    if (items.isEmpty) return;
    final tm = app.transfers;
    try {
      if (!from.remote) {
        final dir = intoDir ?? ws.remote.path;
        if (dir == null) throw ApiException('Önce sunucuda bir klasör aç');
        if (intoDir == null && !ws.remote.writable) {
          throw ApiException('Bu sunucu klasörüne yazma izni yok. Başka bir klasör seç.');
        }
        final n = await tm.upload(items.map((e) => e.path).toList(), dir);
        _queued(n, true, dir);
      } else {
        final dir = intoDir ?? ws.local.path;
        if (dir == null) throw ApiException('Önce bu cihazda bir klasör aç');
        final n = await tm.download(
          items.map((e) => (path: e.path, isDir: e.isDir, size: e.size, mtime: e.mtime.millisecondsSinceEpoch)).toList(),
          dir,
        );
        _queued(n, false, dir);
      }
      from.clearSelection();
    } catch (e) {
      if (mounted) toast(context, e is ApiException ? e.message : (e is FileSystemException ? LocalFs.errorText(e) : '$e'), error: true);
    }
  }

  void _queued(int n, bool up, String dir) {
    if (!mounted) return;
    if (n == 0) {
      toast(context, 'Aktarılacak dosya yok (klasör boş olabilir)', error: true);
      return;
    }
    final name = dir.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).lastOrNull ?? dir;
    toast(context, '$n dosya ${up ? 'sunucuya' : 'bu cihaza'} aktarılıyor → $name');
  }

  @override
  Future<void> osDrop(PaneController to, List<String> paths, {String? intoDir}) async {
    if (!to.remote) {
      toast(context, 'Sunucuya göndermek için dosyaları sağdaki sunucu paneline bırak.', error: true);
      return;
    }
    final dir = intoDir ?? to.path;
    if (dir == null) return;
    try {
      final n = await app.transfers.upload(paths, dir);
      _queued(n, true, dir);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  @override
  void openFile(PaneController c, FileItem e) async {
    if (!c.remote) {
      final err = await AppPlatform.openFile(e.path);
      if (err != null && mounted) toast(context, err, error: true);
      return;
    }
    final previewable = (e.kind == FileKind.image && canThumb(e.name)) || (isTextFile(e.name) && e.size < 20 * 1024 * 1024);
    if (previewable) {
      await showPreview(context, c, e);
      return;
    }
    final ok = await confirm(
      context,
      title: '"${e.name}" indirilsin mi?',
      text: 'Bu dosya bu cihazda "${ws.local.path ?? ''}" klasörüne indirilecek (${formatBytes(e.size)}).',
      ok: 'İndir',
    );
    if (ok) await send(c, [e]);
  }

  @override
  bool canPaste(PaneController c) => c.remote && ws.clip.isNotEmpty;

  @override
  void clip(PaneController c, List<FileItem> items, {required bool cut}) {
    ws.clip = items.map((e) => e.path).toList();
    ws.clipCut = cut;
    toast(context, '${items.length} öğe ${cut ? 'taşınmak' : 'kopyalanmak'} üzere seçildi. Hedef klasörde "Yapıştır" de.');
    setState(() {});
  }

  @override
  Future<void> paste(PaneController c, {String? intoDir}) async {
    final dest = intoDir ?? c.path;
    if (dest == null || ws.clip.isEmpty) return;
    try {
      final j = await app.api!.copy(ws.clip, dest, move: ws.clipCut);
      ws.jobs[j.id] = j;
      if (ws.clipCut) ws.clip = [];
      if (mounted) {
        toast(context, '${j.names.length} öğe ${j.kind == 'move' ? 'taşınıyor' : 'kopyalanıyor'}…');
        setState(() {});
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  // ---- layout ----

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<Workspace>();
    final app = context.watch<AppState>();
    final w = MediaQuery.sizeOf(context).width;
    final wide = w >= 860;
    final serverName = app.server?.name ?? 'Sunucu';
    final localPane = ws.storageOk
        ? FilePane(
            c: ws.local,
            host: this,
            compact: !wide,
            title: AppPlatform.isAndroid ? 'Bu telefon' : 'Bu bilgisayar',
            subtitle: app.deviceName,
            icon: AppPlatform.isAndroid ? Icons.smartphone_rounded : Icons.computer_rounded,
          )
        : _StorageAsk(onAsk: ws.askStorage);
    final remotePane = FilePane(
      c: ws.remote,
      host: this,
      compact: !wide,
      title: serverName,
      subtitle: app.server?.host ?? '',
      icon: Icons.dns_rounded,
    );
    final jobs = ws.jobs.values.toList();
    final bottom = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final j in jobs) Padding(padding: const EdgeInsets.only(top: 8), child: _JobCard(job: j)),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: TransferDock(onOpen: () => showTransfers(context)),
        ),
      ],
    );
    if (wide) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: localPane),
                  _MiddleBar(ws: ws, host: this),
                  Expanded(child: remotePane),
                ],
              ),
            ),
            bottom,
          ],
        ),
      );
    }
    // phone: top / bottom split with a handle in the middle
    return LayoutBuilder(
      builder: (context, cons) {
        final ratio = _ratio ?? app.prefs.splitRatio;
        final focus = ws.focus;
        final h = cons.maxHeight - 52;
        final topH = focus == 0 ? h - 64 : (focus == 1 ? 64.0 : h * ratio);
        return Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          child: Column(
            children: [
              SizedBox(height: topH.clamp(64, h - 64), child: localPane),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: (d) {
                  setState(() {
                    ws.focus = -1;
                    _ratio = ((topH + d.delta.dy) / h).clamp(0.15, 0.85);
                  });
                },
                onVerticalDragEnd: (_) {
                  if (_ratio != null) app.prefs.splitRatio = _ratio!;
                },
                onDoubleTap: () => setState(() {
                  ws.focus = -1;
                  _ratio = 0.5;
                  app.prefs.splitRatio = 0.5;
                }),
                child: _Splitter(ws: ws, host: this),
              ),
              Expanded(child: remotePane),
              bottom,
            ],
          ),
        );
      },
    );
  }
}

class _MiddleBar extends StatelessWidget {
  final Workspace ws;
  final _TransferScreenState host;
  const _MiddleBar({required this.ws, required this.host});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([ws.local, ws.remote]),
      builder: (context, _) {
        final up = ws.local.selected.isNotEmpty;
        final down = ws.remote.selected.isNotEmpty;
        return SizedBox(
          width: 76,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _RoundAction(
                icon: Icons.arrow_forward_rounded,
                tip: 'Seçilenleri sunucuya gönder',
                enabled: up,
                onTap: () => host.send(ws.local, ws.local.selection),
              ),
              const SizedBox(height: 14),
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  gradient: C.gradient,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: C.teal.withValues(alpha: 0.3), blurRadius: 18, offset: const Offset(0, 6))],
                ),
                child: const Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 14),
              _RoundAction(
                icon: Icons.arrow_back_rounded,
                tip: 'Seçilenleri bu cihaza indir',
                enabled: down,
                onTap: () => host.send(ws.remote, ws.remote.selection),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RoundAction extends StatelessWidget {
  final IconData icon;
  final String tip;
  final bool enabled;
  final VoidCallback onTap;
  const _RoundAction({required this.icon, required this.tip, required this.enabled, required this.onTap});
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tip,
    child: Material(
      color: enabled ? Colors.white : Colors.white.withValues(alpha: 0.6),
      shape: const CircleBorder(),
      elevation: enabled ? 3 : 0,
      shadowColor: C.teal.withValues(alpha: 0.3),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: 46,
          height: 46,
          child: Icon(icon, color: enabled ? C.teal : C.faint),
        ),
      ),
    ),
  );
}

class _Splitter extends StatelessWidget {
  final Workspace ws;
  final _TransferScreenState host;
  const _Splitter({required this.ws, required this.host});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([ws.local, ws.remote]),
      builder: (context, _) {
        final up = ws.local.selected.isNotEmpty;
        final down = ws.remote.selected.isNotEmpty;
        return SizedBox(
          height: 52,
          child: Row(
            children: [
              IconButton(
                tooltip: 'Telefonu büyüt',
                onPressed: () => ws.setFocus(ws.focus == 0 ? -1 : 0),
                icon: Icon(ws.focus == 0 ? Icons.unfold_less_rounded : Icons.expand_more_rounded, color: C.muted),
              ),
              Expanded(
                child: Center(
                  child: up || down
                      ? FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: C.teal,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: () => up
                              ? host.send(ws.local, ws.local.selection)
                              : host.send(ws.remote, ws.remote.selection),
                          icon: Icon(up ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded),
                          label: Text(up ? 'Sunucuya gönder' : 'Telefona indir'),
                        )
                      : Container(
                          width: 64,
                          height: 6,
                          decoration: BoxDecoration(color: C.faint.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(3)),
                        ),
                ),
              ),
              IconButton(
                tooltip: 'Sunucuyu büyüt',
                onPressed: () => ws.setFocus(ws.focus == 1 ? -1 : 1),
                icon: Icon(ws.focus == 1 ? Icons.unfold_less_rounded : Icons.expand_less_rounded, color: C.muted),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _JobCard extends StatelessWidget {
  final ServerJob job;
  const _JobCard({required this.job});
  @override
  Widget build(BuildContext context) {
    final j = job;
    final what = j.names.length == 1 ? j.names.first : '${j.names.length} öğe';
    final verb = j.kind == 'move' ? 'taşınıyor' : 'kopyalanıyor';
    final text = switch (j.state) {
      'running' => '$what $verb · ${formatBytes(j.done)} / ${formatBytes(j.total)}',
      'done' => '$what ${j.kind == 'move' ? 'taşındı' : 'kopyalandı'}',
      'canceled' => '$what: iptal edildi',
      _ => '$what: ${j.error.isEmpty ? 'başarısız' : j.error}',
    };
    return SoftCard(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
      child: Row(
        children: [
          Icon(
            j.running ? Icons.dns_rounded : (j.state == 'done' ? Icons.check_circle_rounded : Icons.error_outline_rounded),
            color: j.state == 'failed' ? C.danger : C.teal,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sunucuda: $text', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                if (j.running) ...[const SizedBox(height: 5), Bar(value: j.progress, height: 4)],
              ],
            ),
          ),
          if (j.running)
            IconButton(
              tooltip: 'İptal',
              onPressed: () => context.read<AppState>().api?.cancelJob(j.id),
              icon: const Icon(Icons.close_rounded, color: C.muted),
            ),
        ],
      ),
    );
  }
}

class _StorageAsk extends StatelessWidget {
  final VoidCallback onAsk;
  const _StorageAsk({required this.onAsk});
  @override
  Widget build(BuildContext context) => SoftCard(
    child: EmptyState(
      icon: Icons.folder_shared_rounded,
      title: 'Telefondaki dosyalara erişim izni gerekli',
      text: 'Dosya gönderip alabilmek için "Tüm dosyalara erişim" iznini ver. İzin sadece bu uygulama içindir.',
      action: GradientButton(label: 'İzin ver', icon: Icons.lock_open_rounded, onPressed: onAsk),
    ),
  );
}
