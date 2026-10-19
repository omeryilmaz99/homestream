import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../theme.dart';
import 'media_card.dart';

/// Horizontal row of cards with a title and hover arrows (Netflix style).
class MediaRow extends StatefulWidget {
  final String title;
  final List<MediaItem> items;
  final bool wide;
  final double horizontalPadding;
  final void Function(MediaItem item)? onTap;
  const MediaRow({
    super.key,
    required this.title,
    required this.items,
    this.wide = false,
    this.horizontalPadding = 48,
    this.onTap,
  });

  @override
  State<MediaRow> createState() => _MediaRowState();
}

class _MediaRowState extends State<MediaRow> {
  final _ctrl = ScrollController();
  bool _hover = false;
  bool _canLeft = false;
  bool _canRight = true;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_update);
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  void _update() {
    if (!_ctrl.hasClients) return;
    final l = _ctrl.offset > 4;
    final r = _ctrl.offset < _ctrl.position.maxScrollExtent - 4;
    if (l != _canLeft || r != _canRight) {
      setState(() {
        _canLeft = l;
        _canRight = r;
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _page(int dir) {
    if (!_ctrl.hasClients) return;
    final w = _ctrl.position.viewportDimension * 0.85;
    _ctrl.animateTo(
      (_ctrl.offset + dir * w).clamp(0, _ctrl.position.maxScrollExtent),
      duration: const Duration(milliseconds: 550),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardW = widget.wide ? 300.0 : 170.0;
    final cardH = widget.wide ? cardW * 9 / 16 + 52 : cardW * 1.5;
    final pad = widget.horizontalPadding;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(pad, 0, pad, 12),
              child: Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            SizedBox(
              // extra room so hover scale/shadow isn't clipped
              height: cardH + 24,
              child: Stack(
                children: [
                  Listener(
                    // Mouse wheel over a row scrolls it horizontally when shift is held.
                    onPointerSignal: (e) {
                      if (e is PointerScrollEvent &&
                          e.scrollDelta.dx.abs() > e.scrollDelta.dy.abs() &&
                          _ctrl.hasClients) {
                        _ctrl.jumpTo(
                          (_ctrl.offset + e.scrollDelta.dx).clamp(
                            0,
                            _ctrl.position.maxScrollExtent,
                          ),
                        );
                      }
                    },
                    child: ListView.separated(
                      controller: _ctrl,
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      padding: EdgeInsets.fromLTRB(pad, 12, pad, 12),
                      itemCount: widget.items.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 14),
                      itemBuilder: (context, i) {
                        final it = widget.items[i];
                        return widget.wide
                            ? WideCard(
                                item: it,
                                width: cardW,
                                onTap: widget.onTap == null
                                    ? null
                                    : () => widget.onTap!(it),
                              )
                            : PosterCard(item: it, width: cardW);
                      },
                    ),
                  ),
                  _Arrow(
                    left: true,
                    visible: _hover && _canLeft,
                    width: pad,
                    onTap: () => _page(-1),
                  ),
                  _Arrow(
                    left: false,
                    visible: _hover && _canRight,
                    width: pad,
                    onTap: () => _page(1),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  final bool left;
  final bool visible;
  final double width;
  final VoidCallback onTap;
  const _Arrow({
    required this.left,
    required this.visible,
    required this.width,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left ? 0 : null,
      right: left ? null : 0,
      top: 12,
      bottom: 12,
      width: width.clamp(40, 64),
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: left ? Alignment.centerLeft : Alignment.centerRight,
                    end: left ? Alignment.centerRight : Alignment.centerLeft,
                    colors: [
                      AppColors.bg.withValues(alpha: 0.9),
                      AppColors.bg.withValues(alpha: 0),
                    ],
                  ),
                ),
                child: Icon(
                  left
                      ? Icons.chevron_left_rounded
                      : Icons.chevron_right_rounded,
                  size: 44,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
