import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/downloads.dart';
import '../../core/models.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../track_menu.dart';
import '../widgets/collection.dart';
import '../widgets/common.dart';
import '../widgets/cover.dart';

/// "Beğenilen Şarkılar" (opened from the library and the profile).
class LikedScreen extends StatelessWidget {
  const LikedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return Scaffold(
      body: ValueListenableBuilder<Set<String>>(
        valueListenable: app.liked,
        builder: (context, liked, _) => DataView<List<Track>>(
          reloadKey: liked.length,
          load: (api) => api.liked(),
          offline: const _OfflineLiked(),
          builder: (context, tracks, reload) {
            // removed likes disappear at once; new ones come with the reload
            final list = liked.isEmpty
                ? tracks
                : tracks.where((t) => liked.contains(t.id)).toList();
            return _LikedView(tracks: list);
          },
        ),
      ),
    );
  }
}

class _LikedView extends StatelessWidget {
  final List<Track> tracks;
  final String kicker;
  const _LikedView({required this.tracks, this.kicker = 'ÇALMA LİSTESİ'});

  @override
  Widget build(BuildContext context) {
    return CollectionView(
      kicker: kicker,
      title: 'Beğenilen Şarkılar',
      cover: const LikedCover(radius: 14),
      tracks: tracks,
      contextName: 'Beğenilen Şarkılar',
      empty: const Padding(
        padding: EdgeInsets.only(top: 30),
        child: EmptyState(
          icon: Icons.favorite_border_rounded,
          title: 'Henüz beğendiğin şarkı yok',
          message: 'Şarkılardaki kalp simgesine dokunarak burada topla.',
        ),
      ),
      actions: [
        CollectionDownloadButton(
          keyName: 'liked',
          type: 'liked',
          id: 'liked',
          name: 'Beğenilen Şarkılar',
          subtitle: 'Yeni beğendiklerin de otomatik indirilir',
          tracks: tracks,
        ),
        IconButton(
          tooltip: 'Çalma listesine ekle',
          icon: const Icon(
            Icons.playlist_add_rounded,
            size: 30,
            color: C.textDim,
          ),
          onPressed: tracks.isEmpty
              ? null
              : () => showAddToPlaylist(context, tracks),
        ),
      ],
    );
  }
}

class _OfflineLiked extends StatelessWidget {
  const _OfflineLiked();
  @override
  Widget build(BuildContext context) {
    final dl = context.watch<Downloads>();
    final c = dl.collection('liked');
    final tracks = c != null
        ? dl.collectionTracks(c)
        : dl.tracks.where((t) => t.liked).toList();
    return _LikedView(tracks: tracks, kicker: 'İNDİRİLENLER');
  }
}
