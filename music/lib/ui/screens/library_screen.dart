import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/downloads.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../state/app_state.dart';
import '../nav.dart';
import '../neu.dart';
import '../theme.dart';
import '../track_menu.dart';
import '../widgets/common.dart';
import '../widgets/cover.dart';
import '../widgets/rows.dart';
import 'album_screen.dart';
import 'artist_screen.dart';
import 'downloads_screen.dart';
import 'liked_screen.dart';
import 'playlist_screen.dart';
import 'settings_screen.dart';
import 'tracks_screen.dart';

/// "Kitaplık": playlists, albums, artists, songs and downloads.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  int _tab = 0;
  static const _tabs = [
    'Çalma Listeleri',
    'Albümler',
    'Sanatçılar',
    'İndirilenler',
  ];

  @override
  Widget build(BuildContext context) {
    final online = context.select<AppState, bool>((s) => s.online);
    Widget body;
    switch (_tab) {
      case 1:
        body = const _Albums();
      case 2:
        body = const _Artists();
      case 3:
        body = const _DownloadsList();
      default:
        body = const _Playlists();
    }
    return Scaffold(
      body: Column(
        children: [
          PageTitle(
            'Kitaplık',
            actions: [
              IconButton(
                tooltip: 'Tüm şarkılar',
                icon: const Icon(Icons.library_music_rounded),
                onPressed: () =>
                    ShellNav.push(const TracksScreen(title: 'Tüm şarkılar')),
              ),
              IconButton(
                tooltip: 'Ayarlar',
                icon: const Icon(Icons.settings_rounded),
                onPressed: () => ShellNav.push(const SettingsScreen()),
              ),
            ],
          ),
          SizedBox(
            height: 54,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              clipBehavior: Clip.none,
              itemCount: _tabs.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) => NeuButton(
                active: _tab == i,
                radius: 20,
                depth: 0.6,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                onTap: () => setState(() => _tab = i),
                child: Text(
                  _tabs[i],
                  style: TextStyle(
                    color: _tab == i ? C.accent : C.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: KeyedSubtree(key: ValueKey('$_tab-$online'), child: body),
            ),
          ),
        ],
      ),
    );
  }
}

