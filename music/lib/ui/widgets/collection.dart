import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../audio/handler.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../neu.dart';
import '../theme.dart';
import 'common.dart';
import 'track_tile.dart';

/// Shared layout of album / playlist / liked / folder pages: big cover,
/// title, actions, then the song list. The title moves into a top bar
/// while scrolling.
class CollectionView extends StatefulWidget {
  final Widget cover;
  final String title;
  final String? kicker; // "ALBÜM", "ÇALMA LİSTESİ"
  final Widget? subtitle;
  final List<Track> tracks;
  final List<Track>? playable; // header buttons play these (default: tracks)
  final String contextName;
  final bool numbered;
  final List<Widget> actions; // left of the play button
  final List<Widget> topActions; // top bar (menu)
  final Playlist? playlist;
  final VoidCallback? onChanged;
  final List<Widget> slivers; // below the songs
  final Widget? empty;
  final bool roundCover;
  final List<Widget> headerExtra; // e.g. sub folders list
  const CollectionView({
    super.key,
    required this.cover,
    required this.title,
    this.kicker,
    this.subtitle,
    required this.tracks,
    this.playable,
    required this.contextName,
    this.numbered = false,
    this.actions = const [],
    this.topActions = const [],
    this.playlist,
    this.onChanged,
    this.slivers = const [],
    this.empty,
    this.roundCover = false,
    this.headerExtra = const [],
  });

  @override
  State<CollectionView> createState() => _CollectionViewState();
}

