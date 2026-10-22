import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../theme.dart';
import '../track_menu.dart';
import '../widgets/collection.dart';
import '../widgets/common.dart';
import '../widgets/track_tile.dart';

const _sorts = {
  'title': 'Ada göre',
  'artist': 'Sanatçıya göre',
  'album': 'Albüme göre',
  'added': 'Son eklenen',
  'plays': 'En çok dinlenen',
  'recent': 'Son dinlenen',
};

/// A long song list: all songs, a genre, or a given list.
class TracksScreen extends StatefulWidget {
  final String title;
  final String? genre;
  final List<Track>? preset;
  final String contextName;
  final String initialSort;
  const TracksScreen({
    super.key,
    required this.title,
    this.genre,
    this.preset,
    this.contextName = '',
    this.initialSort = 'title',
  });

  @override
  State<TracksScreen> createState() => _TracksScreenState();
}

class _TracksScreenState extends State<TracksScreen> {
  late String _sort = widget.initialSort;
  String _filter = '';

  List<Track> _apply(List<Track> all) {
    if (_filter.isEmpty) return all;
    final q = foldTr(_filter);
    return all
        .where((t) => foldTr('${t.title} ${t.artist} ${t.album}').contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.contextName.isNotEmpty
        ? widget.contextName
        : widget.title;
    Widget list(List<Track> all) {
      final tracks = _apply(all);
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: TextField(
                        onChanged: (v) => setState(() => _filter = v.trim()),
                        decoration: const InputDecoration(
                          hintText: 'Listede ara',
                          prefixIcon: Icon(Icons.search_rounded, size: 20),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    tooltip: 'Karışık çal',
                    onPressed: tracks.isEmpty
                        ? null
                        : () => playList(
                            context,
                            tracks,
                            index: -1,
                            shuffle: true,
                            name: name,
                          ),
                    icon: const Icon(Icons.shuffle_rounded),
                  ),
                  IconButton.filled(
                    tooltip: 'Çal',
                    style: IconButton.styleFrom(
                      backgroundColor: C.accent,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: tracks.isEmpty
                        ? null
                        : () => playList(context, tracks, name: name),
                    icon: const Icon(Icons.play_arrow_rounded),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                '${songCount(tracks.length)} • ${formatTotal(tracks.fold(0.0, (a, t) => a + t.duration))}',
                style: T.faint,
              ),
            ),
          ),
          if (tracks.isEmpty)
            const SliverToBoxAdapter(
              child: EmptyState(
                icon: Icons.music_off_rounded,
                title: 'Şarkı bulunamadı',
              ),
            )
          else
            SliverList.builder(
              itemCount: tracks.length,
              itemBuilder: (context, i) => TrackTile(
                track: tracks[i],
                showAlbum: true,
                onTap: () => playList(context, tracks, index: i, name: name),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 140)),
        ],
      );
    }

    return Scaffold(
      body: SubPage(
        title: widget.title,
        actions: [
          if (widget.preset == null)
            PopupMenuButton<String>(
              tooltip: 'Sırala',
              icon: const Icon(Icons.sort_rounded),
              color: C.raisedTop,
              initialValue: _sort,
              onSelected: (v) => setState(() => _sort = v),
              itemBuilder: (_) => [
                for (final e in _sorts.entries)
                  PopupMenuItem(value: e.key, child: Text(e.value)),
              ],
            ),
          if (widget.preset != null)
            IconButton(
              tooltip: 'Çalma listesine ekle',
              icon: const Icon(Icons.playlist_add_rounded),
              onPressed: () => showAddToPlaylist(context, widget.preset!),
            ),
        ],
        child: widget.preset != null
            ? list(widget.preset!)
            : DataView<List<Track>>(
                reloadKey: _sort,
                load: (api) => api.tracks(sort: _sort, genre: widget.genre),
                builder: (context, all, _) => list(all),
              ),
      ),
    );
  }
}
