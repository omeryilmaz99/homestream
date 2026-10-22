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
      _bar.value = ((_scroll.offset - 200) / 80).clamp(0.0, 1.0);
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
    final player = context.read<MusicHandler>();
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

    return Stack(
      children: [
        CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(24, top + 58, 24, 0),
                child: Column(
                  children: [
                    FadeSlideIn(
                      offset: 24,
                      child: Center(
                        child: NeuBox(
                          circle: widget.roundCover,
                          radius: 22,
                          padding: const EdgeInsets.all(10),
                          depth: 1.4,
                          child: SizedBox(
                            width: MediaQuery.sizeOf(context).width * 0.58,
                            height: MediaQuery.sizeOf(context).width * 0.58,
                            child: widget.cover,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    if (widget.kicker != null)
                      Text(
                        widget.kicker!,
                        style: T.faint.copyWith(
                          letterSpacing: 2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      widget.title,
                      style: T.h1.copyWith(fontSize: 25),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 6),
                      widget.subtitle!,
                    ],
                    const SizedBox(height: 6),
                    Text(
                      all.isEmpty
                          ? ''
                          : '${songCount(all.length)} • ${formatTotal(total)}',
                      style: T.faint,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        ...widget.actions,
                        const Spacer(),
                        NeuIconButton(
                          Icons.shuffle_rounded,
                          size: 48,
                          tooltip: 'Karışık çal',
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
                        const SizedBox(width: 16),
                        ValueListenableBuilder<String>(
                          valueListenable: player.contextName,
                          builder: (context, ctxName, _) =>
                              ValueListenableBuilder<bool>(
                                valueListenable: player.playing,
                                builder: (context, playing, _) {
                                  final mine =
                                      ctxName == widget.title &&
                                      all.any(
                                        (t) => t.id == player.current.value?.id,
                                      );
                                  return NeuIconButton(
                                    mine && playing
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    size: 62,
                                    iconSize: 34,
                                    accent: true,
                                    tooltip: 'Çal',
                                    onTap: all.isEmpty
                                        ? null
                                        : () {
                                            if (mine) {
                                              player.togglePlay();
                                            } else {
                                              playList(
                                                context,
                                                all,
                                                name: widget.title,
                                              );
                                            }
                                          },
                                  );
                                },
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
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
              boxShadow: v > 0.5
                  ? [
                      BoxShadow(
                        color: C.dark.withValues(alpha: 0.6),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                const SizedBox(width: 8),
                if (Navigator.of(context).canPop()) ...[
                  NeuIconButton(
                    Icons.arrow_back_rounded,
                    size: 40,
                    iconSize: 20,
                    tooltip: 'Geri',
                    onTap: () => Navigator.maybePop(context),
                  ),
                  const SizedBox(width: 12),
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
                NeuIconButton(
                  Icons.arrow_back_rounded,
                  size: 40,
                  iconSize: 20,
                  tooltip: 'Geri',
                  onTap: () => Navigator.maybePop(context),
                ),
                const SizedBox(width: 12),
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
