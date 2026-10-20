import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../core/format.dart';
import '../core/platform.dart';
import '../ui/theme.dart';
import '../ui/tv_focus.dart';
import 'player_screen.dart';

/// The overlay with title, seek bar and buttons. Kept deliberately light:
/// only the time label and seek bar listen to the position stream.
class PlayerControls extends StatefulWidget {
  final PlayerScreenState state;
  const PlayerControls({super.key, required this.state});
  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls> {
  bool _render = true;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.state.controlsVisible,
      builder: (context, visible, _) {
        if (visible) _render = true;
        return IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 250),
            onEnd: () {
              if (!widget.state.controlsVisible.value && mounted) {
                setState(() => _render = false);
              }
            },
            // Once faded out the subtree is removed so nothing rebuilds over the video.
            child: _render
                ? _ControlsBody(state: widget.state)
                : const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}

class _ControlsBody extends StatelessWidget {
  final PlayerScreenState state;
  const _ControlsBody({required this.state});

  @override
  Widget build(BuildContext context) {
    final player = state.player;
    final item = state.item;
    return Stack(
      fit: StackFit.expand,
      children: [
        // gradients
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xAA000000),
                  Color(0x00000000),
                  Color(0x00000000),
                  Color(0xCC000000),
                ],
                stops: [0, 0.18, 0.62, 1],
              ),
            ),
          ),
        ),
        // top bar
        Positioned(
          left: 24,
          right: 24,
          top: 18,
          child: Row(
            children: [
              _IconBtn(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Geri (Esc)',
                onTap: state.close,
                size: 30,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.isEpisode && item.seriesTitle.isNotEmpty
                          ? item.seriesTitle
                          : item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (item.isEpisode)
                      Text(
                        '${item.episodeCode}${item.title.isNotEmpty ? ' · ${item.title}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textDim,
                          fontSize: 14,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // center play/pause indicator (click target is the video itself)
        Center(
          child: StreamBuilder<bool>(
            stream: player.stream.playing,
            initialData: player.state.playing,
            builder: (context, snap) {
              final playing = snap.data ?? false;
              return AnimatedOpacity(
                opacity: playing ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: playing,
                  child: GestureDetector(
                    onTap: player.play,
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.45),
                        border: Border.all(color: Colors.white70, width: 2),
                      ),
                      child: const Icon(Icons.play_arrow_rounded, size: 54),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // bottom area
        Positioned(
          left: 24,
          right: 24,
          bottom: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SeekBar(state: state),
              const SizedBox(height: 6),
              Row(
                children: [
                  StreamBuilder<bool>(
                    stream: player.stream.playing,
                    initialData: player.state.playing,
                    builder: (context, snap) => _IconBtn(
                      icon: (snap.data ?? false)
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      tooltip: (snap.data ?? false)
                          ? 'Duraklat (Boşluk)'
                          : 'Oynat (Boşluk)',
                      onTap: player.playOrPause,
                      size: 38,
                      focusNode: state.playFocus,
                    ),
                  ),
                  _IconBtn(
                    icon: Icons.replay_10_rounded,
                    tooltip: 'Geri sar (←)',
                    onTap: () => state.seekRelative(-state.prefs.seekStep),
                  ),
                  _IconBtn(
                    icon: Icons.forward_10_rounded,
                    tooltip: 'İleri sar (→)',
                    onTap: () => state.seekRelative(state.prefs.seekStep),
                  ),
                  if (!AppPlatform.isTv) _VolumeControl(player: player),
                  const SizedBox(width: 10),
                  _TimeLabel(player: player),
                  const Spacer(),
                  ValueListenableBuilder(
                    valueListenable: state.related,
                    builder: (context, rel, _) => rel?.next == null
                        ? const SizedBox.shrink()
                        : _IconBtn(
                            icon: Icons.skip_next_rounded,
                            tooltip: 'Sonraki bölüm (N)',
                            onTap: state.playNext,
                          ),
                  ),
                  _IconBtn(
                    icon: Icons.subtitles_rounded,
                    tooltip: 'Altyazı ve ses',
                    onTap: () => state.menuOpen.value = !state.menuOpen.value,
                  ),
                  if (AppPlatform.isDesktop)
                    ValueListenableBuilder<bool>(
                      valueListenable: state.fullscreen,
                      builder: (context, fs, _) => _IconBtn(
                        icon: fs
                            ? Icons.fullscreen_exit_rounded
                            : Icons.fullscreen_rounded,
                        tooltip: 'Tam ekran (F)',
                        onTap: state.toggleFullscreen,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        // track / settings menu (Positioned must be a direct child of the Stack)
        Positioned(
          right: 24,
          bottom: 96,
          child: ValueListenableBuilder<bool>(
            valueListenable: state.menuOpen,
            builder: (context, open, _) => AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0.05, 0),
                    end: Offset.zero,
                  ).animate(a),
                  child: c,
                ),
              ),
              child: open
                  ? TrackMenu(key: const ValueKey('menu'), state: state)
                  : const SizedBox.shrink(key: ValueKey('none')),
            ),
          ),
        ),
      ],
    );
  }
}

class _IconBtn extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double size;
  final FocusNode? focusNode;
  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size = 30,
    this.focusNode,
  });
  @override
  State<_IconBtn> createState() => _IconBtnState();
}

class _IconBtnState extends State<_IconBtn> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final btn = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Focusable(
        focusNode: widget.focusNode,
        onTap: widget.onTap,
        builder: (context, focused) => AnimatedScale(
          scale: _hover || focused ? 1.15 : 1,
          duration: const Duration(milliseconds: 140),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: focused ? Colors.white : Colors.transparent,
            ),
            child: Icon(
              widget.icon,
              size: widget.size,
              color: focused ? Colors.black : Colors.white,
            ),
          ),
        ),
      ),
    );
    // tooltips are hover hints; a remote has no hover
    return AppPlatform.isTv
        ? btn
        : Tooltip(message: widget.tooltip, child: btn);
  }
}

