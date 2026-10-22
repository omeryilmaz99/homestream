import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../audio/handler.dart';
import '../core/downloads.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../state/app_state.dart';
import 'nav.dart';
import 'screens/album_screen.dart';
import 'screens/artist_screen.dart';
import 'screens/folders_screen.dart';
import 'theme.dart';
import 'widgets/common.dart';
import 'widgets/cover.dart';

/// Options of a song (long press / ⋮).
Future<void> showTrackMenu(
  BuildContext context,
  Track t, {
  Playlist? playlist,
  VoidCallback? onRemoved,
  bool fromPlayer = false,
}) {
  final app = context.read<AppState>();
  final dl = context.read<Downloads>();
  final player = context.read<MusicHandler>();
  return showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (ctx) {
      void close() => Navigator.pop(ctx);
      final liked = app.isLiked(t);
      final downloaded = dl.isDownloaded(t.id);
      final queued = dl.task(t.id) != null;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 56,
                        height: 56,
                        child: CoverImage(
                          cover: t.cover,
                          coverId: t.coverId,
                          radius: 8,
                          width: 160,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.title,
                              style: T.h3,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              t.artist,
                              style: T.dim,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (!fromPlayer) ...[
                  _item(Icons.playlist_play_rounded, 'Sıradaki olarak çal', () {
                    close();
                    if (player.current.value == null) {
                      player.playTracks([t]);
                    } else {
                      player.playNext([t]);
                      app.toast('Sıradaki şarkı: ${t.title}');
                    }
                  }),
                  _item(Icons.queue_music_rounded, 'Çalma sırasına ekle', () {
                    close();
                    if (player.current.value == null) {
                      player.playTracks([t]);
                    } else {
                      player.addToQueue([t]);
                      app.toast('Çalma sırasına eklendi');
                    }
                  }),
                ],
                _item(
                  liked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  liked ? 'Beğenilenlerden çıkar' : 'Beğenilenlere ekle',
                  () {
                    close();
                    app.toggleLike(t);
                  },
                  color: liked ? C.accent : null,
                ),
                _item(Icons.playlist_add_rounded, 'Çalma listesine ekle', () {
                  close();
                  showAddToPlaylist(context, [t]);
                }),
                if (playlist != null)
                  _item(
                    Icons.remove_circle_outline_rounded,
                    'Bu listeden çıkar',
                    () async {
                      close();
                      final ids = [...playlist.trackIds]..remove(t.id);
                      final r = await app.call(
                        (a) => a.setPlaylistTracks(playlist.id, ids),
                      );
                      if (r != null) {
                        app.refreshPlaylists();
                        app.libraryVersion.value++;
                        onRemoved?.call();
                      }
                    },
                  ),
                if (downloaded)
                  _item(Icons.delete_outline_rounded, 'İndirileni sil', () {
                    close();
                    dl.remove([t.id]);
                    app.toast('İndirilen şarkı silindi');
                  })
                else if (queued)
                  _item(Icons.cancel_outlined, 'İndirmeyi iptal et', () {
                    close();
                    dl.cancel(t.id);
                  })
                else
                  _item(Icons.download_rounded, 'İndir', () {
                    close();
                    dl.download([t]);
                    app.toast('İndiriliyor: ${t.title}');
                  }),
                if (t.albumId.isNotEmpty)
                  _item(Icons.album_rounded, 'Albüme git', () {
                    close();
                    ShellNav.push(AlbumScreen(id: t.albumId, title: t.album));
                  }),
                if (t.artistId.isNotEmpty)
                  _item(Icons.person_rounded, 'Sanatçıya git', () {
                    close();
                    ShellNav.push(ArtistScreen(id: t.artistId, name: t.artist));
                  }),
                if (t.dir.isNotEmpty)
                  _item(Icons.folder_open_rounded, 'Klasörüne git', () {
                    close();
                    ShellNav.push(FolderScreen(path: t.dir, title: ''));
                  }),
                _item(Icons.info_outline_rounded, 'Şarkı bilgisi', () {
                  close();
                  showTrackInfo(context, t);
                }),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Widget _item(IconData icon, String label, VoidCallback onTap, {Color? color}) {
  return ListTile(
    leading: Icon(icon, color: color ?? C.textDim),
    title: Text(label, style: T.body),
    onTap: onTap,
    contentPadding: const EdgeInsets.symmetric(horizontal: 22),
    visualDensity: const VisualDensity(vertical: -1),
  );
}

void showTrackInfo(BuildContext context, Track t) {
  final rows = <(String, String)>[
    ('Şarkı', t.title),
    if (t.artist.isNotEmpty) ('Sanatçı', t.artist),
    if (t.album.isNotEmpty) ('Albüm', t.album),
    if (t.albumArtist.isNotEmpty && t.albumArtist != t.artist)
      ('Albüm sanatçısı', t.albumArtist),
    if (t.trackNo > 0)
      (
        'Parça',
        t.discNo > 1 ? 'Disk ${t.discNo} • ${t.trackNo}' : '${t.trackNo}',
      ),
    if (t.year > 0) ('Yıl', '${t.year}'),
    if (t.genre.isNotEmpty) ('Tür', t.genre),
    ('Süre', formatDuration(t.duration)),
    if (t.qualityLabel.isNotEmpty) ('Kalite', t.qualityLabel),
    if (t.channels > 0)
      (
        'Kanal',
        t.channels == 1
            ? 'Mono'
            : t.channels == 2
            ? 'Stereo'
            : '${t.channels} kanal',
      ),
    if (t.isVideo) ('Kaynak', 'Video dosyası (yalnızca ses çalınır)'),
    if (t.size > 0) ('Boyut', formatSize(t.size)),
    if (t.path.isNotEmpty) ('Dosya', t.path),
    if (t.playCount > 0) ('Dinlenme', '${t.playCount} kez'),
  ];
  showDialog(
    context: context,
    useRootNavigator: true,
    builder: (ctx) => AlertDialog(
      title: const Text('Şarkı bilgisi'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 110, child: Text(r.$1, style: T.dim)),
                    Expanded(child: SelectableText(r.$2, style: T.body)),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Kapat'),
        ),
      ],
    ),
  );
}

/// Asks for a short text (playlist names).
Future<String?> askText(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '',
  String ok = 'Kaydet',
}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) {
      void submit() {
        final v = c.text.trim();
        if (v.isNotEmpty) Navigator.pop(ctx, v);
      }

      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: 80,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: hint, counterText: ''),
          onSubmitted: (_) => submit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
          FilledButton(onPressed: submit, child: Text(ok)),
        ],
      );
    },
  );
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  String? message,
  String ok = 'Sil',
  bool danger = true,
}) async {
  final r = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message, style: T.dim),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(
                  backgroundColor: C.danger,
                  foregroundColor: Colors.white,
                )
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Playlist picker: adds songs to a list, or to a new one.
Future<void> showAddToPlaylist(BuildContext context, List<Track> tracks) async {
  final app = context.read<AppState>();
  if (!app.online) {
    app.toast('Çalma listesi için sunucuya bağlı olmalısın');
    return;
  }
  await app.refreshPlaylists();
  if (!context.mounted) return;
  await showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.75,
        ),
        child: ValueListenableBuilder<List<Playlist>>(
          valueListenable: app.playlists,
          builder: (ctx, lists, _) => ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(22, 0, 22, 10),
                child: Text('Çalma listesine ekle', style: T.h3),
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: C.bgDeep,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    color: C.accent,
                    size: 28,
                  ),
                ),
                title: const Text('Yeni çalma listesi', style: T.body),
                onTap: () async {
                  final name = await askText(
                    ctx,
                    title: 'Yeni çalma listesi',
                    hint: 'Liste adı',
                    ok: 'Oluştur',
                  );
                  if (name == null) return;
                  if (ctx.mounted) Navigator.pop(ctx);
                  await app.createPlaylist(name, tracks);
                },
              ),
              for (final p in lists)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  leading: SizedBox(
                    width: 48,
                    height: 48,
                    child: MosaicCover(
                      covers: p.covers,
                      seed: p.id,
                      radius: 8,
                      width: 150,
                    ),
                  ),
                  title: Text(
                    p.name,
                    style: T.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(songCount(p.trackCount), style: T.dim),
                  onTap: () {
                    Navigator.pop(ctx);
                    app.addToPlaylist(p, tracks);
                  },
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Download button state of a group of songs.
class CollectionDownloadButton extends StatelessWidget {
  final String keyName; // download collection key
  final String type;
  final String id;
  final String name;
  final String subtitle;
  final List<Track> tracks;
  const CollectionDownloadButton({
    super.key,
    required this.keyName,
    required this.type,
    required this.id,
    required this.name,
    this.subtitle = '',
    required this.tracks,
  });

  @override
  Widget build(BuildContext context) {
    final dl = context.watch<Downloads>();
    final ids = tracks.map((t) => t.id).toList();
    final saved = dl.collection(keyName) != null;
    final all = dl.allDownloaded(ids);
    final busy = dl.anyQueued(ids);
    final progress = dl.progressOf(ids);
    Widget icon;
    if (all && saved) {
      icon = Container(
        width: 26,
        height: 26,
        decoration: const BoxDecoration(
          color: C.accent,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.arrow_downward_rounded,
          color: Colors.black,
          size: 18,
        ),
      );
    } else if (busy) {
      icon = SizedBox(
        width: 26,
        height: 26,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: progress > 0 ? progress : null,
              strokeWidth: 2.5,
              backgroundColor: C.bgDeep,
            ),
            const Icon(Icons.stop_rounded, size: 14, color: C.textDim),
          ],
        ),
      );
    } else {
      icon = const Icon(
        Icons.download_for_offline_outlined,
        size: 30,
        color: C.textDim,
      );
    }
    return IconButton(
      tooltip: all && saved
          ? 'İndirildi'
          : busy
          ? 'İndiriliyor'
          : 'İndir',
      icon: icon,
      onPressed: tracks.isEmpty
          ? null
          : () async {
              if (busy) {
                if (await confirm(
                  context,
                  title: 'İndirme durdurulsun mu?',
                  ok: 'Durdur',
                )) {
                  for (final id in ids) {
                    dl.cancel(id);
                  }
                }
                return;
              }
              if (all && saved) {
                if (!context.mounted) return;
                final ok = await confirm(
                  context,
                  title: 'İndirilenler silinsin mi?',
                  message: '"$name" artık çevrimdışı dinlenemeyecek.',
                );
                if (ok) await dl.removeCollection(keyName);
                return;
              }
              dl.download(
                tracks,
                collection: DownloadCollection(
                  key: keyName,
                  type: type,
                  id: id,
                  name: name,
                  subtitle: subtitle,
                  trackIds: ids,
                  at: DateTime.now().millisecondsSinceEpoch,
                ),
              );
              if (context.mounted) {
                showToast(context, '${tracks.length} şarkı indiriliyor');
              }
            },
    );
  }
}
