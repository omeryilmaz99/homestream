import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/downloads.dart';
import '../../core/models.dart';
import '../nav.dart';
import '../theme.dart';
import '../track_menu.dart';
import '../widgets/collection.dart';
import '../widgets/common.dart';
import '../widgets/cover.dart';
import '../widgets/rows.dart';
import '../widgets/track_tile.dart';
import 'tracks_screen.dart';

class ArtistScreen extends StatelessWidget {
  final String id;
  final String name;
  const ArtistScreen({super.key, required this.id, this.name = ''});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DataView<ArtistDetail>(
        load: (api) => api.artist(id),
        offline: _OfflineArtist(id: id, name: name),
        builder: (context, d, reload) => _ArtistBody(d: d),
      ),
    );
  }
}

class _ArtistBody extends StatelessWidget {
  final ArtistDetail d;
  const _ArtistBody({required this.d});

  @override
  Widget build(BuildContext context) {
    final a = d.artist;
    final top = d.top.take(5).toList();
    return CollectionView(
      kicker: 'SANATÇI',
      title: a.name,
      roundCover: true,
      cover: CoverImage(
        cover: a.cover,
        circle: true,
        width: 640,
        placeholderIcon: Icons.person_rounded,
      ),
      subtitle: a.albumCount > 0
          ? Text(
              a.albumCount == 1 ? '1 albüm' : '${a.albumCount} albüm',
              style: T.dim,
            )
          : null,
      // play / shuffle use every song of the artist
      tracks: const [],
      playable: d.tracks,
      contextName: a.name,
      empty: const SizedBox.shrink(),
      actions: [
        CollectionDownloadButton(
          keyName: 'artist:${a.id}',
          type: 'artist',
          id: a.id,
          name: a.name,
          subtitle: 'Sanatçı',
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
      ],
      headerExtra: [
        if (top.isNotEmpty)
          SectionHeader(
            'Popüler Şarkılar',
            action: d.tracks.length > top.length
                ? 'Tümünü Gör (${d.tracks.length})'
                : null,
            onAction: () => ShellNav.push(
              TracksScreen(
                title: a.name,
                preset: d.tracks,
                contextName: a.name,
              ),
            ),
          ),
        for (var i = 0; i < top.length; i++)
          TrackTile(
            track: top[i],
            rank: i + 1,
            showAlbum: true,
            onTap: () => playList(context, d.top, index: i, name: a.name),
          ),
      ],
      slivers: [
        if (d.albums.isNotEmpty)
          SliverToBoxAdapter(
            child: AlbumRow(title: 'Albümler', albums: d.albums),
          ),
        if (d.appearsOn.isNotEmpty)
          SliverToBoxAdapter(
            child: AlbumRow(title: 'Yer aldığı albümler', albums: d.appearsOn),
          ),
      ],
    );
  }
}

class _OfflineArtist extends StatelessWidget {
  final String id;
  final String name;
  const _OfflineArtist({required this.id, required this.name});
  @override
  Widget build(BuildContext context) {
    final tracks = context
        .watch<Downloads>()
        .tracks
        .where((t) => t.artistId == id)
        .toList();
    if (tracks.isEmpty) {
      return const EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Çevrimdışı',
        message: 'Bu sanatçının indirilmiş şarkısı yok.',
      );
    }
    return CollectionView(
      kicker: 'SANATÇI • İNDİRİLENLER',
      title: name.isNotEmpty ? name : tracks.first.artist,
      roundCover: true,
      cover: CoverImage(
        cover: tracks.first.cover,
        coverId: tracks.first.coverId,
        circle: true,
        width: 640,
      ),
      tracks: tracks,
      contextName: name,
    );
  }
}