class _TimeLabel extends StatelessWidget {
  final Player player;
  const _TimeLabel({required this.player});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.stream.position,
      initialData: player.state.position,
      builder: (context, snap) {
        final pos = (snap.data ?? Duration.zero).inMilliseconds / 1000;
        final dur = player.state.duration.inMilliseconds / 1000;
        return Text(
          '${formatDuration(pos)} / ${formatDuration(dur)}',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        );
      },
    );
  }
}

class _VolumeControl extends StatefulWidget {
  final Player player;
  const _VolumeControl({required this.player});
  @override
  State<_VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends State<_VolumeControl> {
  bool _hover = false;
  double _beforeMute = 100;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: StreamBuilder<double>(
        stream: widget.player.stream.volume,
        initialData: widget.player.state.volume,
        builder: (context, snap) {
          final v = snap.data ?? 100;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _IconBtn(
                icon: v == 0
                    ? Icons.volume_off_rounded
                    : (v < 50
                          ? Icons.volume_down_rounded
                          : Icons.volume_up_rounded),
                tooltip: 'Ses (M)',
                onTap: () {
                  if (v > 0) {
                    _beforeMute = v;
                    widget.player.setVolume(0);
                  } else {
                    widget.player.setVolume(_beforeMute);
                  }
                },
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: _hover ? 110 : 0,
                child: ClipRect(
                  child: _hover
                      ? SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6,
                            ),
                          ),
                          child: Slider(
                            value: v.clamp(0, 150),
                            max: 150,
                            onChanged: widget.player.setVolume,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Seek bar with buffered range, hover time preview and drag support.
class SeekBar extends StatefulWidget {
  final PlayerScreenState state;
  const SeekBar({super.key, required this.state});
  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _dragValue; // 0..1
  double? _hoverX;
  bool _hover = false;

  Player get player => widget.state.player;

  double _fraction(Offset local, double width) =>
      (local.dx / width).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() {
            _hover = false;
            _hoverX = null;
          }),
          onHover: (e) => setState(() => _hoverX = e.localPosition.dx),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (d) {
              setState(() => _dragValue = _fraction(d.localPosition, width));
              widget.state.onUserActivity();
            },
            onHorizontalDragUpdate: (d) {
              setState(() {
                _dragValue = _fraction(d.localPosition, width);
                _hoverX = d.localPosition.dx;
              });
              widget.state.onUserActivity();
            },
            onHorizontalDragEnd: (_) {
              final v = _dragValue;
              setState(() => _dragValue = null);
              if (v != null) player.seek(player.state.duration * v);
            },
            onTapUp: (d) {
              final v = _fraction(d.localPosition, width);
              player.seek(player.state.duration * v);
              widget.state.onUserActivity();
            },
            child: SizedBox(
              height: 34,
              child: StreamBuilder<Duration>(
                stream: player.stream.position,
                initialData: player.state.position,
                builder: (context, snap) {
                  final dur = player.state.duration.inMilliseconds;
                  final pos = (snap.data ?? Duration.zero).inMilliseconds;
                  final buf = player.state.buffer.inMilliseconds;
                  final played = _dragValue ?? (dur > 0 ? pos / dur : 0.0);
                  final buffered = dur > 0 ? (buf / dur).clamp(0.0, 1.0) : 0.0;
                  final active = _hover || _dragValue != null;
                  final trackH = active ? 6.0 : 4.0;
                  final previewX = _hoverX;
                  return Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.centerLeft,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        height: trackH,
                        decoration: BoxDecoration(
                          color: const Color(0x40FFFFFF),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: buffered,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          height: trackH,
                          decoration: BoxDecoration(
                            color: const Color(0x66FFFFFF),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: played.clamp(0.0, 1.0),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          height: trackH,
                          decoration: BoxDecoration(
                            gradient: AppColors.brandGradient,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      Positioned(
                        left: (played.clamp(0.0, 1.0) * width) - 8,
                        child: AnimatedScale(
                          scale: active ? 1 : 0.6,
                          duration: const Duration(milliseconds: 120),
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(color: Colors.black54, blurRadius: 6),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (active && previewX != null && dur > 0)
                        Positioned(
                          left: (previewX - 34).clamp(0, width - 68),
                          bottom: 26,
                          child: Container(
                            width: 68,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              formatDuration(
                                (previewX / width).clamp(0.0, 1.0) * dur / 1000,
                              ),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Subtitle / audio / speed panel.
class TrackMenu extends StatefulWidget {
  final PlayerScreenState state;
  const TrackMenu({super.key, required this.state});
  @override
  State<TrackMenu> createState() => _TrackMenuState();
}

class _TrackMenuState extends State<TrackMenu> {
  int _tab = 0;
  StreamSubscription? _sub;
  final _firstTab = FocusNode(debugLabel: 'menu-tab');

  @override
  void initState() {
    super.initState();
    if (AppPlatform.isTv) {
      // with a remote, move into the menu as soon as it opens
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _firstTab.requestFocus();
      });
    }
    _sub = widget.state.player.stream.track.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _firstTab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final p = s.player;
    final tracks = p.state.tracks;
    final cur = p.state.track;
    final subs = tracks.subtitle
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();
    final audios = tracks.audio
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();

    Widget option(String label, bool selected, VoidCallback onTap) => Focusable(
      onTap: () {
        onTap();
        setState(() {});
      },
      builder: (context, focused) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: focused ? const Color(0x26FFFFFF) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: focused ? Colors.white : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: selected
                  ? Icon(Icons.check_rounded, size: 18, color: AppColors.accent)
                  : null,
            ),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected || focused ? Colors.white : AppColors.textDim,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    Widget body;
    switch (_tab) {
      case 0:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            option(
              'Kapalı',
              cur.subtitle.id == 'no',
              () => p.setSubtitleTrack(SubtitleTrack.no()),
            ),
            ...subs.map(
              (t) => option(
                trackLabel(t),
                cur.subtitle.id == t.id,
                () => p.setSubtitleTrack(t),
              ),
            ),
            const Divider(color: AppColors.border, height: 18),
            Row(
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 12),
                  child: Text(
                    'Boyut',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: s.prefs.subtitleScale.toDouble().clamp(50, 200),
                    min: 50,
                    max: 200,
                    divisions: 15,
                    label: '${s.prefs.subtitleScale}%',
                    onChanged: (v) {
                      s.setSubScale(v.round());
                      setState(() {});
                    },
                  ),
                ),
              ],
            ),
            Row(
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 12),
                  child: Text(
                    'Gecikme',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Altyazıyı erkene al (Z)',
                  icon: const Icon(Icons.remove_rounded),
                  onPressed: () => s
                      .setSubDelay(s.subDelay - 0.1)
                      .then((_) => setState(() {})),
                ),
                Text(
                  '${s.subDelay.toStringAsFixed(1)} sn',
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                IconButton(
                  tooltip: 'Altyazıyı geciktir (X)',
                  icon: const Icon(Icons.add_rounded),
                  onPressed: () => s
                      .setSubDelay(s.subDelay + 0.1)
                      .then((_) => setState(() {})),
                ),
              ],
            ),
            if (!AppPlatform.isTv)
              TextButton.icon(
                onPressed: s.loadSubtitleFile,
                icon: const Icon(Icons.file_open_rounded, size: 18),
                label: const Text('Bilgisayardan altyazı yükle'),
              ),
          ],
        );
      case 1:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (audios.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Ses parçası bulunamadı',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ),
            ...audios.map((t) {
              final ch = t.channelscount ?? t.audiochannels;
              final extra = [
                if ((t.codec ?? '').isNotEmpty) t.codec!.toUpperCase(),
                if (ch != null && ch > 0)
                  ch >= 6
                      ? (ch == 8 ? '7.1' : '5.1')
                      : (ch == 2 ? 'Stereo' : '$ch kanal'),
              ].join(' · ');
              return option(
                '${trackLabel(t)}${extra.isNotEmpty ? '  ($extra)' : ''}',
                cur.audio.id == t.id,
                () => p.setAudioTrack(t),
              );
            }),
          ],
        );
      default:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final r in [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0])
              option(
                r == 1.0 ? 'Normal' : '${r}x',
                (p.state.rate - r).abs() < 0.01,
                () => p.setRate(r),
              ),
          ],
        );
    }

    return MouseRegion(
      onHover: (_) => s.onUserActivity(),
      child: Container(
        width: 340,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.6,
        ),
        decoration: BoxDecoration(
          color: const Color(0xEE15151D),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 30)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  for (final (i, label) in [
                    (0, 'Altyazı'),
                    (1, 'Ses'),
                    (2, 'Hız'),
                  ])
                    Expanded(
                      child: Focusable(
                        focusNode: i == 0 ? _firstTab : null,
                        onTap: () => setState(() => _tab = i),
                        builder: (context, focused) => AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            color: _tab == i
                                ? AppColors.surface3
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: focused
                                  ? Colors.white
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            label,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _tab == i
                                  ? Colors.white
                                  : AppColors.textMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                child: body,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Next episode" pill shown during the last seconds (credits) of an episode.
class NextEpisodePill extends StatelessWidget {
  final PlayerScreenState state;
  const NextEpisodePill({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: state.related,
      builder: (context, rel, _) {
        final next = rel?.next;
        if (next == null) return const SizedBox.shrink();
        return StreamBuilder<Duration>(
          stream: state.player.stream.position,
          builder: (context, snap) {
            final dur = state.player.state.duration.inSeconds;
            final pos = (snap.data ?? Duration.zero).inSeconds;
            final show =
                dur > 300 &&
                dur - pos <= 40 &&
                dur - pos > 0 &&
                !state.ended.value;
            return Positioned(
              right: 32,
              bottom: 110,
              child: IgnorePointer(
                ignoring: !show,
                child: AnimatedSlide(
                  offset: show ? Offset.zero : const Offset(0.3, 0),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    opacity: show ? 1 : 0,
                    duration: const Duration(milliseconds: 300),
                    child: PillButton(
                      primary: true,
                      icon: Icons.skip_next_rounded,
                      label: 'Sonraki Bölüm · ${next.episodeCode}',
                      onPressed: state.playNext,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
