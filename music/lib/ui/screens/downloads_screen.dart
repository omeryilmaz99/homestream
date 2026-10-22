import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/downloads.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../nav.dart';
import '../theme.dart';
import '../track_menu.dart';
import '../widgets/collection.dart';
import '../widgets/common.dart';
import '../widgets/cover.dart';
import '../widgets/track_tile.dart';

/// Everything saved on the phone; works without the server.
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dl = context.watch<Downloads>();
    final tasks = dl.tasks;
    final failed = tasks.where((t) => t.state == DlState.failed).length;
    final cols = dl.collections;
    final tracks = dl.tracks;
    return Scaffold(
      body: SubPage(
        title: 'İndirilenler',
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  tracks.isEmpty
                      ? 'İndirdiğin şarkılar sunucuya bağlı olmasan da burada çalınır.'
                      : '${songCount(tracks.length)} • ${formatSize(dl.totalBytes)}',
                  style: T.dim,
                ),
              ),
            ),
            if (tasks.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 8, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'İndiriliyor (${tasks.length})',
                          style: T.h3,
                        ),
                      ),
                      if (failed > 0)
                        TextButton(
                          onPressed: dl.retryFailed,
                          child: const Text('Tekrar dene'),
                        ),
                      TextButton(
                        onPressed: () async {
                          if (await confirm(
                            context,
                            title: 'Tüm indirmeler iptal edilsin mi?',
                            ok: 'İptal et',
                          )) {
                            dl.cancelAll();
                          }
                        },
                        child: const Text(
                          'Tümünü iptal et',
                          style: TextStyle(color: C.textDim),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverList.builder(
                itemCount: tasks.length > 30 ? 30 : tasks.length,
                itemBuilder: (context, i) => _TaskTile(task: tasks[i]),
              ),
              if (tasks.length > 30)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 6,
                    ),
                    child: Text(
                      've ${tasks.length - 30} şarkı daha sırada',
                      style: T.faint,
                    ),
                  ),
                ),
            ],
            if (cols.isNotEmpty) ...[
              const SliverToBoxAdapter(
                child: SectionHeader('Listeler ve albümler'),
              ),
              SliverList.builder(
                itemCount: cols.length,
                itemBuilder: (context, i) {
                  final c = cols[i];
                  final ct = dl.collectionTracks(c);
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 2,
                    ),
                    leading: SizedBox(
                      width: 52,
                      height: 52,
                      child: collectionCover(c, ct),
                    ),
                    title: Text(
                      c.name,
                      style: T.body,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${_typeName(c.type)} • ${ct.length}/${c.trackIds.length} şarkı',
                      style: T.dim,
                    ),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: C.textFaint,
                    ),
                    onTap: () => ShellNav.push(
                      DownloadedCollectionScreen(collectionKey: c.key),
                    ),
                  );
                },
              ),
            ],
            if (tracks.isNotEmpty) ...[
              SectionHeaderSliver(
                'Tüm indirilen şarkılar',
                action: 'Karışık çal',
                onAction: () => playList(
                  context,
                  tracks,
                  index: -1,
                  shuffle: true,
                  name: 'İndirilenler',
                ),
              ),
              SliverList.builder(
                itemCount: tracks.length,
                itemBuilder: (context, i) => TrackTile(
                  track: tracks[i],
                  showAlbum: true,
                  onTap: () =>
                      playList(context, tracks, index: i, name: 'İndirilenler'),
                ),
              ),
            ],
            if (tracks.isEmpty && tasks.isEmpty)
              const SliverToBoxAdapter(
                child: EmptyState(
                  icon: Icons.download_for_offline_outlined,
                  title: 'Henüz indirme yok',
                  message:
                      'Bir albümde, çalma listesinde ya da klasörde ↓ simgesine dokun. '
                      'Tek şarkı için ⋮ menüsünden "İndir"i seç.',
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 140)),
          ],
        ),
      ),
    );
  }
}

