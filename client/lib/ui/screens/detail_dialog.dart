import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/media_card.dart';
import '../widgets/net_image.dart';
import 'play_launcher.dart';

/// Opens the info panel for a movie, series or episode.
Future<void> openDetail(BuildContext context, MediaItem item) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Kapat',
    barrierColor: Colors.black.withValues(alpha: 0.75),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (_, _, _) => DetailDialog(item: item),
    transitionBuilder: (_, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.94, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class DetailDialog extends StatefulWidget {
  final MediaItem item;
  const DetailDialog({super.key, required this.item});

  @override
  State<DetailDialog> createState() => _DetailDialogState();
}

class _DetailDialogState extends State<DetailDialog> {
  late MediaItem _item = widget.item;
  bool _loading = true;
  String? _error;
  Related? _related;
  int _seasonIndex = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AppState>().api;
    if (api == null) return;
    try {
      final d = await api.item(widget.item.id);
      if (!mounted) return;
      setState(() {
        _item = d;
        _loading = false;
        _error = null;
        if (d.isSeries && d.seasons.isNotEmpty) {
          final target = d.nextUp?.season;
          final i = d.seasons.indexWhere((s) => s.number == target);
          _seasonIndex = i >= 0 ? i : 0;
        }
      });
      final rel = await api.related(widget.item.id);
      if (mounted) setState(() => _related = rel);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _play({double? startAt, MediaItem? target}) async {
    final t = target ?? (_item.isSeries ? _item.nextUp : _item);
    if (t == null) return;
    await playItem(context, t, startAt: startAt);
    if (mounted) _load();
  }

  Future<void> _toggleLike() async {
    final api = context.read<AppState>().api!;
    final liked = !_item.userData.liked;
    setState(() => _item.userData = _item.userData.copyWith(liked: liked));
    try {
      await api.setLiked(_item.id, liked);
      if (mounted) {
        context.read<AppState>().bumpData();
        showToast(
          context,
          liked ? 'Beğendiklerine eklendi' : 'Beğeni kaldırıldı',
        );
      }
    } catch (e) {
      if (mounted) showToast(context, e.toString(), error: true);
    }
  }

  Future<void> _setPlayed(MediaItem target, bool played) async {
    final api = context.read<AppState>().api!;
    try {
      await api.setPlayed(target.id, played);
      if (!mounted) return;
      context.read<AppState>().bumpData();
      showToast(
        context,
        played ? 'İzlendi olarak işaretlendi' : 'İzlenmedi olarak işaretlendi',
      );
      _load();
    } catch (e) {
      if (mounted) showToast(context, e.toString(), error: true);
    }
  }

  Future<void> _openSeries() async {
    if (_item.seriesId.isEmpty) return;
    final nav = Navigator.of(context);
    final api = context.read<AppState>().api!;
    final navContext = nav.context;
    nav.pop();
    try {
      final s = await api.item(_item.seriesId);
      if (navContext.mounted) openDetail(navContext, s);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = (size.width * 0.9).clamp(320.0, 980.0);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
      },
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            elevation: 24,
            child: SizedBox(
              width: w,
              child: CustomScrollView(
                shrinkWrap: true,
                slivers: [
                  SliverToBoxAdapter(child: _header(w)),
                  SliverToBoxAdapter(child: _body()),
                  if (_item.isSeries && _item.seasons.isNotEmpty)
                    ..._episodes(),
                  if (_related != null && _related!.recommended.isNotEmpty)
                    ..._recommended(w),
                  const SliverToBoxAdapter(child: SizedBox(height: 28)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(double w) {
    final h = w * 0.5;
    final playTarget = _item.isSeries ? _item.nextUp : _item;
    final inProgress = playTarget?.inProgress ?? false;
    String playLabel;
    if (_item.isSeries) {
      if (playTarget == null) {
        playLabel = 'Oynat';
      } else {
        playLabel =
            '${inProgress ? 'Devam Et' : 'Oynat'} · ${playTarget.episodeCode}';
      }
    } else {
      playLabel = inProgress
          ? 'Devam Et · ${formatDuration(_item.userData.position)}'
          : 'Oynat';
    }
    return SizedBox(
      height: h,
      child: Stack(
        fit: StackFit.expand,
        children: [
          NetImage(_item.backdrop, width: 1280, alignment: Alignment.topCenter),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x33000000),
                  Color(0x00000000),
                  AppColors.surface,
                ],
                stops: [0, 0.35, 1],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0xCC14141C), Color(0x0014141C)],
                stops: [0, 0.7],
              ),
            ),
          ),
          Positioned(
            top: 14,
            right: 14,
            child: CircleIconButton(
              icon: Icons.close_rounded,
              size: 40,
              tooltip: 'Kapat (Esc)',
              onPressed: () => Navigator.pop(context),
            ),
          ),
          Positioned(
            left: 32,
            right: 32,
            bottom: 18,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (w > 640)
                  Padding(
                    padding: const EdgeInsets.only(right: 22),
                    child: Container(
                      width: 150,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(color: Colors.black87, blurRadius: 24),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: AspectRatio(
                          aspectRatio: 2 / 3,
                          child: NetImage(
                            _item.isEpisode && _item.seriesId.isNotEmpty
                                ? '/api/images/${_item.seriesId}/poster'
                                : _item.poster,
                            width: 320,
                          ),
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_item.isEpisode && _item.seriesTitle.isNotEmpty)
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: _openSeries,
                            child: Text(
                              _item.seriesTitle.toUpperCase(),
                              style: const TextStyle(
                                letterSpacing: 2.5,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppColors.accent2,
                              ),
                            ),
                          ),
                        ),
                      Text(
                        _item.isEpisode
                            ? '${_item.episodeCode}${_item.title.isNotEmpty ? ' · ${_item.title}' : ''}'
                            : _item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: w > 640 ? 36 : 26,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                          letterSpacing: -1,
                          shadows: const [
                            Shadow(blurRadius: 20, color: Colors.black),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          PillButton(
                            primary: true,
                            autofocus: true,
                            icon: Icons.play_arrow_rounded,
                            label: playLabel,
                            onPressed: _loading || playTarget == null
                                ? null
                                : () => _play(),
                          ),
                          if (inProgress)
                            PillButton(
                              icon: Icons.replay_rounded,
                              label: 'Baştan Başla',
                              onPressed: () => _play(startAt: 0),
                            ),
                          if (!_item.isEpisode)
                            CircleIconButton(
                              icon: _item.userData.liked
                                  ? Icons.thumb_up_alt_rounded
                                  : Icons.thumb_up_alt_outlined,
                              active: _item.userData.liked,
                              tooltip: _item.userData.liked
                                  ? 'Beğeniyi kaldır'
                                  : 'Beğendim',
                              onPressed: _toggleLike,
                            ),
                          CircleIconButton(
                            icon: _item.userData.played
                                ? Icons.check_circle_rounded
                                : Icons.check_circle_outline_rounded,
                            active: _item.userData.played,
                            tooltip: _item.userData.played
                                ? 'İzlenmedi olarak işaretle'
                                : 'İzlendi olarak işaretle',
                            onPressed: () =>
                                _setPlayed(_item, !_item.userData.played),
                          ),
                          if (_item.isEpisode && _item.seriesId.isNotEmpty)
                            CircleIconButton(
                              icon: Icons.video_library_rounded,
                              tooltip: 'Dizinin tüm bölümleri',
                              onPressed: _openSeries,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    final f = _item.file;
    final meta = <Widget>[
      if (_item.rating > 0)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 18),
            const SizedBox(width: 3),
            Text(
              _item.rating.toStringAsFixed(1),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      if (_item.year > 0)
        Text('${_item.year}', style: const TextStyle(color: AppColors.textDim)),
      if (_item.duration > 0)
        Text(
          formatDuration(_item.duration, long: true),
          style: const TextStyle(color: AppColors.textDim),
        ),
      if (_item.isSeries)
        Text(
          '${_item.seasonCount > 0 ? '${_item.seasonCount} sezon · ' : ''}${_item.episodeCount} bölüm',
          style: const TextStyle(color: AppColors.textDim),
        ),
      if (f != null && f.resolutionLabel.isNotEmpty) Tag(f.resolutionLabel),
      if (f != null && f.hdr) const Tag('HDR'),
      if (f != null && f.audio.any((a) => a.channels >= 6))
        Tag(f.audio.any((a) => a.channels >= 8) ? '7.1' : '5.1'),
      if (f != null &&
          (f.subtitles.isNotEmpty || f.externalSubtitles.isNotEmpty))
        const Tag('Altyazı'),
    ];

    final audioLangs =
        f?.audio
            .map(
              (a) => languageName(a.language).isNotEmpty
                  ? languageName(a.language)
                  : a.title,
            )
            .where((s) => s.isNotEmpty)
            .toSet()
            .join(', ') ??
        '';
    final subLangs = {
      ...?f?.externalSubtitles.map(
        (s) => languageName(s.language).isNotEmpty
            ? languageName(s.language)
            : (s.title.isNotEmpty ? s.title : 'Harici'),
      ),
      ...?f?.subtitles.map(
        (s) => languageName(s.language).isNotEmpty
            ? languageName(s.language)
            : (s.title.isNotEmpty ? s.title : 'Bilinmeyen'),
      ),
    }.join(', ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 8, 32, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_item.isSeries && _item.inProgress) ...[
            Row(
              children: [
                SizedBox(
                  width: 240,
                  child: ProgressLine(_item.progress, height: 5),
                ),
                const SizedBox(width: 12),
                Text(
                  '${formatDuration(_item.userData.position)} / ${formatDuration(_item.duration)} · ${formatRemaining(_item.userData.position, _item.duration)}',
                  style: const TextStyle(
                    color: AppColors.textDim,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: meta,
          ),
          const SizedBox(height: 14),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(minHeight: 2),
            )
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: AppColors.danger)),
          LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth > 640;
              final overview = Text(
                _item.overview.isNotEmpty
                    ? _item.overview
                    : 'Açıklama bulunmuyor.',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.6,
                  color: _item.overview.isNotEmpty
                      ? const Color(0xFFDADAE2)
                      : AppColors.textMuted,
                ),
              );
              final info = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_item.genres.isNotEmpty)
                    _InfoLine('Tür', _item.genres.join(', ')),
                  if (audioLangs.isNotEmpty) _InfoLine('Ses', audioLangs),
                  if (subLangs.isNotEmpty) _InfoLine('Altyazı', subLangs),
                  if (f != null && f.videoCodec.isNotEmpty)
                    _InfoLine(
                      'Video',
                      '${f.videoCodec.toUpperCase()}${f.width > 0 ? ' · ${f.width}×${f.height}' : ''}',
                    ),
                  if (f != null)
                    _InfoLine('Dosya', '${f.path}  (${formatSize(f.size)})'),
                ],
              );
              if (!wide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [overview, const SizedBox(height: 14), info],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: overview),
                  const SizedBox(width: 28),
                  Expanded(flex: 2, child: info),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  List<Widget> _episodes() {
    final seasons = _item.seasons;
    final season = seasons[_seasonIndex.clamp(0, seasons.length - 1)];
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 12),
          child: Row(
            children: [
              const Text(
                'Bölümler',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              if (seasons.length > 1)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _seasonIndex,
                      dropdownColor: AppColors.surface2,
                      borderRadius: BorderRadius.circular(10),
                      items: [
                        for (var i = 0; i < seasons.length; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text(
                              '${seasons[i].title.isNotEmpty ? seasons[i].title : '${seasons[i].number}. Sezon'}  (${seasons[i].episodes.length})',
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _seasonIndex = v ?? 0),
                    ),
                  ),
                )
              else
                Text(
                  season.title.isNotEmpty
                      ? season.title
                      : '${season.number}. Sezon',
                  style: const TextStyle(color: AppColors.textDim),
                ),
            ],
          ),
        ),
      ),
      SliverList.builder(
        itemCount: season.episodes.length,
        itemBuilder: (context, i) => _EpisodeTile(
          key: ValueKey(season.episodes[i].id),
          episode: season.episodes[i],
          highlighted: _item.nextUp?.id == season.episodes[i].id,
          onPlay: (start) => _play(target: season.episodes[i], startAt: start),
          onSetPlayed: (v) => _setPlayed(season.episodes[i], v),
        ),
      ),
    ];
  }

  List<Widget> _recommended(double w) {
    final items = _related!.recommended;
    final cols = (w - 64) ~/ 150;
    return [
      const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(32, 28, 32, 14),
          child: Text(
            'Benzer İçerikler',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols.clamp(2, 6),
            childAspectRatio: 2 / 3,
            mainAxisSpacing: 16,
            crossAxisSpacing: 14,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => LayoutBuilder(
              builder: (context, c) =>
                  PosterCard(item: items[i], width: c.maxWidth),
            ),
            childCount: items.length,
          ),
        ),
      ),
    ];
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;
  const _InfoLine(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(color: AppColors.textMuted),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(color: AppColors.textDim),
          ),
        ],
      ),
      style: const TextStyle(fontSize: 13.5, height: 1.4),
    ),
  );
}

