import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/downloads.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../state/app_state.dart';
import '../nav.dart';
import '../neu.dart';
import '../theme.dart';
import '../widgets/collection.dart';
import '../widgets/common.dart';
import '../widgets/cover.dart';
import '../widgets/track_tile.dart';
import 'downloads_screen.dart';

/// "Klasörler" tab: the music folders as they are on the disk.
class FoldersScreen extends StatelessWidget {
  const FoldersScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const FolderScreen(path: '', title: 'Klasörler');
}

class FolderScreen extends StatefulWidget {
  final String path;
  final String title;
  const FolderScreen({super.key, required this.path, required this.title});

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen> {
  bool _busy = false;

  /// Every song below this folder (sub folders too).
  Future<List<Track>?> _all() async {
    setState(() => _busy = true);
    final r = await context.read<AppState>().call(
      (a) => a.browse(widget.path, recursive: true),
    );
    if (mounted) setState(() => _busy = false);
    return r?.tracks;
  }

  Future<void> _play(BrowseResult b, {bool shuffle = false}) async {
    final tracks = b.dirs.isEmpty ? b.tracks : await _all();
    if (tracks == null || tracks.isEmpty || !mounted) return;
    await playList(
      context,
      tracks,
      index: shuffle ? -1 : 0,
      shuffle: shuffle,
      name: b.name,
    );
  }

  Future<void> _download(BrowseResult b) async {
    final dl = context.read<Downloads>();
    final key = 'folder:${b.path}';
    final saved = dl.collection(key);
    if (saved != null && dl.allDownloaded(saved.trackIds)) {
      showToast(context, 'Bu klasör zaten indirildi');
      return;
    }
    final tracks = b.dirs.isEmpty ? b.tracks : await _all();
    if (tracks == null || tracks.isEmpty || !mounted) return;
    dl.download(
      tracks,
      collection: DownloadCollection(
        key: key,
        type: 'folder',
        id: b.path,
        name: b.name,
        subtitle: 'Klasör',
        trackIds: tracks.map((t) => t.id).toList(),
        at: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    showToast(context, '${tracks.length} şarkı indiriliyor');
  }

  @override
  Widget build(BuildContext context) {
    final root = widget.path.isEmpty;
    return Scaffold(
      body: DataView<BrowseResult>(
        load: (api) async {
          var r = await api.browse(widget.path);
          // only one music folder: show its contents right away
          if (root && r.dirs.length == 1 && r.tracks.isEmpty) {
            r = await api.browse(r.dirs.first.path);
          }
          return r;
        },
        offline: const _OfflineFolders(),
        builder: (context, b, reload) {
          final title = b.name.isNotEmpty ? b.name : widget.title;
          final header = root
              ? PageTitle(
                  'Klasörler',
                  actions: [
                    IconButton(
                      tooltip: 'İndirilenler',
                      icon: const Icon(Icons.download_done_rounded),
                      onPressed: () => ShellNav.push(const DownloadsScreen()),
                    ),
                  ],
                )
              : null;
          final body = CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              if (header != null) SliverToBoxAdapter(child: header),
              if (!root)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 74,
                          height: 74,
                          child: CoverImage(
                            cover: b.cover,
                            radius: 12,
                            placeholderIcon: Icons.folder_rounded,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(songCount(b.count), style: T.dim),
                              if (b.dirs.isNotEmpty)
                                Text('${b.dirs.length} klasör', style: T.faint),
                            ],
                          ),
                        ),
                        if (_busy)
                          const Padding(
                            padding: EdgeInsets.all(10),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        _FolderDownloadIcon(
                          path: b.path,
                          onTap: () => _download(b),
                        ),
                        NeuIconButton(
                          Icons.shuffle_rounded,
                          size: 44,
                          tooltip: 'Karışık çal',
                          onTap: b.count == 0
                              ? null
                              : () => _play(b, shuffle: true),
                        ),
                        const SizedBox(width: 12),
                        NeuIconButton(
                          Icons.play_arrow_rounded,
                          size: 52,
                          iconSize: 30,
                          accent: true,
                          tooltip: 'Hepsini çal',
                          onTap: b.count == 0 ? null : () => _play(b),
                        ),
                      ],
                    ),
                  ),
                ),
              if (root && b.dirs.isEmpty)
                const SliverToBoxAdapter(
                  child: EmptyState(
                    icon: Icons.folder_off_rounded,
                    title: 'Müzik klasörü yok',
                    message:
                        'Ayarlar > Sunucu ayarları bölümünden müzik klasörü ekleyebilirsin.',
                  ),
                ),
              SliverList.builder(
                itemCount: b.dirs.length,
                itemBuilder: (context, i) {
                  final d = b.dirs[i];
                  return FadeSlideIn(
                    index: i,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 2,
                      ),
                      leading: SizedBox(
                        width: 52,
                        height: 52,
                        child: FolderCover(cover: d.cover, radius: 10),
                      ),
                      title: Text(
                        d.name,
                        style: T.body.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(songCount(d.count), style: T.dim),
                      trailing: const Icon(
                        Icons.chevron_right_rounded,
                        color: C.textFaint,
                      ),
                      onTap: () => Navigator.of(context).push(
                        ShellNav.route(
                          FolderScreen(path: d.path, title: d.name),
                        ),
                      ),
                    ),
                  );
                },
              ),
              if (b.dirs.isNotEmpty && b.tracks.isNotEmpty)
                const SliverToBoxAdapter(child: SectionHeader('Şarkılar')),
              SliverList.builder(
                itemCount: b.tracks.length,
                itemBuilder: (context, i) => TrackTile(
                  track: b.tracks[i],
                  onTap: () =>
                      playList(context, b.tracks, index: i, name: title),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 140)),
            ],
          );
          return root ? body : SubPage(title: title, child: body);
        },
      ),
    );
  }
}

