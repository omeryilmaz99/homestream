import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/downloads.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../state/app_state.dart';
import '../nav.dart';
import '../neu.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/cover.dart';
import '../widgets/rows.dart';
import '../widgets/track_tile.dart';
import 'folders_screen.dart';
import 'playlist_screen.dart';
import 'tracks_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  String _q = '';
  SearchResults? _results;
  bool _loading = false;
  String? _error;
  int _seq = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed(String v) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 280),
      () => _search(v.trim()),
    );
    setState(() {});
  }

  Future<void> _search(String q) async {
    if (q == _q && _results != null) return;
    _q = q;
    final seq = ++_seq;
    if (q.isEmpty) {
      setState(() {
        _results = null;
        _loading = false;
      });
      return;
    }
    final app = context.read<AppState>();
    if (!app.online || app.api == null) {
      setState(() {
        _results = _localSearch(q);
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final r = await app.api!.search(q);
      if (!mounted || seq != _seq) return;
      setState(() {
        _results = r;
        _loading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted || seq != _seq) return;
      if (e.offline) app.ping();
      setState(() {
        _results = _localSearch(q);
        _loading = false;
        _error = e.offline ? null : e.message;
      });
    }
  }

  SearchResults _localSearch(String q) {
    final f = foldTr(q);
    final tracks = context
        .read<Downloads>()
        .tracks
        .where((t) => foldTr('${t.title} ${t.artist} ${t.album}').contains(f))
        .toList();
    return SearchResults(tracks, [], [], [], []);
  }

  void _remember(String q) {
    if (q.isEmpty) return;
    final prefs = context.read<AppState>().prefs;
    prefs.recentSearches = [q, ...prefs.recentSearches.where((e) => e != q)];
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, top + 14, 20, 6),
            child: const Align(
              alignment: Alignment.centerLeft,
              child: Text('Ara', style: T.h1),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 8),
            child: NeuBox(
              style: NeuStyle.inset,
              radius: 18,
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                onChanged: _changed,
                onSubmitted: (v) {
                  _remember(v.trim());
                  _search(v.trim());
                },
                textInputAction: TextInputAction.search,
                style: T.body,
                decoration: InputDecoration(
                  hintText: 'Şarkı, sanatçı, albüm, klasör…',
                  filled: false,
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: C.textDim,
                  ),
                  suffixIcon: _ctrl.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _ctrl.clear();
                            _search('');
                          },
                        ),
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ),
          ),
          if (_loading)
            const LinearProgressIndicator(minHeight: 2)
          else
            const SizedBox(height: 2),
          Expanded(
            child: GestureDetector(
              onTap: () => _focus.unfocus(),
              behavior: HitTestBehavior.translucent,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _ctrl.text.trim().isEmpty
                    ? _Browse(
                        key: const ValueKey('browse'),
                        onRecent: (q) {
                          _ctrl.text = q;
                          _search(q);
                        },
                      )
                    : _resultsView(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultsView() {
    final r = _results;
    if (r == null) return const SizedBox.shrink(key: ValueKey('none'));
    final online = context.read<AppState>().online;
    if (r.isEmpty) {
      return EmptyState(
        key: const ValueKey('empty'),
        icon: Icons.search_off_rounded,
        title: '"$_q" için sonuç yok',
        message:
            _error ??
            (online
                ? 'Başka bir kelime dene.'
                : 'Çevrimdışı: yalnızca indirilen şarkılarda arandı.'),
      );
    }
    final tracks = r.tracks;
    return ListView(
      key: ValueKey('r$_q'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: 150),
      children: [
        if (!online)
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(
              'Çevrimdışı: indirilen şarkılarda arandı',
              style: T.faint,
            ),
          ),
        if (r.artists.isNotEmpty)
          HorizontalRow(
            title: 'Sanatçılar',
            count: r.artists.length,
            height: 200,
            itemBuilder: (context, i) => GestureDetector(
              onTapDown: (_) => _remember(_q),
              child: ArtistCard(artist: r.artists[i], width: 130),
            ),
          ),
        if (tracks.isNotEmpty) ...[
          SectionHeader(
            'Şarkılar',
            action: tracks.length > 6 ? 'Tümü (${tracks.length})' : null,
            onAction: () => ShellNav.push(
              TracksScreen(
                title: '"$_q"',
                preset: tracks,
                contextName: 'Arama: $_q',
              ),
            ),
          ),
          for (var i = 0; i < tracks.length && i < 6; i++)
            TrackTile(
              track: tracks[i],
              showAlbum: true,
              onTap: () {
                _remember(_q);
                playList(context, tracks, index: i, name: 'Arama: $_q');
              },
            ),
        ],
        if (r.albums.isNotEmpty)
          HorizontalRow(
            title: 'Albümler',
            count: r.albums.length,
            itemBuilder: (context, i) => GestureDetector(
              onTapDown: (_) => _remember(_q),
              child: AlbumCard(album: r.albums[i]),
            ),
          ),
        if (r.playlists.isNotEmpty) ...[
          const SectionHeader('Çalma listeleri'),
          for (final p in r.playlists)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: SizedBox(
                width: 50,
                height: 50,
                child: MosaicCover(
                  covers: p.covers,
                  seed: p.id,
                  radius: 8,
                  width: 150,
                ),
              ),
              title: Text(p.name, style: T.body),
              subtitle: Text(songCount(p.trackCount), style: T.dim),
              onTap: () =>
                  ShellNav.push(PlaylistScreen(id: p.id, name: p.name)),
            ),
        ],
        if (r.folders.isNotEmpty) ...[
          const SectionHeader('Klasörler'),
          for (final f in r.folders)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: SizedBox(
                width: 50,
                height: 50,
                child: FolderCover(cover: f.cover, radius: 8),
              ),
              title: Text(f.name, style: T.body),
              subtitle: Text(songCount(f.count), style: T.dim),
              onTap: () {
                _remember(_q);
                ShellNav.push(FolderScreen(path: f.path, title: f.name));
              },
            ),
        ],
      ],
    );
  }
}

