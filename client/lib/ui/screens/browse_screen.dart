import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/net_image.dart';
import 'detail_dialog.dart';

/// Plain folder browser over the server's library folders, for opening
/// videos manually.
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});
  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  late final AppState _state = context.read<AppState>();
  String _path = '';
  BrowseResult? _result;
  String? _error;
  bool _loading = false;
  final List<String> _crumbNames = [];

  @override
  void initState() {
    super.initState();
    _state.dataVersion.addListener(_reload);
    _open('');
  }

  @override
  void dispose() {
    _state.dataVersion.removeListener(_reload);
    super.dispose();
  }

  void _reload() => _open(_path, keepCrumbs: true);

  Future<void> _open(String path, {bool keepCrumbs = false}) async {
    final api = _state.api;
    if (api == null) return;
    setState(() => _loading = true);
    try {
      final r = await api.browse(path);
      if (!mounted) return;
      setState(() {
        _path = r.path;
        _result = r;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
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
      if (mounted) openDetail(context, item);
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(48, 100, 48, 6),
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
          padding: const EdgeInsets.fromLTRB(40, 4, 48, 12),
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
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: ListView.builder(
                    key: ValueKey(r.path),
                    padding: const EdgeInsets.fromLTRB(40, 0, 40, 40),
                    itemCount: r.entries.length,
                    itemBuilder: (context, i) {
                      final e = r.entries[i];
                      return _EntryTile(
                        entry: e,
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
  const _EntryTile({required this.entry, required this.onTap});
  @override
  State<_EntryTile> createState() => _EntryTileState();
}

class _EntryTileState extends State<_EntryTile> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final progress =
        e.duration > 0 && e.userData.position > 0 && !e.userData.played
        ? e.userData.position / e.duration
        : 0.0;
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
