import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../audio/handler.dart';
import '../../core/downloads.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../track_menu.dart';
import 'common.dart';
import 'cover.dart';

/// Small download state mark of a song: ✓ downloaded, ring while downloading.
class DownloadMark extends StatelessWidget {
  final String trackId;
  final double size;
  final double gap; // space after the mark (only when it is shown)
  const DownloadMark(this.trackId, {super.key, this.size = 14, this.gap = 0});

  @override
  Widget build(BuildContext context) {
    final st = context.select<Downloads, (bool, DlState?, int)>((d) {
      final t = d.task(trackId);
      return (
        d.isDownloaded(trackId),
        t?.state,
        ((t?.progress ?? 0) * 20).round(),
      );
    });
    Widget mark;
    if (st.$1) {
      mark = Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: C.accent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.arrow_downward_rounded,
          size: size * 0.75,
          color: Colors.black,
        ),
      );
    } else if (st.$2 == null) {
      return const SizedBox.shrink();
    } else if (st.$2 == DlState.failed) {
      mark = Icon(Icons.error_outline_rounded, size: size + 2, color: C.danger);
    } else {
      mark = SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          value: st.$2 == DlState.running && st.$3 > 0 ? st.$3 / 20 : null,
          color: C.accent,
          backgroundColor: C.bgDeep,
        ),
      );
    }
    return gap > 0
        ? Padding(
            padding: EdgeInsets.only(right: gap),
            child: mark,
          )
        : mark;
  }
}

class TrackTile extends StatelessWidget {
  final Track track;
  final VoidCallback? onTap;
  final bool showCover;
  final int? number; // album view: track number instead of cover
  final Widget? trailing;
  final Playlist? playlist; // menu: "remove from this playlist"
  final VoidCallback? onRemoved;
  final bool showAlbum;
  const TrackTile({
    super.key,
    required this.track,
    this.onTap,
    this.showCover = true,
    this.number,
    this.trailing,
    this.playlist,
    this.onRemoved,
    this.showAlbum = false,
  });

  @override
  Widget build(BuildContext context) {
    final player = context.read<MusicHandler>();
    final online = context.select<AppState, bool>((s) => s.online);
    final available =
        online ||
        context.select<Downloads, bool>((d) => d.isDownloaded(track.id));
    final sub = [
      track.artist,
      if (showAlbum && track.album.isNotEmpty) track.album,
    ].where((e) => e.isNotEmpty).join(' • ');
    return ValueListenableBuilder<Track?>(
      valueListenable: player.current,
      builder: (context, cur, _) {
        final isCur = cur?.id == track.id;
        return Opacity(
          opacity: available ? 1 : 0.4,
          child: InkWell(
            onTap: onTap,
            onLongPress: () => showTrackMenu(
              context,
              track,
              playlist: playlist,
              onRemoved: onRemoved,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 7, 4, 7),
              child: Row(
                children: [
                  if (number != null)
                    SizedBox(
                      width: 30,
                      child: isCur
                          ? ValueListenableBuilder<bool>(
                              valueListenable: player.playing,
                              builder: (_, p, _) => Align(
                                alignment: Alignment.centerLeft,
                                child: PlayingBars(animate: p, size: 14),
                              ),
                            )
                          : Text(
                              number! > 0 ? '$number' : '–',
                              style: T.dim.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                    )
                  else if (showCover)
                    Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: SizedBox(
                        width: 50,
                        height: 50,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CoverImage(
                              cover: track.cover,
                              coverId: track.coverId,
                              radius: 8,
                              width: 150,
                            ),
                            if (isCur)
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: ValueListenableBuilder<bool>(
                                    valueListenable: player.playing,
                                    builder: (_, p, _) =>
                                        PlayingBars(animate: p, size: 18),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: T.body.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isCur ? C.accent : C.text,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            DownloadMark(track.id, size: 13, gap: 5),
                            if (track.hiRes)
                              const _Badge('HI-RES')
                            else if (track.lossless)
                              const _Badge('LOSSLESS'),
                            if (track.isVideo) const _Badge('VİDEO'),
                            Expanded(
                              child: Text(
                                sub.isEmpty
                                    ? formatDuration(track.duration)
                                    : sub,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: T.dim,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  ?trailing,
                  IconButton(
                    icon: const Icon(Icons.more_vert_rounded, color: C.textDim),
                    tooltip: 'Seçenekler',
                    onPressed: () => showTrackMenu(
                      context,
                      track,
                      playlist: playlist,
                      onRemoved: onRemoved,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  const _Badge(this.text);
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: C.textDim.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.w800,
          color: C.textDim,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Plays [tracks] starting at [index]; offline only the downloaded ones.
Future<void> playList(
  BuildContext context,
  List<Track> tracks, {
  int index = 0,
  bool shuffle = false,
  String name = '',
}) async {
  final app = context.read<AppState>();
  final dl = context.read<Downloads>();
  final player = context.read<MusicHandler>();
  var list = tracks;
  var start = index;
  if (!app.online) {
    final picked = index >= 0 && index < tracks.length ? tracks[index] : null;
    list = tracks.where((t) => dl.isDownloaded(t.id)).toList();
    if (list.isEmpty) {
      showToast(context, 'Çevrimdışı: bu şarkılar indirilmemiş');
      return;
    }
    start = picked == null ? 0 : list.indexWhere((t) => t.id == picked.id);
    if (start < 0) {
      showToast(context, 'Çevrimdışı: bu şarkı indirilmemiş');
      return;
    }
  }
  await player.playTracks(
    list,
    start: shuffle && index < 0 ? -1 : start,
    shuffled: shuffle,
    context: name,
  );
}
