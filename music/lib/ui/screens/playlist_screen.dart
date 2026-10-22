import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/downloads.dart';
import '../../core/models.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../track_menu.dart';
import '../widgets/collection.dart';
import '../widgets/common.dart';
import '../widgets/cover.dart';

class PlaylistScreen extends StatefulWidget {
  final String id;
  final String name;
  const PlaylistScreen({super.key, required this.id, this.name = ''});

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  int _k = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DataView<Playlist>(
        reloadKey: _k,
        load: (api) => api.playlist(widget.id),
        offline: _OfflinePlaylist(id: widget.id, name: widget.name),
        builder: (context, p, reload) => _body(context, p, reload),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    Playlist p,
    Future<void> Function() reload,
  ) {
    final app = context.read<AppState>();
    final dl = context.read<Downloads>();
    return CollectionView(
      kicker: 'ÇALMA LİSTESİ',
      title: p.name,
      cover: MosaicCover(covers: p.covers, seed: p.id, radius: 14, width: 640),
      subtitle: p.missingCount > 0
          ? Text(
              '${p.missingCount} şarkı artık kütüphanede yok',
              style: T.faint.copyWith(color: C.danger),
            )
          : null,
      tracks: p.tracks,
      contextName: p.name,
      playlist: p,
      onChanged: reload,
      empty: const Padding(
        padding: EdgeInsets.only(top: 30),
        child: EmptyState(
          icon: Icons.queue_music_rounded,
          title: 'Liste boş',
          message:
              'Şarkıların ⋮ menüsünden "Çalma listesine ekle" ile şarkı ekleyebilirsin.',
        ),
      ),
      actions: [
        CollectionDownloadButton(
          keyName: 'playlist:${p.id}',
          type: 'playlist',
          id: p.id,
          name: p.name,
          subtitle: 'Çalma listesi',
          tracks: p.tracks,
        ),
        IconButton(
          tooltip: 'Düzenle',
          icon: const Icon(Icons.edit_note_rounded, size: 30, color: C.textDim),
          onPressed: p.tracks.isEmpty
              ? null
              : () async {
                  final changed =
                      await Navigator.of(
                        context,
                        rootNavigator: true,
                      ).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => PlaylistEditor(playlist: p),
                          fullscreenDialog: true,
                        ),
                      );
                  if (changed == true) await reload();
                },
        ),
      ],
      topActions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded),
          color: C.raisedTop,
          onSelected: (v) async {
            switch (v) {
              case 'rename':
                final name = await askText(
                  context,
                  title: 'Adını değiştir',
                  initial: p.name,
                );
                if (name == null || name == p.name) return;
                final r = await app.call((a) => a.renamePlaylist(p.id, name));
                if (r != null) {
                  dl.collection('playlist:${p.id}')?.name = name;
                  dl.updated();
                  app.refreshPlaylists();
                  app.libraryVersion.value++;
                  setState(() => _k++);
                }
              case 'delete':
                final ok = await confirm(
                  context,
                  title: '"${p.name}" silinsin mi?',
                  message:
                      'Şarkılar kütüphanede kalır, yalnızca liste silinir.',
                );
                if (!ok) return;
                if (await app.deletePlaylist(p)) {
                  await dl.removeCollection('playlist:${p.id}');
                  if (context.mounted) Navigator.maybePop(context);
                }
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'rename', child: Text('Adını değiştir')),
            PopupMenuItem(
              value: 'delete',
              child: Text('Listeyi sil', style: TextStyle(color: C.danger)),
            ),
          ],
        ),
      ],
    );
  }
}

/// Reorder / remove songs of a playlist.
class PlaylistEditor extends StatefulWidget {
  final Playlist playlist;
  const PlaylistEditor({super.key, required this.playlist});
  @override
  State<PlaylistEditor> createState() => _PlaylistEditorState();
}

class _PlaylistEditorState extends State<PlaylistEditor> {
  late final List<Track> _tracks = List.of(widget.playlist.tracks);
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    final app = context.read<AppState>();
    // songs missing from the library stay in the list
    final known = {for (final t in widget.playlist.tracks) t.id};
    final missing = widget.playlist.trackIds.where((id) => !known.contains(id));
    final ids = [..._tracks.map((t) => t.id), ...missing];
    final r = await app.call(
      (a) => a.setPlaylistTracks(widget.playlist.id, ids),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (r != null) {
      final dl = context.read<Downloads>();
      final dc = dl.collection('playlist:${widget.playlist.id}');
      if (dc != null) {
        dc.trackIds = ids;
        dl.updated();
      }
      app.refreshPlaylists();
      app.libraryVersion.value++;
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.playlist.name),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Kaydet'),
            ),
          ),
        ],
      ),
      body: ReorderableListView.builder(
        padding: const EdgeInsets.only(bottom: 40),
        itemCount: _tracks.length,
        onReorderItem: (from, to) {
          setState(() {
            final t = _tracks.removeAt(from);
            _tracks.insert(to, t);
          });
        },
        itemBuilder: (context, i) {
          final t = _tracks[i];
          return ListTile(
            key: ValueKey('${t.id}#$i'),
            contentPadding: const EdgeInsets.only(left: 4, right: 8),
            leading: IconButton(
              icon: const Icon(Icons.remove_circle_rounded, color: C.danger),
              tooltip: 'Çıkar',
              onPressed: () => setState(() => _tracks.removeAt(i)),
            ),
            title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              t.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.dim,
            ),
            trailing: ReorderableDragStartListener(
              index: i,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.drag_handle_rounded, color: C.textDim),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _OfflinePlaylist extends StatelessWidget {
  final String id;
  final String name;
  const _OfflinePlaylist({required this.id, required this.name});
  @override
  Widget build(BuildContext context) {
    final dl = context.watch<Downloads>();
    final c = dl.collection('playlist:$id');
    final tracks = c == null ? <Track>[] : dl.collectionTracks(c);
    if (tracks.isEmpty) {
      return const EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Çevrimdışı',
        message:
            'Bu liste indirilmemiş. Listeyi indirirsen sunucu olmadan da dinleyebilirsin.',
      );
    }
    return CollectionView(
      kicker: 'ÇALMA LİSTESİ • İNDİRİLENLER',
      title: c?.name ?? name,
      cover: MosaicCover(
        covers: [for (final t in tracks.take(4)) t.cover],
        seed: id,
        radius: 14,
        width: 640,
      ),
      tracks: tracks,
      contextName: c?.name ?? name,
    );
  }
}
