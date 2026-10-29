import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../state/app_state.dart';
import '../layout.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/net_image.dart';
import 'detail_dialog.dart';
import 'play_launcher.dart';

/// Plain folder browser over the server's library folders, for opening
/// videos manually.
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});
  @override
  State<BrowseScreen> createState() => BrowseScreenState();
}

class BrowseScreenState extends State<BrowseScreen> {
  late final AppState _state = context.read<AppState>();
  String _path = '';
  BrowseResult? _result;
  String? _error;
  bool _loading = false;
  final List<String> _crumbNames = [];
  // remote/keyboard: where focus goes after opening a folder
  final _pageFocus = FocusNode(canRequestFocus: false, skipTraversal: true);
  // a fresh node per folder: the old list stays built while it fades out
  FocusNode _targetFocus = FocusNode();
  final _scroll = ScrollController();
  String _focusPath = '';

  /// Back button: opens the parent folder. False at the top level.
  bool goUp() {
    final parent = _result?.parent;
    if (parent == null) return false;
    _open(parent);
    return true;
  }

  @override
  void initState() {
    super.initState();
    _state.dataVersion.addListener(_reload);
    _open('');
  }

  @override
  void dispose() {
    _state.dataVersion.removeListener(_reload);
    _pageFocus.dispose();
    _targetFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _reload() => _open(_path, keepCrumbs: true);

  Future<void> _open(String path, {bool keepCrumbs = false}) async {
    final api = _state.api;
    if (api == null) return;
    final hadFocus = _pageFocus.hasFocus;
    final from = _path;
    setState(() => _loading = true);
    try {
      final r = await api.browse(path);
      if (!mounted) return;
      final changed = r.path != _path;
      setState(() {
        _path = r.path;
        _result = r;
        _error = null;
        _loading = false;
        // going up: focus the folder we came out of, else the first entry
        if (changed) {
          _focusPath = from;
          final old = _targetFocus;
          _targetFocus = FocusNode();
          Future.delayed(const Duration(seconds: 2), old.dispose);
        }
      });
      if (changed && hadFocus) _focusTarget();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  int _targetIndex(BrowseResult r) {
    final i = r.entries.indexWhere(
      (e) =>
          e.isDir &&
          _focusPath.isNotEmpty &&
          (_focusPath == e.path || _focusPath.startsWith('${e.path}/')),
    );
    return i < 0 ? 0 : i;
  }

  void _focusTarget() {
    final r = _result;
    if (r == null || r.entries.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_targetFocus.context == null && _scroll.hasClients) {
        // not built yet (far down the list): scroll near it first
        _scroll.jumpTo(
          (_targetIndex(r) * 72.0).clamp(0, _scroll.position.maxScrollExtent),
        );
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _targetFocus.requestFocus(),
        );
      } else {
        _targetFocus.requestFocus();
      }
    });
  }

  List<(String, String)> _crumbs() {
    final res = <(String, String)>[('', 'Kütüphane')];
    if (_path.isEmpty) return res;
    final parts = _path.split('/');
    for (var i = 0; i < parts.length; i++) {
      final p = parts.sublist(0, i + 1).join('/');
      final name = i == 0 && _result != null && parts.length == 1
          ? _result!.name
          : parts[i];
      res.add((p, i == 0 ? (_rootNames[parts[0]] ?? name) : name));
    }
    return res;
  }

  final Map<String, String> _rootNames = {};

