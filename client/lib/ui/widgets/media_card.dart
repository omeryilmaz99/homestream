import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../screens/detail_dialog.dart';
import '../layout.dart';
import '../theme.dart';
import 'common.dart';
import 'net_image.dart';

/// Shared hover/focus/click behavior with a smooth scale animation.
class HoverCard extends StatefulWidget {
  final Widget Function(BuildContext context, bool active) builder;
  final VoidCallback onTap;
  final VoidCallback? onSecondaryTap;
  final double scale;
  final bool autofocus;
  const HoverCard({
    super.key,
    required this.builder,
    required this.onTap,
    this.onSecondaryTap,
    this.scale = 1.06,
    this.autofocus = false,
  });

  @override
  State<HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<HoverCard> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final active = _hover || _focus;
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      mouseCursor: SystemMouseCursors.click,
      onShowHoverHighlight: (v) => setState(() => _hover = v),
      onFocusChange: (v) {
        setState(() => _focus = v);
        if (v) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 250),
          );
        }
      },
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => widget.onTap(),
        ),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTap: widget.onSecondaryTap,
        child: AnimatedScale(
          scale: active ? widget.scale : 1,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ]
                  : const [],
              border: Border.all(
                color: _focus ? Colors.white : Colors.transparent,
                width: 2.5,
                strokeAlign: BorderSide.strokeAlignOutside,
              ),
            ),
            child: widget.builder(context, active),
          ),
        ),
      ),
    );
  }
}

/// 2:3 poster card for movies and series.
class PosterCard extends StatelessWidget {
  final MediaItem item;
  final double width;
  final bool autofocus;
  const PosterCard({
    super.key,
    required this.item,
    this.width = 170,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final imgW = width > 200 ? 480 : 320;
    return SizedBox(
      width: width,
      child: HoverCard(
        autofocus: autofocus,
        onTap: () => openDetail(context, item),
        builder: (context, active) => ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 2 / 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                NetImage(item.poster, width: imgW),
                if (item.posterGenerated) _GeneratedPosterOverlay(item: item),
                // Hover info
                AnimatedOpacity(
                  opacity: active && !item.posterGenerated ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: _HoverInfo(item: item),
                ),
                if (item.userData.played && !item.isSeries)
                  const Positioned(top: 8, right: 8, child: _WatchedBadge()),
                if (item.isSeries && item.unwatchedCount > 0)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _CountBadge(item.unwatchedCount),
                  ),
                if (item.inProgress)
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: ProgressLine(item.progress),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GeneratedPosterOverlay extends StatelessWidget {
  final MediaItem item;
  const _GeneratedPosterOverlay({required this.item});
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0x66000000), Color(0xEE000000)],
          stops: [0.25, 0.55, 1],
        ),
      ),
      child: Padding(
        padding: isCompact(context)
            ? const EdgeInsets.fromLTRB(8, 8, 8, 12)
            : const EdgeInsets.fromLTRB(12, 12, 12, 18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: isCompact(context) ? 14 : 17,
                fontWeight: FontWeight.w800,
                height: 1.15,
                shadows: const [Shadow(blurRadius: 8, color: Colors.black)],
              ),
            ),
            if (item.year > 0 || item.isSeries) ...[
              const SizedBox(height: 4),
              Text(
                item.isSeries
                    ? '${item.seasonCount > 1 ? '${item.seasonCount} sezon' : '${item.episodeCount} bölüm'}${item.year > 0 ? ' · ${item.year}' : ''}'
                    : '${item.year}',
                style: const TextStyle(fontSize: 12, color: AppColors.textDim),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HoverInfo extends StatelessWidget {
  final MediaItem item;
  const _HoverInfo({required this.item});
  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (item.year > 0) '${item.year}',
      if (item.isSeries) '${item.episodeCount} bölüm',
      if (!item.isSeries && item.duration > 0)
        formatDuration(item.duration, long: true),
    ].join(' · ');
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0xDD000000)],
          stops: [0.45, 1],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            if (meta.isNotEmpty)
              Text(
                meta,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textDim,
                ),
              ),
            if (item.rating > 0)
              Row(
                children: [
                  const Icon(
                    Icons.star_rounded,
                    size: 14,
                    color: Color(0xFFFBBF24),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    item.rating.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textDim,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _WatchedBadge extends StatelessWidget {
  const _WatchedBadge();
  @override
  Widget build(BuildContext context) => Container(
    width: 24,
    height: 24,
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      color: AppColors.success,
      boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 6)],
    ),
    child: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
  );
}

class _CountBadge extends StatelessWidget {
  final int count;
  const _CountBadge(this.count);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      gradient: AppColors.brandGradient,
      borderRadius: BorderRadius.circular(10),
      boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6)],
    ),
    child: Text(
      '$count',
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
    ),
  );
}

/// 16:9 card used for "Continue watching", episodes and next-up.
class WideCard extends StatelessWidget {
  final MediaItem item;
  final double width;
  final VoidCallback? onTap;
  final bool showProgress;
  final bool autofocus;
  const WideCard({
    super.key,
    required this.item,
    this.width = 300,
    this.onTap,
    this.showProgress = true,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final title = item.isEpisode
        ? (item.seriesTitle.isNotEmpty ? item.seriesTitle : item.title)
        : item.title;
    final subtitle = item.isEpisode
        ? '${item.episodeCode}${item.title.isNotEmpty && item.title != item.seriesTitle ? ' · ${item.title}' : ''}'
        : (item.inProgress
              ? formatRemaining(item.userData.position, item.duration)
              : [
                  if (item.year > 0) '${item.year}',
                  if (item.duration > 0)
                    formatDuration(item.duration, long: true),
                ].join(' · '));
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HoverCard(
            autofocus: autofocus,
            scale: 1.04,
            onTap: onTap ?? () => openDetail(context, item),
            builder: (context, active) => ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    NetImage(item.backdrop, width: width > 340 ? 780 : 480),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x00000000), Color(0x99000000)],
                          stops: [0.5, 1],
                        ),
                      ),
                    ),
                    Center(
                      child: AnimatedOpacity(
                        opacity: active ? 1 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: AnimatedScale(
                          scale: active ? 1 : 0.7,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutBack,
                          child: Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withValues(alpha: 0.45),
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              size: 34,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (item.userData.played)
                      const Positioned(
                        top: 8,
                        right: 8,
                        child: _WatchedBadge(),
                      ),
                    if (item.duration > 0 && !item.inProgress)
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            formatDuration(item.duration),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    if (showProgress && item.inProgress)
                      Positioned(
                        left: 10,
                        right: 10,
                        bottom: 10,
                        child: ProgressLine(item.progress),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          if (subtitle.isNotEmpty)
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12.5,
              ),
            ),
        ],
      ),
    );
  }
}