class _FolderDownloadIcon extends StatelessWidget {
  final String path;
  final VoidCallback onTap;
  const _FolderDownloadIcon({required this.path, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final dl = context.watch<Downloads>();
    final c = dl.collection('folder:$path');
    final done = c != null && dl.allDownloaded(c.trackIds);
    final busy = c != null && dl.anyQueued(c.trackIds);
    return IconButton(
      tooltip: done ? 'İndirildi' : 'Klasörü indir',
      onPressed: busy ? null : onTap,
      icon: done
          ? const Icon(Icons.download_done_rounded, color: C.accent)
          : busy
          ? SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                value: dl.progressOf(c.trackIds),
              ),
            )
          : const Icon(Icons.download_for_offline_outlined, color: C.textDim),
    );
  }
}

/// Offline: downloaded folders and the rest of the downloads.
class _OfflineFolders extends StatelessWidget {
  const _OfflineFolders();
  @override
  Widget build(BuildContext context) {
    final dl = context.watch<Downloads>();
    final folders = dl.collections.where((c) => c.type == 'folder').toList();
    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: PageTitle('Klasörler')),
        if (folders.isEmpty)
          SliverToBoxAdapter(
            child: EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Klasörler çevrimdışı açılamıyor',
              message: 'İndirdiğin klasörler burada görünür.',
              action: AccentPill(
                'İNDİRİLENLER',
                onTap: () => ShellNav.push(const DownloadsScreen()),
              ),
            ),
          ),
        SliverList.builder(
          itemCount: folders.length,
          itemBuilder: (context, i) {
            final c = folders[i];
            final tracks = dl.collectionTracks(c);
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 2,
              ),
              leading: SizedBox(
                width: 52,
                height: 52,
                child: FolderCover(
                  cover: tracks.isEmpty ? '' : tracks.first.cover,
                  radius: 10,
                ),
              ),
              title: Text(c.name, style: T.body),
              subtitle: Text(songCount(tracks.length), style: T.dim),
              onTap: () => ShellNav.push(
                DownloadedCollectionScreen(collectionKey: c.key),
              ),
            );
          },
        ),
      ],
    );
  }
}
