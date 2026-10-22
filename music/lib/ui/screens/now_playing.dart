import 'dart:async';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../audio/handler.dart';
import '../../core/downloads.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../state/app_state.dart';
import '../nav.dart';
import '../neu.dart';
import '../theme.dart';
import '../track_menu.dart';
import '../widgets/common.dart';
import '../widgets/cover.dart';
import 'artist_screen.dart';

void openNowPlaying(BuildContext context) {
  Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder(
      opaque: false,
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, _, _) => const NowPlayingScreen(),
      transitionsBuilder: (context, a, _, child) {
        final c = CurvedAnimation(
          parent: a,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(c),
          child: child,
        );
      },
    ),
  );
}

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});
  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bg = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  );
  Color _tint = C.accentLo;
  String? _tintFor;
  double _dragY = 0;

  @override
  void initState() {
    super.initState();
    final anim = context.read<AppState>().prefs.animations;
    if (anim) _bg.repeat();
  }

  @override
  void dispose() {
    _bg.dispose();
    super.dispose();
  }

  void _updateTint(Track t) {
    final key = t.coverId.isNotEmpty ? t.coverId : t.cover;
    if (_tintFor == key) return;
    _tintFor = key;
    final p = coverProvider(context, t.cover, t.coverId);
    if (p == null) return;
    dominantColor(p, key).then((c) {
      if (c != null && mounted && _tintFor == key) setState(() => _tint = c);
    });
  }

  @override
  Widget build(BuildContext context) {
    final player = context.read<MusicHandler>();
    return ValueListenableBuilder<Track?>(
      valueListenable: player.current,
      builder: (context, t, _) {
        if (t == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.maybePop(context);
          });
          return const Material(color: C.bg);
        }
        _updateTint(t);
        return GestureDetector(
          onVerticalDragUpdate: (d) =>
              setState(() => _dragY = math.max(0, _dragY + d.delta.dy)),
          onVerticalDragEnd: (d) {
            if (_dragY > 140 || (d.primaryVelocity ?? 0) > 900) {
              Navigator.maybePop(context);
            } else {
              setState(() => _dragY = 0);
            }
          },
          child: AnimatedContainer(
            duration: Duration(milliseconds: _dragY == 0 ? 220 : 0),
            transform: Matrix4.translationValues(0, _dragY, 0),
            child: Material(
              color: C.bg,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _Background(anim: _bg, tint: _tint),
                  ),
                  SafeArea(child: _Body(track: t)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Slow moving colour blobs from the cover colour.
class _Background extends StatelessWidget {
  final Animation<double> anim;
  final Color tint;
  const _Background({required this.anim, required this.tint});
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: tint),
      duration: const Duration(milliseconds: 900),
      builder: (context, c, _) => AnimatedBuilder(
        animation: anim,
        builder: (context, _) {
          final t = anim.value * 2 * math.pi;
          final col = c ?? tint;
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.6 * math.cos(t), -0.7 + 0.25 * math.sin(t)),
                radius: 1.25,
                colors: [
                  col.withValues(alpha: 0.55),
                  col.withValues(alpha: 0.12),
                  C.bg,
                ],
                stops: const [0, 0.55, 1],
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(
                    -0.8 * math.sin(t * 1.3),
                    0.9 + 0.1 * math.cos(t),
                  ),
                  radius: 1.0,
                  colors: [
                    Color.lerp(
                      col,
                      Colors.black,
                      0.35,
                    )!.withValues(alpha: 0.35),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final Track track;
  const _Body({required this.track});

  @override
  Widget build(BuildContext context) {
    final player = context.read<MusicHandler>();
    final app = context.read<AppState>();
    final t = track;
    final size = MediaQuery.sizeOf(context);
    final coverSize = math.min(size.width - 64, size.height * 0.42);
    return Column(
      children: [
        // top bar
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: Row(
            children: [
              NeuIconButton(
                Icons.keyboard_arrow_down_rounded,
                size: 44,
                iconSize: 28,
                tooltip: 'Küçült',
                onTap: () => Navigator.maybePop(context),
              ),
              Expanded(
                child: ValueListenableBuilder<String>(
                  valueListenable: player.contextName,
                  builder: (context, name, _) => Column(
                    children: [
                      Text(
                        'ÇALINIYOR',
                        style: T.faint.copyWith(
                          letterSpacing: 2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (name.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            name,
                            style: T.dim.copyWith(
                              color: C.text,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              NeuIconButton(
                Icons.more_horiz_rounded,
                size: 44,
                tooltip: 'Seçenekler',
                onTap: () => showTrackMenu(context, t, fromPlayer: true),
              ),
            ],
          ),
        ),
        const Spacer(),
        // cover: swipe to change song
        _SwipeCover(track: t, size: coverSize),
        const Spacer(),
        // title + like
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        t.title,
                        key: ValueKey(t.id),
                        style: T.h2.copyWith(fontSize: 22),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: t.artistId.isEmpty
                          ? null
                          : () => ShellNav.push(
                              ArtistScreen(id: t.artistId, name: t.artist),
                            ),
                      child: Text(
                        t.artist.isEmpty ? 'Bilinmeyen sanatçı' : t.artist,
                        style: T.body.copyWith(color: C.textDim),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              ValueListenableBuilder<Set<String>>(
                valueListenable: app.liked,
                builder: (context, liked, _) {
                  final on = liked.contains(t.id);
                  return NeuIconButton(
                    on ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    size: 48,
                    active: on,
                    tooltip: on ? 'Beğenilenlerden çıkar' : 'Beğen',
                    onTap: () => app.toggleLike(t),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _QualityRow(track: t),
        const SizedBox(height: 8),
        const _Seek(),
        const SizedBox(height: 10),
        const _Controls(),
        const SizedBox(height: 18),
        _BottomRow(track: t),
        const SizedBox(height: 14),
      ],
    );
  }
}

class _SwipeCover extends StatefulWidget {
  final Track track;
  final double size;
  const _SwipeCover({required this.track, required this.size});
  @override
  State<_SwipeCover> createState() => _SwipeCoverState();
}

class _SwipeCoverState extends State<_SwipeCover> {
  double _dx = 0;

  @override
  Widget build(BuildContext context) {
    final player = context.read<MusicHandler>();
    final t = widget.track;
    return GestureDetector(
      onHorizontalDragUpdate: (d) => setState(() => _dx += d.delta.dx),
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (_dx < -80 || v < -700) {
          player.skipToNext();
        } else if (_dx > 80 || v > 700) {
          player.skipToPrevious();
        }
        setState(() => _dx = 0);
      },
      onDoubleTap: player.togglePlay,
      child: ValueListenableBuilder<bool>(
        valueListenable: player.playing,
        builder: (context, playing, child) => AnimatedScale(
          scale: playing ? 1 : 0.9,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutBack,
          child: child,
        ),
        child: AnimatedContainer(
          duration: Duration(milliseconds: _dx == 0 ? 250 : 0),
          transform: Matrix4.translationValues(_dx * 0.6, 0, 0)
            ..rotateZ(_dx / 3000),
          transformAlignment: Alignment.center,
          child: NeuBox(
            radius: 28,
            depth: 1.6,
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 420),
                switchInCurve: Curves.easeOut,
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: ScaleTransition(
                    scale: Tween(begin: 0.94, end: 1.0).animate(a),
                    child: child,
                  ),
                ),
                child: Stack(
                  key: ValueKey(t.coverId.isNotEmpty ? t.coverId : t.id),
                  fit: StackFit.expand,
                  children: [
                    CoverImage(
                      cover: t.cover,
                      coverId: t.coverId,
                      radius: 20,
                      width: 900,
                    ),
                    if (t.isVideo)
                      Positioned(
                        left: 10,
                        top: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.movie_rounded,
                                size: 14,
                                color: Colors.white70,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Videodan',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QualityRow extends StatelessWidget {
  final Track track;
  const _QualityRow({required this.track});
  @override
  Widget build(BuildContext context) {
    final q = track.qualityLabel;
    final local = context.select<Downloads, bool>(
      (d) => d.isDownloaded(track.id),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        children: [
          if (track.hiRes)
            const _Pill('HI-RES', accent: true)
          else if (track.lossless)
            const _Pill('LOSSLESS', accent: true),
          if (q.isNotEmpty) _Pill(q),
          if (local)
            const _Pill('İNDİRİLDİ', icon: Icons.arrow_circle_down_rounded),
          const Spacer(),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final bool accent;
  final IconData? icon;
  const _Pill(this.text, {this.accent = false, this.icon});
  @override
  Widget build(BuildContext context) {
    final color = accent ? C.accent : C.textDim;
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _Seek extends StatefulWidget {
  const _Seek();
  @override
  State<_Seek> createState() => _SeekState();
}

class _SeekState extends State<_Seek> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final player = context.read<MusicHandler>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26),
      child: ValueListenableBuilder<Duration>(
        valueListenable: player.duration,
        builder: (context, dur, _) => ValueListenableBuilder<Duration>(
          valueListenable: player.position,
          builder: (context, pos, _) {
            final total = dur.inMilliseconds > 0
                ? dur.inMilliseconds / 1000
                : (player.current.value?.duration ?? 0);
            final p = total > 0
                ? (pos.inMilliseconds / 1000 / total).clamp(0.0, 1.0)
                : 0.0;
            final shown = _drag ?? p;
            return Column(
              children: [
                NeuSeekBar(
                  value: shown,
                  onChanged: total > 0
                      ? (v) => setState(() => _drag = v)
                      : null,
                  onChangeEnd: total > 0
                      ? (v) {
                          setState(() => _drag = null);
                          player.seek(
                            Duration(milliseconds: (v * total * 1000).round()),
                          );
                        }
                      : null,
                ),
                Row(
                  children: [
                    Text(formatDuration(shown * total), style: T.faint),
                    const Spacer(),
                    ValueListenableBuilder<bool>(
                      valueListenable: player.buffering,
                      builder: (context, b, _) => b
                          ? const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: SizedBox(
                                width: 10,
                                height: 10,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    Text(formatDuration(total), style: T.faint),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls();
  @override
  Widget build(BuildContext context) {
    final player = context.read<MusicHandler>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: player.shuffle,
            builder: (context, on, _) => NeuIconButton(
              Icons.shuffle_rounded,
              size: 46,
              iconSize: 20,
              active: on,
              tooltip: on ? 'Karışık: açık' : 'Karışık: kapalı',
              onTap: () => player.setShuffle(!on),
            ),
          ),
          NeuIconButton(
            Icons.skip_previous_rounded,
            size: 58,
            iconSize: 30,
            tooltip: 'Önceki',
            onTap: player.skipToPrevious,
          ),
          ValueListenableBuilder<bool>(
            valueListenable: player.playing,
            builder: (context, playing, _) => NeuButton(
              circle: true,
              width: 80,
              height: 80,
              color: C.accent,
              depth: 1.3,
              tooltip: playing ? 'Duraklat' : 'Çal',
              onTap: player.togglePlay,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (c, a) =>
                    ScaleTransition(scale: a, child: c),
                child: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  key: ValueKey(playing),
                  size: 42,
                  color: Colors.black,
                ),
              ),
            ),
          ),
          NeuIconButton(
            Icons.skip_next_rounded,
            size: 58,
            iconSize: 30,
            tooltip: 'Sonraki',
            onTap: player.skipToNext,
          ),
          ValueListenableBuilder<AudioServiceRepeatMode>(
            valueListenable: player.repeat,
            builder: (context, r, _) => NeuIconButton(
              r == AudioServiceRepeatMode.one
                  ? Icons.repeat_one_rounded
                  : Icons.repeat_rounded,
              size: 46,
              iconSize: 20,
              active: r != AudioServiceRepeatMode.none,
              tooltip: switch (r) {
                AudioServiceRepeatMode.none => 'Tekrar: kapalı',
                AudioServiceRepeatMode.one => 'Tekrar: bu şarkı',
                _ => 'Tekrar: liste',
              },
              onTap: player.cycleRepeat,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomRow extends StatelessWidget {
  final Track track;
  const _BottomRow({required this.track});
  @override
  Widget build(BuildContext context) {
    final player = context.read<MusicHandler>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26),
      child: Row(
        children: [
          ValueListenableBuilder<DateTime?>(
            valueListenable: player.sleepAt,
            builder: (context, at, _) => ValueListenableBuilder<bool>(
              valueListenable: player.sleepEndOfTrack,
              builder: (context, eot, _) {
                final on = at != null || eot;
                return TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: on ? C.accent : C.textDim,
                  ),
                  onPressed: () => showSleepTimer(context),
                  icon: const Icon(Icons.bedtime_outlined, size: 20),
                  label: on
                      ? _SleepLeft(at: at, endOfTrack: eot)
                      : const Text('Uyku'),
                );
              },
            ),
          ),
          const Spacer(),
          Builder(
            builder: (context) {
              final cf = context.select<AppState, int>(
                (s) => s.player.settings.crossfade,
              );
              return cf > 0
                  ? Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Tooltip(
                        message: 'Yumuşak geçiş: $cf sn',
                        child: Row(
                          children: [
                            const Icon(
                              Icons.blur_linear_rounded,
                              size: 16,
                              color: C.textFaint,
                            ),
                            const SizedBox(width: 3),
                            Text('${cf}sn', style: T.faint),
                          ],
                        ),
                      ),
                    )
                  : const SizedBox.shrink();
            },
          ),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: C.textDim),
            onPressed: () => showQueue(context),
            icon: const Icon(Icons.queue_music_rounded, size: 22),
            label: const Text('Sıradakiler'),
          ),
        ],
      ),
    );
  }
}

class _SleepLeft extends StatefulWidget {
  final DateTime? at;
  final bool endOfTrack;
  const _SleepLeft({required this.at, required this.endOfTrack});
  @override
  State<_SleepLeft> createState() => _SleepLeftState();
}

class _SleepLeftState extends State<_SleepLeft> {
  Timer? _t;
  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.endOfTrack && widget.at == null) return const Text('Şarkı sonu');
    final left = widget.at!.difference(DateTime.now());
    return Text(formatDuration(math.max(0, left.inSeconds).toDouble()));
  }
}

void showSleepTimer(BuildContext context) {
  final player = context.read<MusicHandler>();
  const options = [5, 10, 15, 30, 45, 60, 90];
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Uyku zamanlayıcısı', style: T.h3),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Süre dolunca müzik yavaşça kısılır ve durur.',
              style: T.dim,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              for (final m in options)
                ActionChip(
                  label: Text(
                    m < 60
                        ? '$m dk'
                        : '${m ~/ 60} sa${m % 60 > 0 ? ' ${m % 60} dk' : ''}',
                  ),
                  onPressed: () {
                    player.setSleepTimer(Duration(minutes: m));
                    Navigator.pop(ctx);
                  },
                ),
              ActionChip(
                label: const Text('Şarkı bitince'),
                onPressed: () {
                  player.setSleepTimer(null, endOfTrack: true);
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
          if (player.sleepAt.value != null || player.sleepEndOfTrack.value)
            TextButton(
              onPressed: () {
                player.setSleepTimer(null);
                Navigator.pop(ctx);
              },
              child: const Text(
                'Zamanlayıcıyı kapat',
                style: TextStyle(color: C.danger),
              ),
            ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}

void showQueue(BuildContext context) {
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (ctx) => SizedBox(
      height: MediaQuery.sizeOf(ctx).height * 0.8,
      child: const _QueueSheet(),
    ),
  );
}

class _QueueSheet extends StatelessWidget {
  const _QueueSheet();
  @override
  Widget build(BuildContext context) {
    final player = context.read<MusicHandler>();
    return ValueListenableBuilder<List<Track>>(
      valueListenable: player.queueList,
      builder: (context, q, _) => ValueListenableBuilder<int>(
        valueListenable: player.index,
        builder: (context, cur, _) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 12, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Sıradakiler (${q.length})', style: T.h3),
                    ),
                    TextButton(
                      onPressed: q.isEmpty
                          ? null
                          : () async {
                              if (await confirm(
                                context,
                                title: 'Çalma sırası temizlensin mi?',
                                ok: 'Temizle',
                              )) {
                                await player.clearQueue();
                                if (context.mounted) Navigator.pop(context);
                              }
                            },
                      child: const Text(
                        'Temizle',
                        style: TextStyle(color: C.textDim),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.only(bottom: 30),
                  itemCount: q.length,
                  scrollController: ScrollController(
                    initialScrollOffset: math.max(0, (cur - 1) * 64.0),
                  ),
                  onReorderItem: (from, to) {
                    player.moveQueueItem(from, to);
                  },
                  itemBuilder: (context, i) {
                    final t = q[i];
                    final isCur = i == cur;
                    return Dismissible(
                      key: ValueKey('q-${t.id}-$i'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: C.danger.withValues(alpha: 0.25),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        child: const Icon(
                          Icons.delete_outline_rounded,
                          color: C.danger,
                        ),
                      ),
                      onDismissed: (_) => player.removeFromQueue(i),
                      child: SizedBox(
                        height: 64,
                        child: ListTile(
                          contentPadding: const EdgeInsets.only(
                            left: 18,
                            right: 4,
                          ),
                          leading: SizedBox(
                            width: 46,
                            height: 46,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                CoverImage(
                                  cover: t.cover,
                                  coverId: t.coverId,
                                  radius: 6,
                                  width: 140,
                                ),
                                if (isCur)
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Center(
                                      child: ValueListenableBuilder<bool>(
                                        valueListenable: player.playing,
                                        builder: (_, p, _) =>
                                            PlayingBars(animate: p, size: 16),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          title: Text(
                            t.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: T.body.copyWith(
                              color: isCur
                                  ? C.accent
                                  : (i < cur ? C.textFaint : C.text),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            t.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: T.dim,
                          ),
                          onTap: () => player.skipToQueueItem(i),
                          trailing: ReorderableDragStartListener(
                            index: i,
                            child: const Padding(
                              padding: EdgeInsets.all(12),
                              child: Icon(
                                Icons.drag_handle_rounded,
                                color: C.textFaint,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
