import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../audio/handler.dart';
import '../../core/models.dart';
import '../neu.dart';
import '../screens/now_playing.dart';
import '../theme.dart';
import 'cover.dart';

/// The bar above the tabs: current song, play/pause, progress.
/// Tap or swipe up opens the player, swipe sideways changes the song.
class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});
  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  double _dx = 0;

  @override
  Widget build(BuildContext context) {
    final player = context.read<MusicHandler>();
    return ValueListenableBuilder<Track?>(
      valueListenable: player.current,
      builder: (context, t, _) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (c, a) => SizeTransition(
            sizeFactor: a,
            alignment: Alignment.topCenter,
            child: FadeTransition(opacity: a, child: c),
          ),
          child: t == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  key: const ValueKey('mini'),
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                  child: GestureDetector(
                    onTap: () => openNowPlaying(context),
                    onVerticalDragEnd: (d) {
                      if ((d.primaryVelocity ?? 0) < -250) {
                        openNowPlaying(context);
                      }
                    },
                    onHorizontalDragUpdate: (d) =>
                        setState(() => _dx += d.delta.dx),
                    onHorizontalDragEnd: (d) {
                      final v = d.primaryVelocity ?? 0;
                      if (_dx < -60 || v < -600) {
                        player.skipToNext();
                      } else if (_dx > 60 || v > 600) {
                        player.skipToPrevious();
                      }
                      setState(() => _dx = 0);
                    },
                    child: NeuBox(
                      radius: 16,
                      depth: 0.8,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 8, 6, 6),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 44,
                                    height: 44,
                                    child: CoverImage(
                                      cover: t.cover,
                                      coverId: t.coverId,
                                      radius: 8,
                                      width: 140,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: AnimatedContainer(
                                      duration: Duration(
                                        milliseconds: _dx == 0 ? 200 : 0,
                                      ),
                                      transform: Matrix4.translationValues(
                                        _dx * 0.5,
                                        0,
                                        0,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            t.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                              color: C.text,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            t.artist,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: T.faint.copyWith(
                                              color: C.textDim,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  ValueListenableBuilder<bool>(
                                    valueListenable: player.buffering,
                                    builder: (context, b, _) =>
                                        ValueListenableBuilder<bool>(
                                          valueListenable: player.playing,
                                          builder: (context, playing, _) => SizedBox(
                                            width: 48,
                                            height: 48,
                                            child: Stack(
                                              alignment: Alignment.center,
                                              children: [
                                                if (b && playing)
                                                  const SizedBox(
                                                    width: 40,
                                                    height: 40,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                  ),
                                                IconButton(
                                                  tooltip: playing
                                                      ? 'Duraklat'
                                                      : 'Çal',
                                                  icon: Icon(
                                                    playing
                                                        ? Icons.pause_rounded
                                                        : Icons
                                                              .play_arrow_rounded,
                                                    size: 32,
                                                    color: C.text,
                                                  ),
                                                  onPressed: player.togglePlay,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                  ),
                                  IconButton(
                                    tooltip: 'Sonraki',
                                    icon: const Icon(
                                      Icons.skip_next_rounded,
                                      size: 28,
                                      color: C.text,
                                    ),
                                    onPressed: player.skipToNext,
                                  ),
                                ],
                              ),
                            ),
                            _Progress(player: player, fallback: t.duration),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

class _Progress extends StatelessWidget {
  final MusicHandler player;
  final double fallback;
  const _Progress({required this.player, required this.fallback});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration>(
      valueListenable: player.position,
      builder: (context, pos, _) {
        final d = player.duration.value.inMilliseconds > 0
            ? player.duration.value.inMilliseconds / 1000
            : fallback;
        final v = d > 0 ? (pos.inMilliseconds / 1000 / d).clamp(0.0, 1.0) : 0.0;
        return Container(
          height: 2.5,
          alignment: Alignment.centerLeft,
          color: C.bgDeep,
          child: FractionallySizedBox(
            widthFactor: v,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [C.accentLo, C.accentHi]),
              ),
            ),
          ),
        );
      },
    );
  }
}
