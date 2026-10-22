import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../state/app_state.dart';
import '../neu.dart';
import '../theme.dart';
import '../track_menu.dart';
import '../widgets/collection.dart';
import '../widgets/common.dart';

/// Asks for the settings password (checked by the server) once per run.
Future<bool> ensureAdmin(BuildContext context) async {
  final app = context.read<AppState>();
  if (app.adminPassword != null) return true;
  final pw = await showDialog<String>(
    context: context,
    useRootNavigator: true,
    barrierColor: Colors.black87,
    builder: (_) => const _PasswordDialog(),
  );
  if (pw == null) return false;
  app.adminPassword = pw;
  return true;
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();
  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _c = TextEditingController();
  bool _busy = false;
  bool _show = false;
  String? _error;

  Future<void> _submit() async {
    final pw = _c.text.trim();
    if (pw.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = context.read<AppState>().api;
    try {
      await api!.checkAdmin(pw);
      if (mounted) Navigator.pop(context, pw);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.status == 403 || e.status == 401
            ? 'Şifre yanlış'
            : e.message;
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.lock_outline_rounded, color: C.accent, size: 32),
      title: const Text('Sunucu ayarları'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Bu ayarlar sunucudaki herkesi etkiler. Devam etmek için şifreyi gir.',
            style: T.dim,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _c,
            autofocus: true,
            obscureText: !_show,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: 'Şifre',
              errorText: _error,
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
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Aç'),
        ),
      ],
    );
  }
}

/// Server-wide settings (password): music folders, scanning, covers.
class ServerSettingsScreen extends StatefulWidget {
  const ServerSettingsScreen({super.key});
  @override
  State<ServerSettingsScreen> createState() => _ServerSettingsScreenState();
}

