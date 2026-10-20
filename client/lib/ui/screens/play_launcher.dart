import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/platform.dart';
import '../../core/prefs.dart';
import '../../player/player_screen.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Android players are stored with an `android:<package>` path; an empty
/// package means "let Android ask".
const androidPrefix = 'android:';
const androidChooser = ExternalPlayerConfig('Uygulama seç', androidPrefix);

bool externalPlayerAvailable(ExternalPlayerConfig p) =>
    p.path.startsWith(androidPrefix)
    ? AppPlatform.isAndroid
    : !AppPlatform.isAndroid && File(p.path).existsSync();

/// Installed external players (all platforms).
Future<List<ExternalPlayerConfig>> findExternalPlayers() async {
  if (!AppPlatform.isAndroid) return detectExternalPlayers();
  final apps = await AppPlatform.videoPlayers();
  return [
    for (final (label, pkg) in apps)
      ExternalPlayerConfig(label, '$androidPrefix$pkg'),
    androidChooser,
  ];
}

/// Known external players on Windows (detected if installed).
List<ExternalPlayerConfig> detectExternalPlayers() {
  if (AppPlatform.isAndroid) return [];
  if (!Platform.isWindows) {
    final res = <ExternalPlayerConfig>[];
    for (final p in ['/usr/bin/vlc', '/usr/bin/mpv', '/snap/bin/vlc']) {
      if (File(p).existsSync()) {
        res.add(ExternalPlayerConfig(p.contains('mpv') ? 'mpv' : 'VLC', p));
      }
    }
    return res;
  }
  final env = Platform.environment;
  final roots = <String>{
    env['ProgramFiles'] ?? r'C:\Program Files',
    env['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)',
    env['ProgramW6432'] ?? r'C:\Program Files',
  };
  final local = env['LOCALAPPDATA'];
  final candidates = <String, List<String>>{
    'VLC': [r'VideoLAN\VLC\vlc.exe'],
    'PotPlayer': [
      r'DAUM\PotPlayer\PotPlayerMini64.exe',
      r'DAUM\PotPlayer\PotPlayerMini.exe',
      r'PotPlayer\PotPlayerMini64.exe',
    ],
    'MPC-HC': [
      r'MPC-HC\mpc-hc64.exe',
      r'MPC-HC\mpc-hc.exe',
      r'K-Lite Codec Pack\MPC-HC64\mpc-hc64.exe',
    ],
    'MPC-BE': [r'MPC-BE x64\mpc-be64.exe', r'MPC-BE\mpc-be.exe'],
    'mpv': [r'mpv\mpv.exe'],
    'KMPlayer': [r'KMPlayer 64X\KMPlayer64.exe', r'KMPlayer\KMPlayer.exe'],
  };
  final found = <ExternalPlayerConfig>[];
  candidates.forEach((name, rels) {
    for (final root in [
      ...roots,
      ?local,
      if (local != null) '$local\\Programs',
    ]) {
      bool done = false;
      for (final rel in rels) {
        final p = '$root\\$rel';
        if (File(p).existsSync()) {
          found.add(ExternalPlayerConfig(name, p));
          done = true;
          break;
        }
      }
      if (done) break;
    }
  });
  return found;
}

/// Launches an external player with the stream URL, start time and subtitles.
Future<void> launchExternal(
  ExternalPlayerConfig player,
  ApiClient api,
  MediaItem item,
  double startAt,
) async {
  final url = api.streamUrl(item);
  final subs =
      item.file?.externalSubtitles.map((s) => api.url(s.url)).toList() ?? [];
  if (player.path.startsWith(androidPrefix)) {
    final pkg = player.path.substring(androidPrefix.length);
    final ok = await AppPlatform.openExternal(
      url,
      item.displayTitle,
      package: pkg.isEmpty ? null : pkg,
      startMs: (startAt * 1000).floor(),
      subtitles: subs,
    );
    if (!ok) throw 'uygulama bulunamadı';
    return;
  }
  final exe = player.path.toLowerCase();
  final args = <String>[];
  final title = item.displayTitle;
  if (exe.contains('vlc')) {
    args.addAll([url, '--meta-title=$title']);
    if (startAt > 1) args.add('--start-time=${startAt.floor()}');
    if (subs.isNotEmpty) args.add('--sub-file=${subs.first}');
  } else if (exe.contains('potplayer')) {
    args.add(url);
    if (startAt > 1) args.add('/seek=${formatDuration(startAt)}');
    if (subs.isNotEmpty) args.add('/sub=${subs.first}');
    args.add('/title=$title');
  } else if (exe.contains('mpc-hc') || exe.contains('mpc-be')) {
    args.add(url);
    if (startAt > 1) args.addAll(['/start', '${(startAt * 1000).floor()}']);
    for (final s in subs) {
      args.addAll(['/sub', s]);
    }
  } else if (exe.contains('mpv')) {
    args.addAll([url, '--force-media-title=$title']);
    if (startAt > 1) args.add('--start=${startAt.floor()}');
    for (final s in subs) {
      args.add('--sub-file=$s');
    }
  } else {
    args.add(url);
  }
  await Process.start(player.path, args, mode: ProcessStartMode.detached);
}

/// Entry point used everywhere a title is played.
Future<void> playItem(
  BuildContext context,
  MediaItem item, {
  double? startAt,
}) async {
  final state = context.read<AppState>();
  final api = state.api;
  if (api == null) return;
  var it = item;
  try {
    if (it.isSeries) {
      final detail = await api.item(it.id);
      final next =
          detail.nextUp ??
          (detail.seasons.isNotEmpty && detail.seasons.first.episodes.isNotEmpty
              ? detail.seasons.first.episodes.first
              : null);
      if (next == null) {
        if (context.mounted)
          showToast(context, 'Bu dizide oynatılacak bölüm yok.', error: true);
        return;
      }
      it = next;
    }
    if (it.file == null) it = await api.item(it.id);
  } catch (e) {
    if (context.mounted) showToast(context, e.toString(), error: true);
    return;
  }
  final start = startAt ?? (it.inProgress ? it.userData.position : 0.0);
  if (!context.mounted) return;

  final prefs = state.prefs;
  var mode = prefs.playerMode;
  ExternalPlayerConfig? ext = prefs.externalPlayer;
  if (mode == PlayerMode.external &&
      ext != null &&
      !externalPlayerAvailable(ext)) {
    mode = PlayerMode.ask;
  }
  if (mode == PlayerMode.ask || (mode == PlayerMode.external && ext == null)) {
    final choice = await showDialog<_PlayChoice>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => _PlayChoiceDialog(item: it, initialExternal: ext),
    );
    if (choice == null) return;
    if (choice.remember) {
      prefs.playerMode = choice.external
          ? PlayerMode.external
          : PlayerMode.internal;
    }
    if (choice.player != null) prefs.externalPlayer = choice.player;
    mode = choice.external ? PlayerMode.external : PlayerMode.internal;
    ext = choice.player;
  }
  if (!context.mounted) return;

  if (mode == PlayerMode.external && ext != null) {
    try {
      await launchExternal(ext, api, it, start);
      if (context.mounted) {
        showToast(
          context,
          '${ext.name} ile açılıyor. İzleme ilerlemesi harici oynatıcıda kaydedilmez.',
        );
      }
    } catch (e) {
      if (context.mounted)
        showToast(context, 'Harici oynatıcı açılamadı: $e', error: true);
    }
    return;
  }

  await Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 350),
      reverseTransitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, _, _) => PlayerScreen(item: it, startAt: start),
      transitionsBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
    ),
  );
  state.bumpData();
}