/// Before typing: recent searches and genres.
class _Browse extends StatelessWidget {
  final ValueChanged<String> onRecent;
  const _Browse({super.key, required this.onRecent});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final recent = app.prefs.recentSearches;
    return ListView(
      padding: const EdgeInsets.only(bottom: 150),
      children: [
        if (recent.isNotEmpty) ...[
          SectionHeader(
            'Son aramalar',
            action: 'Temizle',
            onAction: app.clearRecentSearches,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final q in recent)
                  NeuButton(
                    radius: 16,
                    depth: 0.5,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    onTap: () => onRecent(q),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.history_rounded,
                          size: 16,
                          color: C.textDim,
                        ),
                        const SizedBox(width: 6),
                        Text(q, style: T.dim.copyWith(color: C.text)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (app.online)
          DataView<List<Genre>>(
            load: (api) => api.genres(),
            builder: (context, genres, _) => genres.isEmpty
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader('Türlere göz at'),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 220,
                                mainAxisSpacing: 14,
                                crossAxisSpacing: 14,
                                childAspectRatio: 1.75,
                              ),
                          itemCount: genres.length,
                          itemBuilder: (context, i) => FadeSlideIn(
                            index: i,
                            child: _GenreTile(genre: genres[i], index: i),
                          ),
                        ),
                      ),
                    ],
                  ),
          )
        else
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Çevrimdışısın: arama indirilen şarkılarda yapılır.',
              style: T.dim,
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

class _GenreTile extends StatelessWidget {
  final Genre genre;
  final int index;
  const _GenreTile({required this.genre, required this.index});
  @override
  Widget build(BuildContext context) {
    final p = coverPalettes[index % coverPalettes.length];
    return NeuButton(
      radius: 16,
      depth: 0.7,
      onTap: () => ShellNav.push(
        TracksScreen(
          title: genre.name,
          genre: genre.name,
          contextName: genre.name,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox.expand(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [p[0], p[1]],
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -14,
                  bottom: -8,
                  child: Transform.rotate(
                    angle: 0.42,
                    child: SizedBox(
                      width: 62,
                      height: 62,
                      child: CoverImage(
                        cover: genre.cover,
                        radius: 6,
                        width: 160,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        genre.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        songCount(genre.trackCount),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white70,
                        ),
                      ),
                    ],
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
