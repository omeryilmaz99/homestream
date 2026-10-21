import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/platform.dart';
import '../screens/detail_dialog.dart';
import '../screens/play_launcher.dart';
import '../layout.dart';
import '../theme.dart';
import 'common.dart';
import 'net_image.dart';

/// Large rotating featured banner at the top of the home page.
class HeroBanner extends StatefulWidget {
  final List<MediaItem> items;
  const HeroBanner({super.key, required this.items});

  @override
  State<HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<HeroBanner>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  Timer? _timer;
  bool _focused = false;
  // the slow "Ken Burns" zoom is skipped on TV boxes (weak GPUs)
  late final AnimationController _zoom = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
    value: AppPlatform.isTv ? 0 : null,
  );

  @override
  void initState() {
    super.initState();
    if (!AppPlatform.isTv) _zoom.forward();
    _restartTimer();
  }

  void _restartTimer() {
    _timer?.cancel();
    // don't rotate away from the buttons while they have focus
    if (widget.items.length < 2 || _focused) return;
    _timer = Timer.periodic(const Duration(seconds: 9), (_) => _go(_index + 1));
  }

  void _go(int i) {
    if (!mounted || widget.items.isEmpty) return;
    setState(() => _index = i % widget.items.length);
    if (!AppPlatform.isTv) _zoom.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant HeroBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_index >= widget.items.length) _index = 0;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox(height: 90);
    final size = MediaQuery.sizeOf(context);
    final compact = isCompact(context);
    final portrait = isPortraitPhone(context);
    final height = portrait
        ? (size.height * 0.62).clamp(380.0, 560.0)
        : compact
        ? size.height * 0.9
        : (size.width * 0.5).clamp(
            380.0,
            (size.height * 0.78).clamp(380.0, double.infinity),
          );
    final item = widget.items[_index];
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (f) {
        _focused = f;
        _restartTimer();
      },
      child: SizedBox(
        height: height,
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 900),
                layoutBuilder: (current, previous) => Stack(
                  fit: StackFit.expand,
                  children: [...previous, ?current],
                ),
                child: AnimatedBuilder(
                  key: ValueKey(item.id),
                  animation: _zoom,
                  builder: (context, child) => Transform.scale(
                    scale: 1.0 + 0.06 * Curves.easeOut.transform(_zoom.value),
                    child: child,
                  ),
                  child: NetImage(
                    // phones in portrait show the poster, it fits the shape
                    portrait && item.poster.isNotEmpty
                        ? item.poster
                        : item.backdrop,
                    width: AppPlatform.isTv || compact ? 1280 : 1920,
                    alignment: portrait
                        ? Alignment.center
                        : Alignment.topCenter,
                  ),
                ),
              ),
              // readability gradients
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Color(0xEE0A0A0F),
                      Color(0x660A0A0F),
                      Color(0x000A0A0F),
                    ],
                    stops: [0, 0.45, 0.8],
                  ),
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x880A0A0F),
                      Color(0x000A0A0F),
                      Color(0x000A0A0F),
                      AppColors.bg,
                    ],
                    stops: [0, 0.2, 0.62, 1],
                  ),
                ),
              ),
              Positioned(
                left: compact ? 16 : 48,
                right: compact ? 16 : null,
                bottom: compact ? 34 : height * 0.16,
                width: compact ? null : (size.width * 0.45).clamp(320, 640),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 600),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position:
                          Tween(
                            begin: const Offset(0, 0.08),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: anim,
                              curve: Curves.easeOutCubic,
                            ),
                          ),
                      child: child,
                    ),
                  ),
                  child: _HeroInfo(key: ValueKey(item.id), item: item),
                ),
              ),
              if (widget.items.length > 1)
                Positioned(
                  right: compact ? null : 48,
                  left: compact ? 0 : null,
                  bottom: compact ? 12 : height * 0.16,
                  width: compact ? size.width : null,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(widget.items.length, (i) {
                      final sel = i == _index;
                      return GestureDetector(
                        onTap: () {
                          _go(i);
                          _restartTimer();
                        },
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: sel ? 26 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: sel
                                  ? Colors.white
                                  : const Color(0x66FFFFFF),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroInfo extends StatelessWidget {
  final MediaItem item;
  const _HeroInfo({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final compact = isCompact(context);
    final meta = <Widget>[
      if (item.rating > 0)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 18),
            const SizedBox(width: 3),
            Text(
              item.rating.toStringAsFixed(1),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      if (item.year > 0)
        Text('${item.year}', style: const TextStyle(color: AppColors.textDim)),
      if (item.isSeries)
        Text(
          item.seasonCount > 1
              ? '${item.seasonCount} Sezon'
              : '${item.episodeCount} Bölüm',
          style: const TextStyle(color: AppColors.textDim),
        ),
      if (!item.isSeries && item.duration > 0)
        Text(
          formatDuration(item.duration, long: true),
          style: const TextStyle(color: AppColors.textDim),
        ),
      ...item.genres.take(2).map((g) => Tag(g)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          item.isSeries ? 'DİZİ' : 'FİLM',
          style: TextStyle(
            letterSpacing: 4,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: AppColors.accent2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: compact ? 34 : 52,
            height: 1.02,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.5,
            shadows: const [Shadow(blurRadius: 30, color: Colors.black54)],
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 14,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: meta,
        ),
        if (item.overview.isNotEmpty && !compact) ...[
          const SizedBox(height: 14),
          Text(
            item.overview,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15.5,
              height: 1.5,
              color: Color(0xFFDADAE2),
            ),
          ),
        ],
        const SizedBox(height: 22),
        Row(
          children: [
            PillButton(
              primary: true,
              autofocus: AppPlatform.isTv,
              icon: Icons.play_arrow_rounded,
              label: item.inProgress ? 'Devam Et' : 'Oynat',
              onPressed: () => quickPlay(context, item),
            ),
            const SizedBox(width: 12),
            PillButton(
              icon: Icons.info_outline_rounded,
              label: 'Detaylar',
              onPressed: () => openDetail(context, item),
            ),
          ],
        ),
      ],
    );
  }
}