/// Plays using the saved resume position (used by hero "Oynat" buttons).
Future<void> quickPlay(BuildContext context, MediaItem item) =>
    playItem(context, item);

class _PlayChoice {
  final bool external;
  final bool remember;
  final ExternalPlayerConfig? player;
  _PlayChoice(this.external, this.remember, this.player);
}

class _PlayChoiceDialog extends StatefulWidget {
  final MediaItem item;
  final ExternalPlayerConfig? initialExternal;
  const _PlayChoiceDialog({required this.item, this.initialExternal});

  @override
  State<_PlayChoiceDialog> createState() => _PlayChoiceDialogState();
}

class _PlayChoiceDialogState extends State<_PlayChoiceDialog> {
  bool _remember = false;
  List<ExternalPlayerConfig> _players = [];
  ExternalPlayerConfig? _selected;

  @override
  void initState() {
    super.initState();
    _setPlayers(detectExternalPlayers());
    if (AppPlatform.isAndroid) {
      findExternalPlayers().then((l) {
        if (mounted) setState(() => _setPlayers(l));
      });
    }
  }

  void _setPlayers(List<ExternalPlayerConfig> list) {
    _players = list;
    final init = widget.initialExternal;
    if (init != null &&
        !_players.any((p) => p.path == init.path) &&
        externalPlayerAvailable(init)) {
      _players.insert(0, init);
    }
    _selected = init != null
        ? _players.where((p) => p.path == init.path).firstOrNull
        : _players.firstOrNull;
    _selected ??= _players.firstOrNull;
  }