class _ServerSettingsScreenState extends State<ServerSettingsScreen> {
  MusicSettings? _s;
  ScanStatus? _scan;
  String? _error;
  Timer? _poll;
  bool _wasRunning = false;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _status());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  AppState get _app => context.read<AppState>();
  String get _pw => _app.adminPassword ?? '';

  Future<void> _load() async {
    try {
      final s = await _app.api!.settings();
      if (mounted) setState(() => _s = s);
      await _status();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _status() async {
    final api = _app.api;
    if (api == null || !_app.online) return;
    try {
      final st = await api.scanStatus();
      if (!mounted) return;
      final finished = _wasRunning && !st.running;
      _wasRunning = st.running;
      setState(() => _scan = st);
      if (finished) {
        _app.libraryVersion.value++;
        final s = await api.settings();
        if (mounted) setState(() => _s = s);
      }
    } on ApiException catch (_) {}
  }

  /// Runs an admin call; a wrong password asks again.
  Future<R?> _admin<R>(Future<R> Function(ApiClient a, String pw) f) async {
    try {
      return await f(_app.api!, _pw);
    } on ApiException catch (e) {
      if (e.status == 403 || e.status == 401) {
        _app.adminPassword = null;
        if (!mounted) return null;
        if (await ensureAdmin(context)) return _admin(f);
        return null;
      }
      if (mounted) {
        showToast(context, e.offline ? 'Sunucuya bağlanılamıyor' : e.message);
      }
      return null;
    }
  }

  Future<void> _set(Map<String, dynamic> patch) async {
    final s = await _admin((a, pw) => a.updateSettings(patch, pw));
    if (s != null && mounted) setState(() => _s = s);
  }

  Future<void> _addFolder() async {
    final path = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: const _FolderPicker(),
      ),
    );
    if (path == null || !mounted) return;
    final base =
        path.split(RegExp(r'[\\/]')).where((e) => e.isNotEmpty).lastOrNull ??
        path;
    final name = await askText(
      context,
      title: 'Klasör adı',
      initial: base,
      hint: 'Klasörler sekmesinde görünecek ad',
      ok: 'Ekle',
    );
    if (name == null) return;
    final ok = await _admin(
      (a, pw) => a.addFolder(path, name, pw).then((_) => true),
    );
    if (ok == true) {
      if (mounted) showToast(context, 'Klasör eklendi, taranıyor…');
      await _load();
    }
  }

  Future<void> _removeFolder(MusicFolder f) async {
    final ok = await confirm(
      context,
      title: '"${f.name}" kaldırılsın mı?',
      message:
          'Dosyalar silinmez; yalnızca bu klasördeki şarkılar müzik kütüphanesinden çıkar. '
          'Beğeniler ve listeler, klasör geri eklenirse yeniden görünür.',
      ok: 'Kaldır',
    );
    if (!ok) return;
    final r = await _admin(
      (a, pw) => a.removeFolder(f.id, pw).then((_) => true),
    );
    if (r == true) {
      _app.libraryVersion.value++;
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      body: SubPage(
        title: 'Sunucu ayarları',
        actions: [
          IconButton(
            tooltip: 'Kilitle',
            icon: const Icon(Icons.lock_rounded),
            onPressed: () {
              _app.adminPassword = null;
              Navigator.maybePop(context);
            },
          ),
        ],
        child: s == null
            ? (_error != null
                  ? EmptyState(
                      icon: Icons.error_outline_rounded,
                      title: 'Yüklenemedi',
                      message: _error,
                      action: AccentPill('TEKRAR DENE', onTap: _load),
                    )
                  : const LoadingView())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 6, 18, 150),
                  children: [
                    _scanCard(),
                    const _Header('Müzik klasörleri'),
                    NeuBox(
                      radius: 20,
                      depth: 0.8,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Column(
                        children: [
                          for (final f in s.folders)
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              leading: Icon(
                                f.available
                                    ? Icons.folder_rounded
                                    : Icons.folder_off_rounded,
                                color: f.available ? C.accent : C.danger,
                              ),
                              title: Text(
                                f.name + (f.isDefault ? ' (varsayılan)' : ''),
                                style: T.body,
                              ),
                              subtitle: Text(
                                '${f.path}\n${f.available ? '${f.trackCount} şarkı' : 'Ulaşılamıyor (disk takılı mı?)'}',
                                style: T.faint,
                              ),
                              isThreeLine: true,
                              trailing: f.isDefault
                                  ? null
                                  : IconButton(
                                      tooltip: 'Kaldır',
                                      icon: const Icon(
                                        Icons.remove_circle_outline_rounded,
                                        color: C.danger,
                                      ),
                                      onPressed: () => _removeFolder(f),
                                    ),
                            ),
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                            ),
                            leading: const Icon(
                              Icons.create_new_folder_rounded,
                              color: C.accent,
                            ),
                            title: const Text('Klasör ekle', style: T.body),
                            subtitle: const Text(
                              'Yalnızca müzik dosyaları alınır',
                              style: T.faint,
                            ),
                            onTap: _addFolder,
                          ),
                        ],
                      ),
                    ),
                    const _Header('Kütüphane'),
                    NeuBox(
                      radius: 20,
                      depth: 0.8,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      child: Column(
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Kapakları internetten bul',
                              style: T.body,
                            ),
                            subtitle: const Text(
                              'Dosyada kapak yoksa albüm kapağı internetten indirilir; bulunamazsa hazır kapak kullanılır',
                              style: T.faint,
                            ),
                            value: s.onlineCovers,
                            onChanged: (v) => _set({'onlineCovers': v}),
                          ),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Otomatik tarama', style: T.body),
                            subtitle: const Text(
                              'Yeni eklenen şarkıları bulma sıklığı',
                              style: T.faint,
                            ),
                            trailing: DropdownButton<int>(
                              value:
                                  const [
                                    0,
                                    15,
                                    30,
                                    60,
                                    180,
                                    720,
                                    1440,
                                  ].contains(s.scanIntervalMinutes)
                                  ? s.scanIntervalMinutes
                                  : 60,
                              underline: const SizedBox.shrink(),
                              dropdownColor: C.raisedTop,
                              items: const [
                                DropdownMenuItem(
                                  value: 0,
                                  child: Text('Kapalı'),
                                ),
                                DropdownMenuItem(
                                  value: 15,
                                  child: Text('15 dk'),
                                ),
                                DropdownMenuItem(
                                  value: 30,
                                  child: Text('30 dk'),
                                ),
                                DropdownMenuItem(
                                  value: 60,
                                  child: Text('1 saat'),
                                ),
                                DropdownMenuItem(
                                  value: 180,
                                  child: Text('3 saat'),
                                ),
                                DropdownMenuItem(
                                  value: 720,
                                  child: Text('12 saat'),
                                ),
                                DropdownMenuItem(
                                  value: 1440,
                                  child: Text('Günde bir'),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) _set({'scanIntervalMinutes': v});
                              },
                            ),
                          ),
                          if (!s.ffmpeg)
                            const ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                Icons.warning_amber_rounded,
                                color: Color(0xFFFFC66D),
                              ),
                              title: Text('FFmpeg bulunamadı', style: T.body),
                              subtitle: Text(
                                'Etiketler, gömülü kapaklar ve MP4 sesleri için sunucuya ffmpeg kurulmalı.',
                                style: T.faint,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _scanCard() {
    final st = _scan;
    final running = st?.running ?? false;
    final covers = st != null && st.coverTask.isNotEmpty;
    String line;
    if (running) {
      line = st!.total > 0 ? '${st.phase} • ${st.done}/${st.total}' : st.phase;
    } else if (st != null && st.lastScanAt > 0) {
      final at = DateTime.fromMillisecondsSinceEpoch(st.lastScanAt * 1000);
      line =
          'Son tarama: ${at.day.toString().padLeft(2, '0')}.${at.month.toString().padLeft(2, '0')} '
          '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    } else {
      line = 'Henüz taranmadı';
    }
    return NeuBox(
      radius: 20,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                running
                    ? Icons.sync_rounded
                    : Icons.check_circle_outline_rounded,
                color: C.accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(running ? 'Taranıyor' : 'Kütüphane', style: T.h3),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(line, style: T.dim),
          if (st != null && st.lastError.isNotEmpty)
            Text(st.lastError, style: T.faint.copyWith(color: C.danger)),
          if (running) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: st!.total > 0 ? st.done / st.total : null,
              minHeight: 4,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
          if (covers) ...[
            const SizedBox(height: 10),
            Text(
              '${st.coverTask} • ${st.coverDone}/${st.coverTotal}',
              style: T.faint,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: running
                      ? null
                      : () async {
                          final ok = await _admin(
                            (a, _) => a.scan().then((_) => true),
                          );
                          if (ok == true) {
                            _wasRunning = true;
                            _status();
                          }
                        },
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Şimdi tara'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: running
                      ? null
                      : () async {
                          final ok = await confirm(
                            context,
                            title: 'Kapaklar yenilensin mi?',
                            message:
                                'Bulunamayan kapaklar yeniden aranır. Bu biraz sürebilir.',
                            ok: 'Yenile',
                            danger: false,
                          );
                          if (!ok) return;
                          final r = await _admin(
                            (a, _) =>
                                a.scan(refreshCovers: true).then((_) => true),
                          );
                          if (r == true) {
                            _wasRunning = true;
                            _status();
                          }
                        },
                  icon: const Icon(Icons.image_search_rounded, size: 18),
                  label: const Text('Kapakları yenile'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 26, 6, 10),
    child: Text(
      text.toUpperCase(),
      style: T.faint.copyWith(letterSpacing: 1.6, fontWeight: FontWeight.w800),
    ),
  );
}

/// Browses the server's disks to pick a music folder.
class _FolderPicker extends StatefulWidget {
  const _FolderPicker();
  @override
  State<_FolderPicker> createState() => _FolderPickerState();
}

class _FolderPickerState extends State<_FolderPicker> {
  FsListing? _l;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _open('');
  }

  Future<void> _open(String path) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final l = await context.read<AppState>().api!.fs(path);
      if (mounted) setState(() => _l = l);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = _l;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              if (l?.parent != null)
                IconButton(
                  icon: const Icon(Icons.arrow_upward_rounded),
                  tooltip: 'Üst klasör',
                  onPressed: () => _open(l!.parent!),
                ),
              Expanded(
                child: Text(
                  (l?.path.isEmpty ?? true) ? 'Sürücüler' : l!.path,
                  style: T.h3,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error!, style: const TextStyle(color: C.danger)),
          ),
        Expanded(
          child: ListView(
            children: [
              for (final d in l?.dirs ?? const <(String, String)>[])
                ListTile(
                  leading: const Icon(Icons.folder_rounded),
                  title: Text(d.$1, style: T.body),
                  onTap: () => _open(d.$2),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: l == null || l.path.isEmpty
                    ? null
                    : () => Navigator.pop(context, l.path),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Bu klasörü seç'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
