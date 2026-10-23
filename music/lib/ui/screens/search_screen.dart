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
import '../widgets/collection.dart';
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
              child: Text('Keşfet', style: T.h1),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
            child: NeuBox(
              radius: 14,
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
                  hintText: 'Sanatçı, şarkı, albüm veya klasör ara…',
                  hintStyle: T.dim.copyWith(color: C.textFaint),
                  filled: false,
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: C.textDim,
                    size: 22,
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
                  contentPadding: const EdgeInsets.symmetric(vertical: 13),
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

/// Before typing: genres and recent searches.
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
        if (app.online)
          DataView<List<Genre>>(
            load: (api) => api.genres(),
            builder: (context, genres, _) => genres.isEmpty
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionHeader(
                        'Müzik Türleri',
                        action: genres.length > 6 ? 'Tümünü Gör' : null,
                        onAction: () =>
                            ShellNav.push(GenresScreen(genres: genres)),
                      ),
                      GenreGrid(genres: genres.take(6).toList()),
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
        if (recent.isNotEmpty) ...[
          SectionHeader(
            'Son Aramalar',
            action: 'Temizle',
            onAction: app.clearRecentSearches,
          ),
          for (final q in recent)
            InkWell(
              onTap: () => onRecent(q),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 8, 2),
                child: Row(
                  children: [
                    const Icon(
                      Icons.history_rounded,
                      size: 20,
                      color: C.textDim,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        q,
                        style: T.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kaldır',
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: C.textFaint,
                      ),
                      onPressed: () => app.removeRecentSearch(q),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// Bright colours of the genre tiles.
const _genreColors = [
  [Color(0xFFFF5E9C), Color(0xFFD9386F)],
  [Color(0xFF5865F2), Color(0xFF5B3FD6)],
  [Color(0xFF9B4DEB), Color(0xFF6C2BC9)],
  [Color(0xFFF2803E), Color(0xFFDA4B3A)],
  [Color(0xFF22A88F), Color(0xFF117263)],
  [Color(0xFFB096F7), Color(0xFF8063E6)],
  [Color(0xFF3A9BEF), Color(0xFF2E5FD1)],
  [Color(0xFFE5508C), Color(0xFF9B3FC4)],
];

class GenreGrid extends StatelessWidget {
  final List<Genre> genres;
  const GenreGrid({super.key, required this.genres});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: GridView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.2,
        ),
        itemCount: genres.length,
        itemBuilder: (context, i) => FadeSlideIn(
          index: i,
          child: _GenreTile(genre: genres[i], index: i),
        ),
      ),
    );
  }
}

class GenresScreen extends StatelessWidget {
  final List<Genre> genres;
  const GenresScreen({super.key, required this.genres});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SubPage(
        title: 'Müzik Türleri',
        child: ListView(
          padding: const EdgeInsets.only(top: 6, bottom: 150),
          children: [GenreGrid(genres: genres)],
        ),
      ),
    );
  }
}

class _GenreTile extends StatelessWidget {
  final Genre genre;
  final int index;
  const _GenreTile({required this.genre, required this.index});
  @override
  Widget build(BuildContext context) {
    final p = _genreColors[index % _genreColors.length];
    return PressScale(
      onTap: () => ShellNav.push(
        TracksScreen(
          title: genre.name,
          genre: genre.name,
          contextName: genre.name,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: p,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 9),
        child: Stack(
          children: [
            Positioned(
              right: -2,
              top: 0,
              child: Icon(
                Icons.graphic_eq_rounded,
                size: 22,
                color: Colors.white.withValues(alpha: 0.35),
              ),
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    genre.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                      color: Colors.white,
                      height: 1.15,
                    ),
                  ),
                  Text(
                    songCount(genre.trackCount),
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Color(0xCCFFFFFF),
                    ),
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