  Future<void> _openVideo(BrowseEntry e) async {
    if (e.itemId.isEmpty) {
      showToast(
        context,
        'Bu dosya henüz taranmadı. Biraz sonra tekrar dene.',
        error: true,
      );
      return;
    }
    try {
      final item = await _state.api!.item(e.itemId);
      if (!mounted) return;
      final inProgress = e.userData.position > 0 && e.duration > 0;
      if (!inProgress) {
        openDetail(context, item);
        return;
      }
      // half watched: ask where to start
      final choice = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: AppColors.surface,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  e.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              ListTile(
                autofocus: true,
                leading: const Icon(Icons.play_arrow_rounded),
                title: Text(
                  'Kaldığın yerden devam et (${formatDuration(e.userData.position)})',
                ),
                onTap: () => Navigator.pop(ctx, 'resume'),
              ),
              ListTile(
                leading: const Icon(Icons.replay_rounded),
                title: const Text('Baştan başla'),
                onTap: () => Navigator.pop(ctx, 'start'),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('Detaylar'),
                onTap: () => Navigator.pop(ctx, 'detail'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
      if (!mounted || choice == null) return;
      if (choice == 'detail') {
        openDetail(context, item);
      } else {
        await playItem(
          context,
          item,
          startAt: choice == 'start' ? 0 : e.userData.position,
        );
      }
    } catch (err) {
      if (mounted) showToast(context, err.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    if (r != null && r.path.isEmpty) {
      for (final e in r.entries) {
        _rootNames[e.path] = e.name;
      }
    }
    _crumbNames.clear();
    final crumbs = _crumbs();
    final target = r == null ? -1 : _targetIndex(r);
    return Focus(
      focusNode: _pageFocus,
      child: _page(context, r, crumbs, target),
    );
  }

  Widget _page(
    BuildContext context,
    BrowseResult? r,
    List<(String, String)> crumbs,
    int target,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            pagePad(context),
            pageTop(context),
            pagePad(context),
            6,
          ),
          child: Row(
            children: [
              const Text(
                'Klasörler',
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                ),
              ),
              const Spacer(),
              if (_loading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            pagePad(context) - 8,
            4,
            pagePad(context),
            12,
          ),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (r?.parent != null)
                IconButton(
                  tooltip: 'Üst klasör',
                  onPressed: () => _open(r!.parent!),
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
              for (var i = 0; i < crumbs.length; i++) ...[
                if (i > 0)
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textMuted,
                    size: 20,
                  ),
                TextButton(
                  onPressed: i == crumbs.length - 1
                      ? null
                      : () => _open(crumbs[i].$1),
                  child: Text(
                    crumbs[i].$2,
                    style: TextStyle(
                      fontSize: 15,
                      color: i == crumbs.length - 1
                          ? Colors.white
                          : AppColors.textDim,
                      fontWeight: i == crumbs.length - 1
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: _error != null && r == null
              ? ErrorState(message: _error!, onRetry: () => _open(_path))
              : r == null
              ? const SizedBox.shrink()
              : r.entries.isEmpty
              ? const EmptyState(
                  icon: Icons.folder_open_rounded,
                  title: 'Bu klasör boş',
                  message: 'Burada video dosyası veya alt klasör yok.',
                )
              : TweenAnimationBuilder<double>(
                  // one list at a time (focus and scroll position follow it)
                  key: ValueKey(r.path),
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 200),
                  builder: (context, v, child) =>
                      Opacity(opacity: v, child: child),
                  child: ListView.builder(
                    key: ValueKey(r.path),
                    controller: _scroll,
                    padding: EdgeInsets.fromLTRB(
                      pagePad(context) - 8,
                      0,
                      pagePad(context) - 8,
                      pageBottom(context),
                    ),
                    itemCount: r.entries.length,
                    itemBuilder: (context, i) {
                      final e = r.entries[i];
                      return _EntryTile(
                        entry: e,
                        focusNode: i == target ? _targetFocus : null,
                        onTap: () => e.isDir ? _open(e.path) : _openVideo(e),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _EntryTile extends StatefulWidget {
  final BrowseEntry entry;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  const _EntryTile({required this.entry, required this.onTap, this.focusNode});
  @override
  State<_EntryTile> createState() => _EntryTileState();
}

class _EntryTileState extends State<_EntryTile> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final progress = e.duration > 0 && e.userData.position > 0
        ? e.userData.position / e.duration
        : 0.0;
    return FocusableActionDetector(
      focusNode: widget.focusNode,
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
          duration: const Duration(milliseconds: 140),
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _hover ? AppColors.surface2 : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              SizedBox(
                width: e.isDir ? 48 : 128,
                height: e.isDir ? 48 : 72,
                child: e.isDir
                    ? Container(
                        decoration: BoxDecoration(
                          color: AppColors.surface3,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.folder_rounded,
                          color: Color(0xFFFBBF24),
                          size: 28,
                        ),
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            e.thumb.isNotEmpty
                                ? NetImage(e.thumb, width: 320)
                                : const ColoredBox(
                                    color: AppColors.surface3,
                                    child: Icon(
                                      Icons.movie_rounded,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                            if (progress > 0)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: ProgressLine(progress, height: 3),
                              ),
                            if (e.userData.played)
                              const Positioned(
                                top: 4,
                                right: 4,
                                child: Icon(
                                  Icons.check_circle_rounded,
                                  color: AppColors.success,
                                  size: 18,
                                ),
                              ),
                          ],
                        ),
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    if (!e.isDir)
                      Text(
                        [
                          if (e.duration > 0) formatDuration(e.duration),
                          if (e.size > 0) formatSize(e.size),
                        ].join(' · '),
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    if (!e.isDir && progress > 0)
                      Text(
                        'Kaldığın yer ${formatDuration(e.userData.position)} · ${formatRemaining(e.userData.position, e.duration)}',
                        style: TextStyle(
                          color: AppColors.accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else if (!e.isDir && e.userData.played)
                      const Text(
                        'İzlendi',
                        style: TextStyle(
                          color: AppColors.success,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                e.isDir
                    ? Icons.chevron_right_rounded
                    : Icons.play_circle_outline_rounded,
                color: _hover ? Colors.white : AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