class _Playlists extends StatelessWidget {
  const _Playlists();
  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final dl = context.watch<Downloads>();
    return ValueListenableBuilder<List<Playlist>>(
      valueListenable: app.playlists,
      builder: (context, lists, _) {
        final online = app.online;
        // offline: the downloaded playlists
        final offlineLists = online
            ? const <DownloadCollection>[]
            : dl.collections.where((c) => c.type == 'playlist').toList();
        return RefreshIndicator(
          color: C.accent,
          onRefresh: app.refreshUserData,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 140),
            children: [
              _LibTile(
                leading: const LikedCover(radius: 8),
                title: 'Beğenilen Şarkılar',
                subtitle:
                    'Çalma listesi • ${songCount(app.liked.value.length)}',
                onTap: () => ShellNav.push(const LikedScreen()),
              ),
              if (online)
                _LibTile(
                  leading: Container(
                    decoration: BoxDecoration(
                      color: C.bgDeep,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      color: C.accent,
                      size: 30,
                    ),
                  ),
                  title: 'Yeni çalma listesi',
                  onTap: () async {
                    final name = await askText(
                      context,
                      title: 'Yeni çalma listesi',
                      hint: 'Liste adı',
                      ok: 'Oluştur',
                    );
                    if (name == null) return;
                    final p = await app.createPlaylist(name);
                    if (p != null) {
                      ShellNav.push(PlaylistScreen(id: p.id, name: p.name));
                    }
                  },
                ),
              for (var i = 0; i < lists.length && online; i++)
                FadeSlideIn(
                  index: i,
                  child: _LibTile(
                    leading: MosaicCover(
                      covers: lists[i].covers,
                      seed: lists[i].id,
                      radius: 8,
                      width: 160,
                    ),
                    title: lists[i].name,
                    subtitle:
                        'Çalma listesi • ${songCount(lists[i].trackCount)}',
                    downloaded:
                        dl.collection('playlist:${lists[i].id}') != null,
                    onTap: () => ShellNav.push(
                      PlaylistScreen(id: lists[i].id, name: lists[i].name),
                    ),
                  ),
                ),
              for (final c in offlineLists)
                _LibTile(
                  leading: collectionCover(
                    c,
                    dl.collectionTracks(c),
                    radius: 8,
                  ),
                  title: c.name,
                  subtitle:
                      'İndirildi • ${songCount(dl.collectionTracks(c).length)}',
                  downloaded: true,
                  onTap: () => ShellNav.push(
                    DownloadedCollectionScreen(collectionKey: c.key),
                  ),
                ),
              if (!online && offlineLists.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Çevrimdışısın. İndirdiğin çalma listeleri burada görünür.',
                    style: T.dim,
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _LibTile extends StatelessWidget {
  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool downloaded;
  const _LibTile({
    required this.leading,
    required this.title,
    this.subtitle = '',
    required this.onTap,
    this.downloaded = false,
  });
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            SizedBox(width: 60, height: 60, child: leading),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: T.body.copyWith(fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (downloaded)
                          const Padding(
                            padding: EdgeInsets.only(right: 5),
                            child: Icon(
                              Icons.arrow_circle_down_rounded,
                              size: 14,
                              color: C.accent,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            subtitle,
                            style: T.dim,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Albums extends StatefulWidget {
  const _Albums();
  @override
  State<_Albums> createState() => _AlbumsState();
}

class _AlbumsState extends State<_Albums> {
  String _sort = 'title';
  static const _sorts = {
    'title': 'Ada göre',
    'artist': 'Sanatçıya göre',
    'year': 'Yıla göre',
    'added': 'Son eklenen',
    'recent': 'Son dinlenen',
  };

  @override
  Widget build(BuildContext context) {
    return DataView<List<Album>>(
      reloadKey: _sort,
      load: (api) => api.albums(sort: _sort),
      offline: const _DownloadsList(),
      builder: (context, albums, _) => CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
              child: Row(
                children: [
                  Expanded(child: Text('${albums.length} albüm', style: T.dim)),
                  PopupMenuButton<String>(
                    color: C.raisedTop,
                    initialValue: _sort,
                    onSelected: (v) => setState(() => _sort = v),
                    itemBuilder: (_) => [
                      for (final e in _sorts.entries)
                        PopupMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.sort_rounded,
                            size: 18,
                            color: C.textDim,
                          ),
                          const SizedBox(width: 6),
                          Text(_sorts[_sort]!, style: T.dim),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (albums.isEmpty)
            const SliverToBoxAdapter(
              child: EmptyState(icon: Icons.album_rounded, title: 'Albüm yok'),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 140),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 190,
                mainAxisSpacing: 18,
                crossAxisSpacing: 18,
                childAspectRatio: 0.74,
              ),
              itemCount: albums.length,
              itemBuilder: (context, i) => LayoutBuilder(
                builder: (context, c) =>
                    AlbumCard(album: albums[i], width: c.maxWidth),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Artists extends StatelessWidget {
  const _Artists();
  @override
  Widget build(BuildContext context) {
    return DataView<List<Artist>>(
      load: (api) => api.artists(),
      offline: const _DownloadsList(),
      builder: (context, artists, _) => ListView.builder(
        padding: const EdgeInsets.only(bottom: 140),
        itemCount: artists.length,
        itemBuilder: (context, i) {
          final a = artists[i];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 3,
            ),
            leading: SizedBox(
              width: 56,
              height: 56,
              child: CoverImage(
                cover: a.cover,
                circle: true,
                width: 160,
                placeholderIcon: Icons.person_rounded,
              ),
            ),
            title: Text(
              a.name,
              style: T.body.copyWith(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              [
                if (a.albumCount > 0) '${a.albumCount} albüm',
                songCount(a.trackCount),
              ].join(' • '),
              style: T.dim,
            ),
            onTap: () => ShellNav.push(ArtistScreen(id: a.id, name: a.name)),
          );
        },
      ),
    );
  }
}

/// Short downloads overview inside the library (full page: DownloadsScreen).
class _DownloadsList extends StatelessWidget {
  const _DownloadsList();
  @override
  Widget build(BuildContext context) {
    final dl = context.watch<Downloads>();
    final cols = dl.collections;
    final tracks = dl.tracks;
    return ListView(
      padding: const EdgeInsets.only(bottom: 140),
      children: [
        _LibTile(
          leading: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [C.accentLo, C.accent]),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.download_done_rounded,
              color: Colors.black,
              size: 30,
            ),
          ),
          title: 'Tüm indirilenler',
          subtitle: dl.activeCount > 0
              ? '${songCount(tracks.length)} • ${dl.activeCount} indiriliyor'
              : '${songCount(tracks.length)} • ${formatSize(dl.totalBytes)}',
          onTap: () => ShellNav.push(const DownloadsScreen()),
        ),
        for (final c in cols)
          _LibTile(
            leading: collectionCover(c, dl.collectionTracks(c), radius: 8),
            title: c.name,
            subtitle:
                '${c.subtitle.isNotEmpty ? c.subtitle : 'İndirildi'} • ${songCount(dl.collectionTracks(c).length)}',
            downloaded: true,
            onTap: () {
              if (c.type == 'album' && context.read<AppState>().online) {
                ShellNav.push(AlbumScreen(id: c.id, title: c.name));
              } else {
                ShellNav.push(DownloadedCollectionScreen(collectionKey: c.key));
              }
            },
          ),
        if (tracks.isEmpty && dl.activeCount == 0)
          const Padding(
            padding: EdgeInsets.all(28),
            child: Text(
              'Albüm, çalma listesi, klasör ya da şarkı indirerek sunucu olmadan dinleyebilirsin.',
              style: T.dim,
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}