class _CollectionViewState extends State<CollectionView> {
  final _scroll = ScrollController();
  final _bar = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      _bar.value = ((_scroll.offset - 160) / 80).clamp(0.0, 1.0);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _bar.dispose();
    super.dispose();
  }

  bool _multiDisc() {
    final discs = widget.tracks.map((t) => t.discNo).toSet();
    return widget.numbered && discs.length > 1;
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final tracks = widget.tracks;
    final all = widget.playable ?? tracks;
    final total = all.fold<double>(0, (a, t) => a + t.duration);
    final multiDisc = _multiDisc();
    final items = <Widget>[];
    var lastDisc = -1;
    for (var i = 0; i < tracks.length; i++) {
      final t = tracks[i];
      if (multiDisc && t.discNo != lastDisc) {
        lastDisc = t.discNo;
        items.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Row(
              children: [
                const Icon(Icons.album_rounded, size: 18, color: C.textDim),
                const SizedBox(width: 8),
                Text(
                  'Disk ${t.discNo > 0 ? t.discNo : 1}',
                  style: T.dim.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        );
      }
      items.add(
        TrackTile(
          track: t,
          number: widget.numbered ? t.trackNo : null,
          playlist: widget.playlist,
          onRemoved: widget.onChanged,
          onTap: () => playList(context, tracks, index: i, name: widget.title),
        ),
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    final header = widget.roundCover
        ? _roundHeader(context, top, all, total)
        : _wideHeader(context, top, width, all, total);

    return Stack(
      children: [
        CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(child: header),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: _PlayButton(all: all, name: widget.title),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _PillButton(
                        icon: Icons.shuffle_rounded,
                        label: 'Karıştır',
                        onTap: all.isEmpty
                            ? null
                            : () => playList(
                                context,
                                all,
                                index: -1,
                                shuffle: true,
                                name: widget.title,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.actions.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
                  child: IconTheme.merge(
                    data: const IconThemeData(size: 24),
                    child: Row(children: widget.actions),
                  ),
                ),
              )
            else
              const SliverToBoxAdapter(child: SizedBox(height: 10)),
            ...widget.headerExtra.map((w) => SliverToBoxAdapter(child: w)),
            if (tracks.isEmpty && widget.empty != null)
              SliverToBoxAdapter(child: widget.empty!)
            else
              SliverList.builder(
                itemCount: items.length,
                itemBuilder: (context, i) => items[i],
              ),
            ...widget.slivers,
            const SliverToBoxAdapter(child: SizedBox(height: 140)),
          ],
        ),
        // top bar
        ValueListenableBuilder<double>(
          valueListenable: _bar,
          builder: (context, v, _) => Container(
            height: top + 56,
            padding: EdgeInsets.only(top: top),
            decoration: BoxDecoration(
              color: C.bg.withValues(alpha: v),
              border: v > 0.9
                  ? const Border(bottom: BorderSide(color: C.divider))
                  : null,
            ),
            child: Row(
              children: [
                const SizedBox(width: 8),
                if (Navigator.of(context).canPop()) ...[
                  _BarButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    tooltip: 'Geri',
                    solid: v < 0.5,
                    onTap: () => Navigator.maybePop(context),
                  ),
                  const SizedBox(width: 10),
                ] else
                  const SizedBox(width: 12),
                Expanded(
                  child: Opacity(
                    opacity: v,
                    child: Text(
                      widget.title,
                      style: T.h3,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                ...widget.topActions,
                const SizedBox(width: 6),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _info(List<Track> all, double total) =>
      all.isEmpty ? '' : '${songCount(all.length)} • ${formatTotal(total)}';

  /// Full-width picture fading into the page, title on top of it.
  Widget _wideHeader(
    BuildContext context,
    double top,
    double width,
    List<Track> all,
    double total,
  ) {
    final h = (math.min(width * 0.82, 420.0) + top * 0.5).roundToDouble();
    final side = math.max(width, h) + 48;
    return SizedBox(
      height: h,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // oversized so the cover's own rounded corners stay outside
          ClipRect(
            child: OverflowBox(
              maxWidth: side,
              maxHeight: side,
              child: SizedBox(width: side, height: side, child: widget.cover),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x55000000), Color(0x000F0F13), C.bg],
                stops: [0, 0.35, 0.97],
              ),
            ),
          ),
          // hides the picture's last pixel row
          const Positioned(
            left: 0,
            right: 0,
            bottom: -1,
            height: 3,
            child: ColoredBox(color: C.bg),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 0,
            child: FadeSlideIn(
              offset: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.kicker != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        widget.kicker!,
                        style: T.faint.copyWith(
                          letterSpacing: 1.6,
                          fontWeight: FontWeight.w700,
                          color: C.textDim,
                        ),
                      ),
                    ),
                  Text(
                    widget.title,
                    style: T.h1.copyWith(fontSize: 28, height: 1.15),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: 4),
                    DefaultTextStyle.merge(
                      textAlign: TextAlign.start,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: widget.subtitle!,
                      ),
                    ),
                  ],
                  if (all.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(_info(all, total), style: T.dim),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Artist page: round picture in the middle.
  Widget _roundHeader(
    BuildContext context,
    double top,
    List<Track> all,
    double total,
  ) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, top + 52, 24, 0),
      child: Column(
        children: [
          FadeSlideIn(
            offset: 20,
            child: Container(
              width: 136,
              height: 136,
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: accentGradient,
              ),
              child: widget.cover,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.title,
            style: T.h1.copyWith(fontSize: 26),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (widget.subtitle != null) ...[
            const SizedBox(height: 4),
            widget.subtitle!,
          ],
          if (all.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(_info(all, total), style: T.dim),
          ],
        ],
      ),
    );
  }
}

/// "Oyna" (or "Duraklat" while this list is playing).
class _PlayButton extends StatelessWidget {
  final List<Track> all;
  final String name;
  const _PlayButton({required this.all, required this.name});
  @override
  Widget build(BuildContext context) {
    final player = context.read<MusicHandler>();
    return ValueListenableBuilder<String>(
      valueListenable: player.contextName,
      builder: (context, ctxName, _) => ValueListenableBuilder<bool>(
        valueListenable: player.playing,
        builder: (context, playing, _) {
          final mine =
              ctxName == name &&
              all.any((t) => t.id == player.current.value?.id);
          return _PillButton(
            icon: mine && playing
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
            label: mine && playing ? 'Duraklat' : 'Oyna',
            accent: true,
            onTap: all.isEmpty
                ? null
                : () {
                    if (mine) {
                      player.togglePlay();
                    } else {
                      playList(context, all, name: name);
                    }
                  },
          );
        },
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool accent;
  final VoidCallback? onTap;
  const _PillButton({
    required this.icon,
    required this.label,
    this.accent = false,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return NeuButton(
      radius: 24,
      height: 46,
      color: accent ? C.accent : C.surfaceHi,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14.5,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// Back button of the pages: a dark round button while over a picture.
class _BarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool solid;
  final VoidCallback onTap;
  const _BarButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.solid = false,
  });
  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: solid
            ? Colors.black.withValues(alpha: 0.35)
            : Colors.transparent,
      ),
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        onPressed: onTap,
        icon: Icon(icon, size: 18, color: C.text),
      ),
    );
  }
}

/// Plain page with a back button and a title (lists, settings).
class SubPage extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget> actions;
  const SubPage({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(8, top + 8, 8, 6),
          child: Row(
            children: [
              if (Navigator.of(context).canPop()) ...[
                _BarButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  tooltip: 'Geri',
                  onTap: () => Navigator.maybePop(context),
                ),
                const SizedBox(width: 8),
              ] else
                const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: T.h2,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ...actions,
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
