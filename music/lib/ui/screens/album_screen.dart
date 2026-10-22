import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/downloads.dart';
import '../../core/models.dart';
import '../../state/app_state.dart';
import '../nav.dart';
import '../theme.dart';
import '../track_menu.dart';
import '../widgets/collection.dart';
import '../widgets/common.dart';
import '../widgets/cover.dart';
import '../widgets/rows.dart';
import 'artist_screen.dart';

class AlbumScreen extends StatelessWidget {
  final String id;
  final String title;
  const AlbumScreen({super.key, required this.id, this.title = ''});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DataView<AlbumDetail>(
        load: (api) => api.album(id),
        offline: _OfflineAlbum(id: id, title: title),
        builder: (context, d, reload) => _AlbumBody(d: d),
      ),
    );
  }
}

class _AlbumBody extends StatelessWidget {
  final AlbumDetail d;
  const _AlbumBody({required this.d});

  @override
  Widget build(BuildContext context) {
    final a = d.album;
    final sub = [
      if (a.year > 0) '${a.year}',
      if (a.genre.isNotEmpty) a.genre,
    ].join(' • ');
    return CollectionView(
      kicker: 'ALBÜM',
      title: a.title,
      cover: CoverImage(cover: a.cover, radius: 14, width: 640),
      subtitle: Column(
        children: [
          GestureDetector(
            onTap: a.artistId.isEmpty
                ? null
                : () => ShellNav.push(
                    ArtistScreen(id: a.artistId, name: a.artist),
                  ),
            child: Text(a.artist, style: T.h3.copyWith(color: C.textDim)),
          ),
          if (sub.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(sub, style: T.faint),
          ],
        ],
      ),
      tracks: d.tracks,
      contextName: a.title,
      numbered: true,
      actions: [
        CollectionDownloadButton(
          keyName: 'album:${a.id}',
          type: 'album',
          id: a.id,
          name: a.title,
          subtitle: a.artist,
          tracks: d.tracks,
        ),
        IconButton(
          tooltip: 'Çalma listesine ekle',
          icon: const Icon(
            Icons.playlist_add_rounded,
            size: 30,
            color: C.textDim,
          ),
          onPressed: () => showAddToPlaylist(context, d.tracks),
        ),
        IconButton(
          tooltip: 'Tümünü beğen',
          icon: const Icon(
            Icons.favorite_border_rounded,
            size: 27,
            color: C.textDim,
          ),
          onPressed: () {
            final app = context.read<AppState>();
            final allLiked = d.tracks.every(app.isLiked);
            app.setLiked(d.tracks, !allLiked);
            showToast(
              context,
              allLiked
                  ? 'Beğeniler kaldırıldı'
                  : 'Albümdeki şarkılar beğenildi',
            );
          },
        ),
      ],
      slivers: [
        if (d.moreByArtist.isNotEmpty)
          SliverToBoxAdapter(
            child: AlbumRow(
              title: '${a.artist} — diğer albümler',
              albums: d.moreByArtist,
            ),
          ),
      ],
    );
  }
}

/// Offline: the album from the downloaded songs.
class _OfflineAlbum extends StatelessWidget {
  final String id;
  final String title;
  const _OfflineAlbum({required this.id, required this.title});

  @override
  Widget build(BuildContext context) {
    final dl = context.watch<Downloads>();
    final tracks = dl.tracks.where((t) => t.albumId == id).toList()
      ..sort(
        (a, b) => a.discNo != b.discNo
            ? a.discNo.compareTo(b.discNo)
            : a.trackNo.compareTo(b.trackNo),
      );
    if (tracks.isEmpty) {
      return const EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Çevrimdışı',
        message: 'Bu albümden indirilmiş şarkı yok.',
      );
    }
    final t = tracks.first;
    return CollectionView(
      kicker: 'ALBÜM • İNDİRİLENLER',
      title: title.isNotEmpty ? title : t.album,
      cover: CoverImage(
        cover: t.cover,
        coverId: t.coverId,
        radius: 14,
        width: 640,
      ),
      subtitle: Text(
        t.albumArtist.isNotEmpty ? t.albumArtist : t.artist,
        style: T.h3.copyWith(color: C.textDim),
      ),
      tracks: tracks,
      contextName: t.album,
      numbered: true,
    );
  }
}
