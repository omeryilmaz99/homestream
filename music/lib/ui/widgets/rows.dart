import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../audio/handler.dart';
import '../../core/models.dart';
import '../nav.dart';
import '../neu.dart';
import '../screens/album_screen.dart';
import '../screens/artist_screen.dart';
import '../screens/liked_screen.dart';
import '../screens/playlist_screen.dart';
import '../theme.dart';
import '../track_menu.dart';
import 'common.dart';
import 'cover.dart';
import 'track_tile.dart';

/// Square card: rounded cover, two lines of text.
class MediaCard extends StatelessWidget {
  final Widget cover;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double width;
  final bool round;
  const MediaCard({
    super.key,
    required this.cover,
    required this.title,
    this.subtitle = '',
    this.onTap,
    this.onLongPress,
    this.width = 132,
    this.round = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: PressScale(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: round
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            Container(
              width: width,
              height: width,
              decoration: BoxDecoration(
                shape: round ? BoxShape.circle : BoxShape.rectangle,
                borderRadius: round ? null : BorderRadius.circular(12),
                boxShadow: neuShadows(depth: 0.5),
              ),
              child: cover,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: round ? TextAlign.center : TextAlign.start,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: C.text,
              ),
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: round ? TextAlign.center : TextAlign.start,
                style: T.faint,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class HorizontalRow extends StatelessWidget {
  final String title;
  final int count;
  final Widget Function(BuildContext, int) itemBuilder;
  final double height;
  final String? action;
  final VoidCallback? onAction;
  const HorizontalRow({
    super.key,
    required this.title,
    required this.count,
    required this.itemBuilder,
    this.height = 186,
    this.action,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title, action: action, onAction: onAction),
        SizedBox(
          height: height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            clipBehavior: Clip.none,
            itemCount: count,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, i) =>
                FadeSlideIn(index: i, child: itemBuilder(context, i)),
          ),
        ),
      ],
    );
  }
}

class AlbumRow extends StatelessWidget {
  final String title;
  final List<Album> albums;
  const AlbumRow({super.key, required this.title, required this.albums});
  @override
  Widget build(BuildContext context) {
    return HorizontalRow(
      title: title,
      count: albums.length,
      itemBuilder: (context, i) => AlbumCard(album: albums[i]),
    );
  }
}

class AlbumCard extends StatelessWidget {
  final Album album;
  final double width;
  const AlbumCard({super.key, required this.album, this.width = 132});
  @override
  Widget build(BuildContext context) {
    return MediaCard(
      width: width,
      cover: CoverImage(cover: album.cover, radius: 12),
      title: album.title,
      subtitle: [
        if (album.year > 0) '${album.year}',
        album.artist,
      ].where((e) => e.isNotEmpty).join(' • '),
      onTap: () => ShellNav.push(AlbumScreen(id: album.id, title: album.title)),
    );
  }
}

class ArtistCard extends StatelessWidget {
  final Artist artist;
  final double width;
  final String subtitle;
  const ArtistCard({
    super.key,
    required this.artist,
    this.width = 112,
    this.subtitle = 'Sanatçı',
  });
  @override
  Widget build(BuildContext context) {
    return MediaCard(
      width: width,
      round: true,
      cover: CoverImage(
        cover: artist.cover,
        circle: true,
        placeholderIcon: Icons.person_rounded,
      ),
      title: artist.name,
      subtitle: subtitle,
      onTap: () =>
          ShellNav.push(ArtistScreen(id: artist.id, name: artist.name)),
    );
  }
}

class PlaylistCard extends StatelessWidget {
  final Playlist playlist;
  final double width;
  const PlaylistCard({super.key, required this.playlist, this.width = 132});
  @override
  Widget build(BuildContext context) {
    return MediaCard(
      width: width,
      cover: MosaicCover(
        covers: playlist.covers,
        seed: playlist.id,
        radius: 12,
      ),
      title: playlist.name,
      subtitle: '${playlist.trackCount} şarkı',
      onTap: () =>
          ShellNav.push(PlaylistScreen(id: playlist.id, name: playlist.name)),
    );
  }
}

/// Opens / plays a home screen tile.
void openHomeCard(
  BuildContext context,
  HomeCard c, {
  List<HomeCard> siblings = const [],
  String rowTitle = '',
}) {
  switch (c.type) {
    case 'album':
      ShellNav.push(AlbumScreen(id: c.id, title: c.title));
    case 'artist':
      ShellNav.push(ArtistScreen(id: c.id, name: c.title));
    case 'playlist':
      ShellNav.push(PlaylistScreen(id: c.id, name: c.title));
    case 'liked':
      ShellNav.push(const LikedScreen());
    case 'track':
      if (c.track == null) return;
      final tracks = [for (final s in siblings) ?s.track];
      final i = tracks.indexWhere((t) => t.id == c.track!.id);
      if (i < 0) {
        playList(context, [c.track!], name: rowTitle);
      } else {
        playList(context, tracks, index: i, name: rowTitle);
      }
  }
}

Widget homeCardCover(HomeCard c, {double radius = 12, int width = 320}) {
  switch (c.type) {
    case 'liked':
      return LikedCover(radius: radius);
    case 'playlist':
      return MosaicCover(
        covers: c.covers,
        seed: c.id,
        radius: radius,
        width: width,
      );
    case 'artist':
      return CoverImage(
        cover: c.cover,
        circle: true,
        width: width,
        placeholderIcon: Icons.person_rounded,
      );
    default:
      return CoverImage(
        cover: c.cover,
        coverId: c.track?.coverId ?? '',
        radius: radius,
        width: width,
      );
  }
}

class HomeCardTile extends StatelessWidget {
  final HomeCard card;
  final List<HomeCard> siblings;
  final String rowTitle;
  final double width;
  const HomeCardTile({
    super.key,
    required this.card,
    this.siblings = const [],
    this.rowTitle = '',
    this.width = 132,
  });
  @override
  Widget build(BuildContext context) {
    final isTrack = card.type == 'track' && card.track != null;
    Widget cover = homeCardCover(card);
    if (isTrack) {
      final player = context.read<MusicHandler>();
      cover = Stack(
        fit: StackFit.expand,
        children: [
          cover,
          ValueListenableBuilder<Track?>(
            valueListenable: player.current,
            builder: (context, cur, _) => cur?.id == card.track!.id
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: ValueListenableBuilder<bool>(
                        valueListenable: player.playing,
                        builder: (_, p, _) => PlayingBars(animate: p, size: 26),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      );
    }
    return MediaCard(
      width: width,
      round: card.type == 'artist',
      cover: cover,
      title: card.title,
      subtitle: card.subtitle,
      onTap: () =>
          openHomeCard(context, card, siblings: siblings, rowTitle: rowTitle),
      onLongPress: isTrack ? () => showTrackMenu(context, card.track!) : null,
    );
  }
}