class _EpisodeTile extends StatefulWidget {
  final MediaItem episode;
  final bool highlighted;
  final void Function(double? start) onPlay;
  final void Function(bool played) onSetPlayed;
  const _EpisodeTile({
    super.key,
    required this.episode,
    required this.highlighted,
    required this.onPlay,
    required this.onSetPlayed,
  });

  @override
  State<_EpisodeTile> createState() => _EpisodeTileState();
}

class _EpisodeTileState extends State<_EpisodeTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.episode;
    return FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      onShowHoverHighlight: (v) => setState(() => _hover = v),
      onShowFocusHighlight: (v) => setState(() => _hover = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => widget.onPlay(null),
        ),
      },
      child: GestureDetector(
        onTap: () => widget.onPlay(null),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 3),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _hover
                ? AppColors.surface3
                : (widget.highlighted
                      ? AppColors.surface2
                      : Colors.transparent),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 34,
                child: Padding(
                  padding: const EdgeInsets.only(top: 30),
                  child: Text(
                    '${e.episode}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDim,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 170,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        NetImage(e.backdrop, width: 320),
                        AnimatedOpacity(
                          opacity: _hover ? 1 : 0,
                          duration: const Duration(milliseconds: 150),
                          child: Container(
                            color: Colors.black38,
                            child: const Icon(
                              Icons.play_circle_outline_rounded,
                              size: 40,
                            ),
                          ),
                        ),
                        if (e.inProgress)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: ProgressLine(e.progress, height: 4),
                          ),
                        if (e.userData.played)
                          const Positioned(
                            top: 6,
                            right: 6,
                            child: Icon(
                              Icons.check_circle_rounded,
                              color: AppColors.success,
                              size: 20,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            e.title.isNotEmpty
                                ? e.title
                                : '${e.episode}. Bölüm',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15.5,
                            ),
                          ),
                        ),
                        if (e.duration > 0)
                          Text(
                            formatDuration(e.duration, long: true),
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 13,
                            ),
                          ),
                        PopupMenuButton<String>(
                          tooltip: 'Seçenekler',
                          icon: const Icon(
                            Icons.more_vert_rounded,
                            size: 20,
                            color: AppColors.textDim,
                          ),
                          onSelected: (v) {
                            if (v == 'start') widget.onPlay(0);
                            if (v == 'played')
                              widget.onSetPlayed(!e.userData.played);
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'start',
                              child: Text('Baştan oynat'),
                            ),
                            PopupMenuItem(
                              value: 'played',
                              child: Text(
                                e.userData.played
                                    ? 'İzlenmedi olarak işaretle'
                                    : 'İzlendi olarak işaretle',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (e.inProgress)
                      Text(
                        formatRemaining(e.userData.position, e.duration),
                        style: const TextStyle(
                          color: AppColors.accent2,
                          fontSize: 12.5,
                        ),
                      ),
                    if (e.overview.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          e.overview,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textDim,
                            fontSize: 13.5,
                            height: 1.45,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
