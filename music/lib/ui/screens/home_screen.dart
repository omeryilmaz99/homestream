import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/downloads.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../state/app_state.dart';
import '../nav.dart';
import '../neu.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/rows.dart';
import '../widgets/track_tile.dart';
import 'downloads_screen.dart';
import 'settings_screen.dart';

Color parseHex(String hex, [Color fallback = C.accent]) {
  var h = hex.replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return v == null ? fallback : Color(v);
}

class ProfileAvatar extends StatelessWidget {
  final Profile? profile;
  final double size;
  const ProfileAvatar({super.key, required this.profile, this.size = 40});
  @override
  Widget build(BuildContext context) {
    final p = profile;
    final c = parseHex(p?.color ?? '');
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c, Color.lerp(c, Colors.black, 0.45)!],
        ),
        boxShadow: neuShadows(depth: 0.5),
      ),
      alignment: Alignment.center,
      child: Text(
        p == null
            ? '?'
            : p.avatar.isNotEmpty
            ? p.avatar
            : (p.name.isEmpty ? '?' : p.name.characters.first.toUpperCase()),
        style: TextStyle(
          fontSize: size * 0.48,
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final header = Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.paddingOf(context).top + 14,
        16,
        4,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(greeting(), style: T.h1),
                if (app.profile != null) Text(app.profile!.name, style: T.dim),
              ],
            ),
          ),
          NeuIconButton(
            Icons.settings_rounded,
            size: 42,
            iconSize: 20,
            tooltip: 'Ayarlar',
            onTap: () => ShellNav.push(const SettingsScreen()),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => ShellNav.push(const SettingsScreen()),
            child: ProfileAvatar(profile: app.profile, size: 42),
          ),
        ],
      ),
    );
    return Scaffold(
      body: DataView<HomeData>(
        load: (api) => api.home(),
        offline: _OfflineHome(header: header),
        builder: (context, d, _) {
          if (d.trackCount == 0) {
            return ListView(
              children: [
                header,
                const SizedBox(height: 60),
                const EmptyState(
                  icon: Icons.library_music_rounded,
                  title: 'Kütüphane boş',
                  message:
                      'Sunucudaki müzik klasörüne şarkı ekle ya da Ayarlar > Sunucu ayarları bölümünden yeni bir klasör seç. '
                      'Tarama bitince şarkılar burada görünür.',
                ),
              ],
            );
          }
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.only(bottom: 150),
            children: [
              header,
              if (d.quick.isNotEmpty) _QuickGrid(cards: d.quick),
              for (final r in d.rows)
                if (r.items.isNotEmpty)
                  HorizontalRow(
                    title: r.title,
                    count: r.items.length,
                    height: 212,
                    itemBuilder: (context, i) => HomeCardTile(
                      card: r.items[i],
                      siblings: r.items,
                      rowTitle: r.title,
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

/// The 2-column shortcut tiles at the top (like Spotify).
class _QuickGrid extends StatelessWidget {
  final List<HomeCard> cards;
  const _QuickGrid({required this.cards});
  @override
  Widget build(BuildContext context) {
    final list = cards.take(8).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
      child: LayoutBuilder(
        builder: (context, c) {
          final w = (c.maxWidth - 14) / 2;
          return Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (var i = 0; i < list.length; i++)
                FadeSlideIn(
                  index: i,
                  child: SizedBox(
                    width: w,
                    height: 58,
                    child: NeuButton(
                      radius: 12,
                      depth: 0.7,
                      onTap: () =>
                          openHomeCard(context, list[i], siblings: list),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 58,
                            height: 58,
                            child: ClipRRect(
                              borderRadius: const BorderRadius.horizontal(
                                left: Radius.circular(12),
                              ),
                              child: homeCardCover(
                                list[i],
                                radius: 0,
                                width: 160,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              list[i].title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: C.text,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Without the server: the downloaded music.
class _OfflineHome extends StatelessWidget {
  final Widget header;
  const _OfflineHome({required this.header});
  @override
  Widget build(BuildContext context) {
    final dl = context.watch<Downloads>();
    final tracks = dl.tracks;
    final cols = dl.collections;
    return ListView(
      padding: const EdgeInsets.only(bottom: 150),
      children: [
        header,
        if (tracks.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 60),
            child: EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Sunucuya bağlanılamıyor',
              message:
                  'Aynı ağda olduğundan ve sunucunun açık olduğundan emin ol. '
                  'Şarkı indirirsen bağlantı olmadan da dinleyebilirsin.',
            ),
          )
        else ...[
          if (cols.isNotEmpty)
            HorizontalRow(
              title: 'İndirilen listeler',
              count: cols.length,
              itemBuilder: (context, i) {
                final c = cols[i];
                return MediaCard(
                  cover: collectionCover(c, dl.collectionTracks(c), radius: 12),
                  title: c.name,
                  subtitle: songCount(dl.collectionTracks(c).length),
                  onTap: () => ShellNav.push(
                    DownloadedCollectionScreen(collectionKey: c.key),
                  ),
                );
              },
            ),
          SectionHeader(
            'İndirilen şarkılar',
            action: 'Tümü',
            onAction: () => ShellNav.push(const DownloadsScreen()),
          ),
          for (var i = 0; i < tracks.length && i < 30; i++)
            TrackTile(
              track: tracks[i],
              onTap: () =>
                  playList(context, tracks, index: i, name: 'İndirilenler'),
            ),
        ],
      ],
    );
  }
}
