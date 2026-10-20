import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../ui/theme.dart';
import '../ui/widgets/common.dart';
import '../ui/widgets/net_image.dart';
import 'player_screen.dart';

/// YouTube-style end screen: countdown to the next episode plus other
/// episodes and recommendations.
class EndScreen extends StatefulWidget {
  final PlayerScreenState state;
  const EndScreen({super.key, required this.state});

  @override
  State<EndScreen> createState() => _EndScreenState();
}

class _EndScreenState extends State<EndScreen>
    with SingleTickerProviderStateMixin {
  late final int _seconds = widget.state.prefs.nextCountdown.clamp(5, 60);
  late final AnimationController _countdown = AnimationController(
    vsync: this,
    duration: Duration(seconds: _seconds),
  );
  bool _cancelled = false;
  MediaItem? _next;

  @override
  void initState() {
    super.initState();
    widget.state.related.addListener(_onRelated);
    _onRelated();
    _countdown.addStatusListener((s) {
      if (s == AnimationStatus.completed && !_cancelled && _next != null) {
        widget.state.playNext();
      }
    });
  }

  void _onRelated() {
    final next = widget.state.related.value?.next;
    if (next != null && _next == null) {
      setState(() => _next = next);
      if (widget.state.prefs.autoPlayNext) _countdown.forward(from: 0);
    } else {
      setState(() {});
    }
  }

  void _cancel() {
    setState(() => _cancelled = true);
    _countdown.stop();
  }

  @override
  void dispose() {
    widget.state.related.removeListener(_onRelated);
    _countdown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rel = widget.state.related.value;
    final next = _next;
    final current = widget.state.item;
    final others = [
      ...?rel?.episodes.where((e) => e.id != current.id && e.id != next?.id),
    ];
    final recommended = rel?.recommended ?? const <MediaItem>[];

    return MouseRegion(
      onHover: (_) {},
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            color: Colors.black.withValues(alpha: 0.72),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(48, 28, 48, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Geri',
                          onPressed: widget.state.close,
                          icon: const Icon(Icons.arrow_back_rounded, size: 30),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${current.displayTitle} bitti',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              color: AppColors.textDim,
                            ),
                          ),
                        ),
                        PillButton(
                          icon: Icons.replay_rounded,
                          label: 'Tekrar izle',
                          height: 40,
                          onPressed: widget.state.replay,
                        ),
                      ],
                    ),
                    const Spacer(),
                    if (next != null) _nextCard(next) else _noNext(),
                    const Spacer(),
                    if (others.isNotEmpty) ...[
                      const Text(
                        'Diğer bölümler',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _strip(others),
                      const SizedBox(height: 18),
                    ],
                    if (recommended.isNotEmpty) ...[
                      const Text(
                        'Önerilenler',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _strip(recommended),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _noNext() {
    return const Center(
      child: Text(
        'Bir sonraki için aşağıdan seçebilirsin',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _nextCard(MediaItem next) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 420,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    NetImage(next.backdrop, width: 780),
                    Container(color: Colors.black26),
                    Center(
                      child: GestureDetector(
                        onTap: widget.state.playNext,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: SizedBox(
                            width: 92,
                            height: 92,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                AnimatedBuilder(
                                  animation: _countdown,
                                  builder: (context, _) =>
                                      CircularProgressIndicator(
                                        value: _cancelled
                                            ? 0
                                            : _countdown.value,
                                        strokeWidth: 4,
                                        color: Colors.white,
                                        backgroundColor: Colors.white24,
                                      ),
                                ),
                                const Icon(Icons.play_arrow_rounded, size: 56),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 32),
          SizedBox(
            width: 420,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _countdown,
                  builder: (context, _) {
                    final left = (_seconds * (1 - _countdown.value)).ceil();
                    return Text(
                      _cancelled ||
                              !_countdown.isAnimating && _countdown.value == 0
                          ? 'SIRADAKİ'
                          : 'SIRADAKİ · $left sn',
                      style: TextStyle(
                        letterSpacing: 3,
                        fontWeight: FontWeight.w800,
                        color: AppColors.accent2,
                        fontSize: 13,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  next.isEpisode
                      ? '${next.episodeCode}${next.title.isNotEmpty ? ' · ${next.title}' : ''}'
                      : next.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                if (next.overview.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    next.overview,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textDim,
                      height: 1.45,
                    ),
                  ),
                ],
                if (next.duration > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    formatDuration(next.duration, long: true),
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    PillButton(
                      primary: true,
                      autofocus: true,
                      icon: Icons.play_arrow_rounded,
                      label: 'Şimdi oynat',
                      onPressed: widget.state.playNext,
                    ),
                    const SizedBox(width: 10),
                    if (!_cancelled && _countdown.isAnimating)
                      PillButton(label: 'İptal', onPressed: _cancel),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _strip(List<MediaItem> items) {
    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) => _MiniCard(
          item: items[i],
          onTap: () {
            _cancel();
            widget.state.switchTo(items[i]);
          },
        ),
      ),
    );
  }
}

class _MiniCard extends StatefulWidget {
  final MediaItem item;
  final VoidCallback onTap;
  const _MiniCard({required this.item, required this.onTap});
  @override
  State<_MiniCard> createState() => _MiniCardState();
}

class _MiniCardState extends State<_MiniCard> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final label = it.isEpisode
        ? '${it.episodeCode}${it.title.isNotEmpty ? ' · ${it.title}' : ''}'
        : it.title;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hover ? 1.05 : 1,
          duration: const Duration(milliseconds: 180),
          child: SizedBox(
            width: 210,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        NetImage(it.backdrop, width: 480),
                        if (it.inProgress)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: ProgressLine(it.progress),
                          ),
                        if (it.userData.played)
                          const Positioned(
                            top: 6,
                            right: 6,
                            child: Icon(
                              Icons.check_circle_rounded,
                              color: AppColors.success,
                              size: 18,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
