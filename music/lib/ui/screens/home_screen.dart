import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/downloads.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../state/app_state.dart';
import '../nav.dart';
import '../neu.dart';
import '../theme.dart';
import '../widgets/art.dart';
import '../widgets/collection.dart';
import '../widgets/common.dart';
import '../widgets/profile_button.dart';
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
        MediaQuery.paddingOf(context).top + 10,
        12,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'HOME MÜZİK',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.4,
                    color: C.text,
                  ),
                ),
              ),
              NeuIconButton(
                Icons.settings_outlined,
                plain: true,
                size: 40,
                iconSize: 22,
                tooltip: 'Ayarlar',
                onTap: () => ShellNav.push(const SettingsScreen()),
              ),
              const SizedBox(width: 2),
              const ProfileButton(),
              const SizedBox(width: 4),
            ],
          ),
          const SizedBox(height: 16),
          Text(greeting(), style: T.h1),
          const SizedBox(height: 2),
          Text(
            app.profile == null
                ? 'Bugün senin için seçtiklerimiz'
                : '${app.profile!.name}, bugün senin için seçtiklerimiz',
            style: T.dim,
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
              const FadeSlideIn(child: MixHero()),
              for (final r in d.rows)
                if (r.items.isNotEmpty)
                  HorizontalRow(
                    title: r.title,
                    count: r.items.length,
                    action: r.items.length > 3 ? 'Tümünü Gör' : null,
                    onAction: () => ShellNav.push(HomeRowScreen(row: r)),
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

/// "Sana Özel Mix": big card that plays a fresh mix from the server.
class MixHero extends StatefulWidget {
  const MixHero({super.key});
  @override
  State<MixHero> createState() => _MixHeroState();
}

class _MixHeroState extends State<MixHero> {
  bool _busy = false;

  Future<void> _play() async {
    if (_busy) return;
    setState(() => _busy = true);
    final app = context.read<AppState>();
    final tracks = await app.call((a) => a.mix());
    if (!mounted) return;
    setState(() => _busy = false);
    if (tracks == null || tracks.isEmpty) return;
    await playList(context, tracks, name: 'Sana Özel Mix');
  }

  @override
  Widget build(BuildContext context) {
    final seed = 'mix${DateTime.now().day}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: PressScale(
        onTap: _play,
        child: AspectRatio(
          aspectRatio: 1.9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: GradientArt(
              seed,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.55),
                    ],
                    stops: const [0.35, 1],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sana Özel Mix',
                              style: TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Sevdiğin sanatçılardan ve türlerden, her seferinde yeni bir karışım.',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Color(0xDDFFFFFF),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: _busy
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                ),
                              )
                            : const Icon(
                                Icons.play_arrow_rounded,
                                color: C.accent,
                                size: 30,
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Tümünü Gör" of a home row: every card in a grid.
class HomeRowScreen extends StatelessWidget {
  final HomeRow row;
  const HomeRowScreen({super.key, required this.row});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SubPage(
        title: row.title,
        child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 150),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 180,
            mainAxisSpacing: 18,
            crossAxisSpacing: 16,
            childAspectRatio: 0.74,
          ),
          itemCount: row.items.length,
          itemBuilder: (context, i) => LayoutBuilder(
            builder: (context, c) => HomeCardTile(
              card: row.items[i],
              siblings: row.items,
              rowTitle: row.title,
              width: c.maxWidth,
            ),
          ),
        ),
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