String _typeName(String t) => switch (t) {
  'playlist' => 'Çalma listesi',
  'album' => 'Albüm',
  'artist' => 'Sanatçı',
  'folder' => 'Klasör',
  'liked' => 'Beğenilenler',
  _ => 'Liste',
};

Widget collectionCover(
  DownloadCollection c,
  List<Track> tracks, {
  double radius = 10,
}) {
  if (c.type == 'liked') return LikedCover(radius: radius);
  if (tracks.isEmpty) {
    return CoverPlaceholder(c.key, icon: Icons.download_rounded);
  }
  if (c.type == 'playlist') {
    return MosaicCover(
      covers: [for (final t in tracks.take(4)) t.cover],
      seed: c.key,
      radius: radius,
    );
  }
  if (c.type == 'folder') {
    return FolderCover(cover: tracks.first.cover, radius: radius);
  }
  return CoverImage(
    cover: tracks.first.cover,
    coverId: tracks.first.coverId,
    radius: radius,
    circle: c.type == 'artist',
  );
}

class SectionHeaderSliver extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const SectionHeaderSliver(
    this.title, {
    super.key,
    this.action,
    this.onAction,
  });
  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: SectionHeader(title, action: action, onAction: onAction),
  );
}

class _TaskTile extends StatelessWidget {
  final DownloadTask task;
  const _TaskTile({required this.task});
  @override
  Widget build(BuildContext context) {
    final t = task.track;
    final failed = task.state == DlState.failed;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: SizedBox(
        width: 44,
        height: 44,
        child: CoverImage(
          cover: t.cover,
          coverId: t.coverId,
          radius: 6,
          width: 120,
        ),
      ),
      title: Text(
        t.title,
        style: T.body,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: failed
          ? Text(task.error ?? 'Hata', style: T.faint.copyWith(color: C.danger))
          : Padding(
              padding: const EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(
                value: task.state == DlState.running && task.total > 0
                    ? task.progress
                    : null,
                minHeight: 3,
                backgroundColor: C.bgDeep,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
      trailing: IconButton(
        tooltip: 'İptal',
        icon: const Icon(Icons.close_rounded, color: C.textDim),
        onPressed: () => context.read<Downloads>().cancel(t.id),
      ),
    );
  }
}

/// A downloaded playlist / album / folder (works offline).
class DownloadedCollectionScreen extends StatelessWidget {
  final String collectionKey;
  const DownloadedCollectionScreen({super.key, required this.collectionKey});

  @override
  Widget build(BuildContext context) {
    final dl = context.watch<Downloads>();
    final c = dl.collection(collectionKey);
    if (c == null) {
      return const Scaffold(
        body: SubPage(
          title: 'İndirilenler',
          child: EmptyState(
            icon: Icons.delete_outline_rounded,
            title: 'Bu indirme silindi',
          ),
        ),
      );
    }
    final tracks = dl.collectionTracks(c);
    return Scaffold(
      body: CollectionView(
        kicker: '${_typeName(c.type).toUpperCase()} • İNDİRİLDİ',
        title: c.name,
        cover: collectionCover(c, tracks, radius: 14),
        roundCover: c.type == 'artist',
        tracks: tracks,
        contextName: c.name,
        numbered: c.type == 'album',
        actions: [
          IconButton(
            tooltip: 'İndirileni sil',
            icon: const Icon(
              Icons.delete_outline_rounded,
              size: 28,
              color: C.textDim,
            ),
            onPressed: () async {
              final ok = await confirm(
                context,
                title: 'İndirilen "${c.name}" silinsin mi?',
                message:
                    'Şarkılar sunucuda kalır; yalnızca bu telefondaki kopyalar silinir.',
              );
              if (!ok) return;
              await dl.removeCollection(c.key);
              if (context.mounted) Navigator.maybePop(context);
            },
          ),
        ],
      ),
    );
  }
}
