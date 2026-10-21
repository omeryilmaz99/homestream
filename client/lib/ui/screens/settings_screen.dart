import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/image_cache.dart';
import '../../core/models.dart';
import '../../core/platform.dart';
import '../../core/prefs.dart';
import '../../state/app_state.dart';
import '../layout.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'play_launcher.dart';

const appVersion = '1.2.0';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final AppState _state = context.read<AppState>();
  Prefs get prefs => _state.prefs;

  ServerSettings? _server;
  ScanStatus? _scan;
  String? _serverError;
  Timer? _scanTimer;
  int _cacheBytes = 0;
  List<ExternalPlayerConfig> _players = [];

  @override
  void initState() {
    super.initState();
    _loadServer();
    _players = detectExternalPlayers();
    if (AppPlatform.isAndroid) {
      findExternalPlayers().then((l) {
        if (mounted) setState(() => _players = l);
      });
    }
    DiskCache.sizeBytes().then((v) {
      if (mounted) setState(() => _cacheBytes = v);
    });
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadServer() async {
    try {
      final s = await _state.api!.settings();
      final st = await _state.api!.scanStatus();
      if (!mounted) return;
      setState(() {
        _server = s;
        _scan = st;
        _serverError = null;
      });
      if (st.running) _pollScan();
    } catch (e) {
      if (mounted) setState(() => _serverError = e.toString());
    }
  }

  void _pollScan() {
    _scanTimer?.cancel();
    _scanTimer = Timer.periodic(const Duration(seconds: 2), (t) async {
      try {
        final st = await _state.api!.scanStatus();
        if (!mounted) return;
        setState(() => _scan = st);
        if (!st.running) {
          t.cancel();
          _state.bumpData();
          _loadServer();
        }
      } catch (_) {}
    });
  }

  Future<void> _startScan({bool refresh = false}) async {
    try {
      await _state.api!.scan(refreshMetadata: refresh);
      if (refresh) DiskCache.evictMemory();
      _pollScan();
      if (mounted) showToast(context, 'Tarama başladı');
    } catch (e) {
      if (mounted) showToast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        pagePad(context),
        pageTop(context),
        pagePad(context),
        pageBottom(context),
      ),
      children: [
        const Text(
          'Ayarlar',
          style: TextStyle(
            fontSize: 38,
            fontWeight: FontWeight.w900,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _appearanceSection(),
                _playbackSection(),
                _subtitleSection(),
                _serversSection(),
                if (AppPlatform.canManageServer)
                  _serverAdminSection()
                else
                  const _Section(
                    icon: Icons.admin_panel_settings_rounded,
                    title: 'Sunucu Yönetimi',
                    subtitle:
                        'Klasörler, tarama ve sunucu ayarları bilgisayardaki Home Stream uygulamasından yapılır.',
                    children: [],
                  ),
                _otherSection(),
                _shortcutsSection(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------- appearance
  Widget _appearanceSection() {
    return _Section(
      icon: Icons.palette_rounded,
      title: 'Görünüm',
      subtitle: 'Uygulamanın tema rengi (bu cihaz).',
      children: [
        const SizedBox(height: 14),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final p in AppTheme.presets)
              _ThemeSwatch(
                preset: p,
                selected: p.id == AppTheme.current.id,
                onTap: () {
                  prefs.theme = p.id;
                  AppTheme.apply(p);
                },
              ),
          ],
        ),
      ],
    );
  }

  // ------------------------------------------------------------ playback
  Widget _playbackSection() {
    final ext = prefs.externalPlayer;
    return _Section(
      icon: Icons.play_circle_rounded,
      title: 'Oynatma',
      children: [
        _Row(
          title: 'Videolar nasıl açılsın?',
          subtitle:
              'Her seferinde sorabilir veya hep aynı oynatıcıyı kullanabilir.',
          trailing: _Select<PlayerMode>(
            value: prefs.playerMode,
            items: const {
              PlayerMode.ask: 'Her seferinde sor',
              PlayerMode.internal: 'Home Stream oynatıcısı',
              PlayerMode.external: 'Harici oynatıcı',
            },
            onChanged: (v) => setState(() => prefs.playerMode = v!),
          ),
        ),
        _Row(
          title: 'Harici oynatıcı',
          subtitle: ext == null
              ? 'Seçilmedi'
              : (AppPlatform.isAndroid ? ext.name : ext.path),
          trailing: _Select<String>(
            value: ext?.path ?? '',
            items: {
              '': 'Seç…',
              for (final p in _players) p.path: p.name,
              if (ext != null && !_players.any((p) => p.path == ext.path))
                ext.path: ext.name,
              if (!AppPlatform.isAndroid) '__pick': 'Başka bir program…',
            },
            onChanged: (v) async {
              if (v == '__pick') {
                final res = await FilePicker.pickFile(
                  dialogTitle: 'Video oynatıcı programını seç',
                  type: FileType.custom,
                  allowedExtensions: ['exe'],
                );
                final path = res?.path;
                if (path == null) return;
                final name = path
                    .split(RegExp(r'[\\/]'))
                    .last
                    .replaceAll(RegExp(r'\.exe$', caseSensitive: false), '');
                setState(
                  () => prefs.externalPlayer = ExternalPlayerConfig(name, path),
                );
              } else if (v != null && v.isNotEmpty) {
                final p = [..._players, ?ext].firstWhere((e) => e.path == v);
                setState(() => prefs.externalPlayer = p);
              }
            },
          ),
        ),
        _SwitchRow(
          title: 'Donanım hızlandırmalı çözme',
          subtitle:
              'Ekran kartını kullanır, 4K/HEVC için önerilir. Görüntü bozulursa kapat.',
          value: prefs.hardwareDecoding,
          onChanged: (v) => setState(() => prefs.hardwareDecoding = v),
        ),
        if (AppPlatform.isDesktop)
          _SwitchRow(
            title: 'Tam ekranda başlat',
            value: prefs.playerFullscreen,
            onChanged: (v) => setState(() => prefs.playerFullscreen = v),
          ),
        _SwitchRow(
          title: 'Sonraki bölümü otomatik oynat',
          subtitle: 'Bölüm bitince geri sayımla sıradakine geçer.',
          value: prefs.autoPlayNext,
          onChanged: (v) => setState(() => prefs.autoPlayNext = v),
        ),
        _Row(
          title: 'Geri sayım süresi',
          trailing: _Select<int>(
            value: prefs.nextCountdown,
            items: const {
              5: '5 sn',
              10: '10 sn',
              15: '15 sn',
              20: '20 sn',
              30: '30 sn',
            },
            onChanged: (v) => setState(() => prefs.nextCountdown = v!),
          ),
        ),
        _Row(
          title: 'İleri / geri sarma adımı',
          trailing: _Select<int>(
            value: prefs.seekStep,
            items: const {5: '5 sn', 10: '10 sn', 15: '15 sn', 30: '30 sn'},
            onChanged: (v) => setState(() => prefs.seekStep = v!),
          ),
        ),
      ],
    );
  }

  Widget _subtitleSection() {
    return _Section(
      icon: Icons.subtitles_rounded,
      title: 'Altyazı ve Ses',
      children: [
        _Row(
          title: 'Tercih edilen altyazı',
          subtitle:
              'Ses zaten bu dildeyse altyazı gösterilmez (sadece zorunlu altyazılar).',
          trailing: _Select<String>(
            value: prefs.subtitleLanguage,
            items: const {'tur': 'Türkçe', 'eng': 'İngilizce', 'off': 'Kapalı'},
            onChanged: (v) => setState(() => prefs.subtitleLanguage = v!),
          ),
        ),
        _Row(
          title: 'Tercih edilen ses dili',
          trailing: _Select<String>(
            value: prefs.audioLanguage,
            items: const {
              'original': 'Orijinal',
              'tur': 'Türkçe',
              'eng': 'İngilizce',
            },
            onChanged: (v) => setState(() => prefs.audioLanguage = v!),
          ),
        ),
        _Row(
          title: 'Altyazı boyutu',
          subtitle: '%${prefs.subtitleScale}',
          trailing: SizedBox(
            width: 240,
            child: Slider(
              value: prefs.subtitleScale.toDouble().clamp(50, 200),
              min: 50,
              max: 200,
              divisions: 15,
              label: '%${prefs.subtitleScale}',
              onChanged: (v) => setState(() => prefs.subtitleScale = v.round()),
            ),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ servers
  Widget _serversSection() {
    final servers = _state.servers;
    return _Section(
      icon: Icons.dns_rounded,
      title: 'Sunucular (bu cihaz)',
      subtitle: 'Her cihaz farklı bir sunucuya bağlanabilir.',
      children: [
        for (final s in servers)
          _Row(
            leading: Icon(
              s.id == _state.server?.id
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: s.id == _state.server?.id
                  ? AppColors.accent
                  : AppColors.textMuted,
            ),
            title: s.name.isNotEmpty ? s.name : s.url,
            subtitle: s.url,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (s.id != _state.server?.id)
                  TextButton(
                    onPressed: () =>
                        _state.connect(s, forceProfilePicker: true),
                    child: const Text('Bağlan'),
                  ),
                IconButton(
                  tooltip: 'Düzenle',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _editServer(s),
                ),
                IconButton(
                  tooltip: 'Kaldır',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => _removeServer(s),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: PillButton(
              icon: Icons.add_rounded,
              label: 'Sunucu ekle',
              height: 40,
              onPressed: _state.showServerSetup,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _editServer(ServerConfig s) async {
    final name = TextEditingController(text: s.name);
    final url = TextEditingController(text: s.url);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sunucuyu düzenle'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(hintText: 'İsim'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: url,
                decoration: const InputDecoration(hintText: 'Adres'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final urlChanged = url.text.trim() != s.url;
      _state.updateServer(s, name: name.text.trim(), url: url.text.trim());
      if (urlChanged && s.id == _state.server?.id) {
        await _state.connect(s);
      }
      if (mounted) setState(() {});
    }
  }

  Future<void> _removeServer(ServerConfig s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sunucu kaldırılsın mı?'),
        content: const Text('Sunucu sadece bu cihazın listesinden kaldırılır.'),
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
    if (ok == true) await _state.removeServer(s);
    if (mounted) setState(() {});
  }

  // ------------------------------------------------------------ server admin
  Widget _serverAdminSection() {
    final s = _server;
    if (_serverError != null && s == null) {
      return _Section(
        icon: Icons.storage_rounded,
        title: 'Sunucu Yönetimi',
        children: [
          Text(_serverError!, style: const TextStyle(color: AppColors.danger)),
        ],
      );
    }
    if (s == null) {
      return const _Section(
        icon: Icons.storage_rounded,
        title: 'Sunucu Yönetimi',
        children: [LinearProgressIndicator(minHeight: 2)],
      );
    }
    final scan = _scan;
    return _Section(
      icon: Icons.storage_rounded,
      title: 'Sunucu Yönetimi',
      subtitle: 'Bu ayarlar sunucuda saklanır ve tüm cihazları etkiler.',
      children: [
        _Row(
          title: 'Sunucu adı',
          subtitle: s.serverName,
          trailing: IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final v = await _prompt('Sunucu adı', s.serverName);
              if (v == null || v.isEmpty) return;
              await _state.api!.updateSettings({'serverName': v});
              _loadServer();
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 14, 4, 6),
          child: Text(
            'Kütüphane klasörleri',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
        for (final f in s.libraryFolders)
          _Row(
            leading: Icon(
              f.available ? Icons.folder_rounded : Icons.folder_off_rounded,
              color: f.available ? const Color(0xFFFBBF24) : AppColors.danger,
            ),
            title: f.name.isNotEmpty ? f.name : f.path,
            subtitle:
                '${f.path} · ${f.available ? '${f.itemCount} video' : 'Şu an erişilemiyor (disk takılı mı?)'}',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _FolderKindMenu(
                  kind: f.kind,
                  onChanged: (k) => _setFolderKind(f, k),
                ),
                const SizedBox(width: 4),
                if (s.libraryFolders.first.id == f.id)
                  const Tooltip(
                    message: 'Ana klasör kaldırılamaz',
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        Icons.lock_outline_rounded,
                        color: AppColors.textMuted,
                      ),
                    ),
                  )
                else
                  IconButton(
                    tooltip: 'Klasörü kütüphaneden çıkar',
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                    onPressed: () => _removeFolder(f),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 8),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final k in folderKinds)
                PillButton(
                  icon: k.icon,
                  label: k.addLabel,
                  height: 40,
                  onPressed: () => _addFolder(k.id),
                ),
            ],
          ),
        ),
        const Divider(color: AppColors.border, height: 28),
        _Row(
          title: 'Kütüphane taraması',
          subtitle: scan == null
              ? ''
              : scan.running
              ? '${scan.phase}${scan.total > 0 ? ' (${scan.done}/${scan.total})' : ''}'
              : (scan.lastScanAt > 0
                    ? 'Son tarama: ${_ago(scan.lastScanAt)}${scan.lastError.isNotEmpty ? ' · ${scan.lastError}' : ''}'
                    : 'Henüz taranmadı'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (scan?.running == true)
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              TextButton(
                onPressed: scan?.running == true ? null : () => _startScan(),
                child: const Text('Şimdi tara'),
              ),
              PopupMenuButton<String>(
                tooltip: 'Diğer',
                onSelected: (v) {
                  if (v == 'refresh') _startScan(refresh: true);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'refresh',
                    child: Text('Kapakları ve bilgileri yenile'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (scan?.running == true && scan!.total > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ProgressLine(scan.done / scan.total, height: 4),
          ),
        _Row(
          title: 'Otomatik tarama sıklığı',
          trailing: _Select<int>(
            value: s.scanIntervalMinutes,
            items: {
              10: '10 dk',
              30: '30 dk',
              60: '1 saat',
              360: '6 saat',
              1440: 'Günde bir',
              if (![10, 30, 60, 360, 1440].contains(s.scanIntervalMinutes))
                s.scanIntervalMinutes: '${s.scanIntervalMinutes} dk',
            },
            onChanged: (v) async {
              await _state.api!.updateSettings({'scanIntervalMinutes': v});
              _loadServer();
            },
          ),
        ),
        _Row(
          title: 'TMDB anahtarı (kapak, özet ve puanlar için)',
          subtitle: s.tmdbEnabled
              ? 'Etkin · ${s.tmdbApiKey}'
              : 'İsteğe bağlı. Yoksa kapaklar videodan otomatik oluşturulur. themoviedb.org\'dan ücretsiz alınır.',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (s.tmdbEnabled)
                IconButton(
                  tooltip: 'Kaldır',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () async {
                    await _state.api!.updateSettings({'tmdbApiKey': ''});
                    _loadServer();
                  },
                ),
              TextButton(
                onPressed: () async {
                  final v = await _prompt(
                    'TMDB API anahtarı (v3) veya okuma erişim jetonu',
                    '',
                  );
                  if (v == null || v.isEmpty) return;
                  try {
                    await _state.api!.updateSettings({'tmdbApiKey': v});
                    await _state.api!.scan(refreshMetadata: true);
                    _pollScan();
                    if (mounted)
                      showToast(context, 'Kaydedildi, bilgiler indiriliyor');
                  } catch (e) {
                    if (mounted) showToast(context, e.toString(), error: true);
                  }
                  _loadServer();
                },
                child: Text(s.tmdbEnabled ? 'Değiştir' : 'Ekle'),
              ),
            ],
          ),
        ),
        _Row(
          title: 'Bilgi dili',
          trailing: _Select<String>(
            value: s.metadataLanguage.isEmpty ? 'tr-TR' : s.metadataLanguage,
            items: {
              'tr-TR': 'Türkçe',
              'en-US': 'English',
              if (!['tr-TR', 'en-US', ''].contains(s.metadataLanguage))
                s.metadataLanguage: s.metadataLanguage,
            },
            onChanged: (v) async {
              await _state.api!.updateSettings({'metadataLanguage': v});
              _loadServer();
            },
          ),
        ),
      ],
    );
  }

  String _ago(int ts) {
    final d = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(ts * 1000),
    );
    if (d.inMinutes < 1) return 'az önce';
    if (d.inHours < 1) return '${d.inMinutes} dk önce';
    if (d.inDays < 1) return '${d.inHours} saat önce';
    return '${d.inDays} gün önce';
  }

  Future<String?> _prompt(String title, String initial) async {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 460,
          child: TextField(
            controller: c,
            autofocus: true,
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  Future<void> _addFolder(String kind) async {
    final picked = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _ServerFolderPicker(kind: kind),
    );
    if (picked == null) return;
    try {
      await _state.api!.addFolder(picked.$1, picked.$2, kind: kind);
      if (mounted) showToast(context, 'Klasör eklendi, taranıyor');
      _loadServer();
      _pollScan();
    } catch (e) {
      if (mounted) showToast(context, e.toString(), error: true);
    }
  }

  Future<void> _setFolderKind(LibraryFolder f, String kind) async {
    if (kind == f.kind) return;
    try {
      await _state.api!.setFolderKind(f.id, kind);
      if (mounted) {
        showToast(
          context,
          '"${f.name}" artık ${folderKindOf(kind).label.toLowerCase()}, yeniden taranıyor',
        );
      }
      _loadServer();
      _pollScan();
    } catch (e) {
      if (mounted) showToast(context, e.toString(), error: true);
    }
  }

  Future<void> _removeFolder(LibraryFolder f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Klasör kütüphaneden çıkarılsın mı?'),
        content: Text(
          '${f.path}\n\nDosyalar silinmez, sadece uygulamada görünmez olur.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Çıkar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _state.api!.removeFolder(f.id);
      _state.bumpData();
      _loadServer();
    } catch (e) {
      if (mounted) showToast(context, e.toString(), error: true);
    }
  }

  // ------------------------------------------------------------ other
  Widget _otherSection() {
    return _Section(
      icon: Icons.tune_rounded,
      title: 'Diğer',
      children: [
        _SwitchRow(
          title: 'Açılışta profil sor',
          subtitle: 'Kapalıysa son kullanılan profille açılır.',
          value: prefs.askProfileOnStart,
          onChanged: (v) => setState(() => prefs.askProfileOnStart = v),
        ),
        _Row(
          title: 'Kapak önbelleği',
          subtitle: formatSize(_cacheBytes).isEmpty
              ? 'Boş'
              : formatSize(_cacheBytes),
          trailing: TextButton(
            onPressed: () async {
              await DiskCache.clear();
              setState(() => _cacheBytes = 0);
              _state.bumpData();
            },
            child: const Text('Temizle'),
          ),
        ),
        _Row(
          title: 'Home Stream',
          subtitle:
              'Uygulama $appVersion · Sunucu ${_state.serverInfo?.version ?? '-'} · ${_state.serverInfo?.movieCount ?? 0} film, ${_state.serverInfo?.seriesCount ?? 0} dizi',
        ),
      ],
    );
  }

  Widget _shortcutsSection() {
    const remote = [
      ('OK', 'Oynat / duraklat'),
      ('◀ / ▶', 'Geri / ileri sar (basılı tut: hızlı)'),
      ('▲ / ▼', 'Düğmeleri göster'),
      ('Geri', 'Düğmeleri gizle / oynatıcıdan çık'),
    ];
    const touch = [
      ('Dokun', 'Düğmeleri göster / gizle'),
      ('Çift dokun', 'Sol yarı geri, sağ yarı ileri sarar'),
      ('Çubuğu kaydır', 'İstediğin yere atla'),
    ];
    const keys = [
      ('Boşluk / K', 'Oynat / duraklat'),
      ('← / →', 'Geri / ileri sar (Shift ile 1 dk)'),
      ('↑ / ↓', 'Ses'),
      ('F / çift tık', 'Tam ekran'),
      ('M', 'Sessiz'),
      ('S / A', 'Altyazı / ses değiştir'),
      ('Z / X', 'Altyazı gecikmesi'),
      ('[ / ]', 'Oynatma hızı'),
      ('N', 'Sonraki bölüm'),
      ('0-9', 'Videonun %0-90\'ına atla'),
      ('Esc', 'Oynatıcıdan çık'),
      ('Ctrl+F', 'Ara'),
    ];
    return _Section(
      icon: AppPlatform.isTv
          ? Icons.settings_remote_rounded
          : AppPlatform.isPhone
          ? Icons.touch_app_rounded
          : Icons.keyboard_rounded,
      title: AppPlatform.isTv
          ? 'Kumanda'
          : AppPlatform.isPhone
          ? 'Oynatıcıda dokunma'
          : 'Klavye kısayolları',
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            for (final (k, v)
                in AppPlatform.isTv
                    ? remote
                    : AppPlatform.isPhone
                    ? touch
                    : keys)
              SizedBox(
                width: isCompact(context) ? double.infinity : 400,
                child: Row(
                  children: [
                    Container(
                      width: 110,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface3,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        k,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        v,
                        style: const TextStyle(color: AppColors.textDim),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ building blocks

class _ThemeSwatch extends StatefulWidget {
  final ThemePreset preset;
  final bool selected;
  final VoidCallback onTap;
  const _ThemeSwatch({
    required this.preset,
    required this.selected,
    required this.onTap,
  });
  @override
  State<_ThemeSwatch> createState() => _ThemeSwatchState();
}

class _ThemeSwatchState extends State<_ThemeSwatch> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final p = widget.preset;
    final active = _hover || widget.selected;
    return FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      onShowHoverHighlight: (v) => setState(() => _hover = v),
      onShowFocusHighlight: (v) => setState(() => _hover = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => widget.onTap(),
        ),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 150,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: active ? AppColors.surface3 : AppColors.surface2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.selected ? p.accent : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: LinearGradient(
                    colors: [p.accent, p.accent2],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                alignment: Alignment.center,
                child: widget.selected
                    ? const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 28,
                      )
                    : null,
              ),
              const SizedBox(height: 8),
              Text(
                p.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  color: active ? Colors.white : AppColors.textDim,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final List<Widget> children;
  const _Section({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.children,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.accent),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 34),
              child: Text(
                subtitle!,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                ),
              ),
            ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const _Row({this.leading, required this.title, this.subtitle, this.trailing});
  @override
  Widget build(BuildContext context) {
    // phones: wide controls (menus, buttons) go under the text
    final stack = isCompact(context) && trailing != null && trailing is! Switch;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null && !stack) ...[
            const SizedBox(width: 12),
            trailing!,
          ],
        ],
      ),
    );
    if (!stack) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row,
        Padding(
          padding: EdgeInsets.fromLTRB(leading != null ? 40 : 4, 0, 4, 8),
          child: trailing!,
        ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow({
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => _Row(
    title: title,
    subtitle: subtitle,
    trailing: Switch(value: value, onChanged: onChanged),
  );
}

class _Select<T> extends StatelessWidget {
  final T value;
  final Map<T, String> items;
  final ValueChanged<T?> onChanged;
  const _Select({
    required this.value,
    required this.items,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      child: Builder(builder: _build),
    );
  }

  Widget _build(BuildContext context) {
    final focused = Focus.of(context).hasFocus;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: focused ? Colors.white : AppColors.border,
          width: focused ? 2 : 1,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: items.containsKey(value) ? value : null,
          dropdownColor: AppColors.surface2,
          borderRadius: BorderRadius.circular(10),
          style: const TextStyle(color: AppColors.text, fontSize: 14),
          items: items.entries
              .map(
                (e) => DropdownMenuItem<T>(value: e.key, child: Text(e.value)),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// Lets the user pick a folder on the server (e.g. an external disk under /media).
/// Library folder kinds (server: auto / movies / series).
class FolderKind {
  final String id;
  final String label;
  final String addLabel;
  final String hint;
  final IconData icon;
  const FolderKind(this.id, this.label, this.addLabel, this.hint, this.icon);
}

const folderKinds = [
  FolderKind(
    'movies',
    'Film klasörü',
    'Film klasörü ekle',
    'İçindeki her video film olarak eklenir.',
    Icons.movie_rounded,
  ),
  FolderKind(
    'series',
    'Dizi klasörü',
    'Dizi klasörü ekle',
    'Her alt klasör bir dizi sayılır, içindeki videolar bölüm olarak eklenir.',
    Icons.live_tv_rounded,
  ),
  FolderKind(
    'auto',
    'Genel klasör',
    'Genel klasör ekle',
    'Film mi dizi mi olduğu dosya ve klasör adlarından anlaşılır.',
    Icons.folder_rounded,
  ),
];

FolderKind folderKindOf(String id) =>
    folderKinds.firstWhere((k) => k.id == id, orElse: () => folderKinds.last);

class _FolderKindMenu extends StatelessWidget {
  final String kind;
  final ValueChanged<String> onChanged;
  const _FolderKindMenu({required this.kind, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cur = folderKindOf(kind);
    return PopupMenuButton<String>(
      tooltip: 'Klasör türünü değiştir',
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final k in folderKinds)
          PopupMenuItem(
            value: k.id,
            child: ListTile(
              dense: true,
              leading: Icon(
                k.icon,
                color: k.id == kind ? AppColors.accent : null,
              ),
              title: Text(k.label),
              subtitle: Text(k.hint, style: const TextStyle(fontSize: 12)),
              trailing: k.id == kind
                  ? Icon(Icons.check_rounded, color: AppColors.accent)
                  : null,
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surface3,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(cur.icon, size: 16, color: AppColors.textDim),
            const SizedBox(width: 6),
            Text(
              cur.label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const Icon(Icons.expand_more_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}

class _ServerFolderPicker extends StatefulWidget {
  final String kind;
  const _ServerFolderPicker({this.kind = 'auto'});
  @override
  State<_ServerFolderPicker> createState() => _ServerFolderPickerState();
}

class _ServerFolderPickerState extends State<_ServerFolderPicker> {
  FsListing? _listing;
  String? _error;
  final _name = TextEditingController();

  @override
  void initState() {
    super.initState();
    _open('/media');
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _open(String path) async {
    try {
      final l = await context.read<AppState>().api!.fs(path);
      if (mounted) {
        setState(() {
          _listing = l;
          _error = null;
        });
      }
    } catch (e) {
      if (path != '/') {
        return _open('/');
      }
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = _listing;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 620,
        height: 620,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${folderKindOf(widget.kind).label} seç',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${folderKindOf(widget.kind).hint} Harici diskler /media/homestream altında görünür.',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.folder_open_rounded,
                      size: 18,
                      color: AppColors.textDim,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l?.path ?? '…',
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _error != null
                    ? Center(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: AppColors.danger),
                        ),
                      )
                    : l == null
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        children: [
                          if (l.parent != null)
                            ListTile(
                              leading: const Icon(Icons.arrow_upward_rounded),
                              title: const Text('Üst klasör'),
                              onTap: () => _open(l.parent!),
                            ),
                          for (final d in l.dirs)
                            ListTile(
                              leading: const Icon(
                                Icons.folder_rounded,
                                color: Color(0xFFFBBF24),
                              ),
                              title: Text(d.name),
                              onTap: () => _open(d.path),
                            ),
                          if (l.dirs.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text(
                                'Alt klasör yok',
                                style: TextStyle(color: AppColors.textMuted),
                              ),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  hintText: 'Görünen ad (isteğe bağlı), ör. Harici Disk',
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Vazgeç'),
                  ),
                  const SizedBox(width: 8),
                  PillButton(
                    primary: true,
                    height: 42,
                    label: 'Bu klasörü ekle',
                    onPressed: l == null || l.path == '/'
                        ? null
                        : () => Navigator.pop(context, (
                            l.path,
                            _name.text.trim(),
                          )),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