  Future<void> _pickExe() async {
    if (AppPlatform.isAndroid) return;
    final res = await FilePicker.pickFile(
      dialogTitle: 'Video oynatıcı programını seç',
      type: FileType.custom,
      allowedExtensions: Platform.isWindows ? ['exe'] : null,
    );
    final path = res?.path;
    if (path == null) return;
    final name = path
        .split(RegExp(r'[\\/]'))
        .last
        .replaceAll(RegExp(r'\.exe$', caseSensitive: false), '');
    final cfg = ExternalPlayerConfig(name, path);
    setState(() {
      _players.removeWhere((p) => p.path == path);
      _players.insert(0, cfg);
      _selected = cfg;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Nasıl açılsın?',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                widget.item.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textDim),
              ),
              const SizedBox(height: 20),
              _ChoiceTile(
                autofocus: true,
                icon: Icons.play_circle_fill_rounded,
                title: 'Home Stream oynatıcısı',
                subtitle:
                    'Önerilen. Kaldığın yer, altyazılar ve sonraki bölüm otomatik.',
                onTap: () =>
                    Navigator.pop(context, _PlayChoice(false, _remember, null)),
              ),
              const SizedBox(height: 12),
              _ChoiceTile(
                icon: Icons.open_in_new_rounded,
                title: _selected == null
                    ? 'Başka bir uygulama'
                    : '${_selected!.name} ile aç',
                subtitle: _players.isEmpty
                    ? 'Bilgisayarında bir oynatıcı bulunamadı. Aşağıdan programı seçebilirsin.'
                    : 'Harici oynatıcıda izleme ilerlemesi kaydedilmez.',
                onTap: _selected == null
                    ? _pickExe
                    : () => Navigator.pop(
                        context,
                        _PlayChoice(true, _remember, _selected),
                      ),
                trailing: PopupMenuButton<Object>(
                  tooltip: 'Oynatıcı seç',
                  icon: const Icon(Icons.expand_more_rounded),
                  onSelected: (v) {
                    if (v is ExternalPlayerConfig) {
                      setState(() => _selected = v);
                    } else {
                      _pickExe();
                    }
                  },
                  itemBuilder: (_) => [
                    ..._players.map(
                      (p) => PopupMenuItem(value: p, child: Text(p.name)),
                    ),
                    if (!AppPlatform.isAndroid)
                      const PopupMenuItem(
                        value: 'pick',
                        child: Text('Başka bir program seç…'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => _remember = !_remember),
                child: Row(
                  children: [
                    Checkbox(
                      value: _remember,
                      onChanged: (v) => setState(() => _remember = v ?? false),
                    ),
                    const Expanded(
                      child: Text(
                        'Seçimimi hatırla (Ayarlar\'dan değiştirebilirsin)',
                        style: TextStyle(color: AppColors.textDim),
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
}

class _ChoiceTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool autofocus;
  const _ChoiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    this.autofocus = false,
  });
  @override
  State<_ChoiceTile> createState() => _ChoiceTileState();
}

class _ChoiceTileState extends State<_ChoiceTile> {
  bool _active = false;
  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      mouseCursor: SystemMouseCursors.click,
      onShowHoverHighlight: (v) => setState(() => _active = v),
      onShowFocusHighlight: (v) => setState(() => _active = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => widget.onTap(),
        ),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _active ? AppColors.surface3 : AppColors.surface2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _active ? AppColors.accent : AppColors.border,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 34,
                color: _active ? AppColors.accent : AppColors.textDim,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
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
              ?widget.trailing,
            ],
          ),
        ),
      ),
    );
  }
}
