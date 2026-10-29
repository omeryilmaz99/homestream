import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/downloads.dart';
import '../../core/models.dart';
import '../../state/app_state.dart';
import '../nav.dart';
import '../neu.dart';
import '../theme.dart';
import '../widgets/collection.dart';
import '../widgets/common.dart';
import '../widgets/rows.dart';
import '../widgets/track_tile.dart';
import 'home_screen.dart' show ProfileAvatar;
import 'liked_screen.dart';
import 'settings_screen.dart';

/// Profile page (from the picture at the top right): who is listening, listening numbers, favourite artists and
/// the last songs played.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final header = _Header(app: app);
    return Scaffold(
      body: ValueListenableBuilder<Set<String>>(
        valueListenable: app.liked,
        builder: (context, liked, _) => DataView<ProfileStats>(
          reloadKey: liked.length,
          load: (api) => api.stats(),
          offline: ListView(
            padding: const EdgeInsets.only(bottom: 150),
            children: [header, const _OfflineStats()],
          ),
          builder: (context, st, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.only(bottom: 150),
            children: [
              header,
              _StatsRow(
                items: [
                  (formatCompact(st.plays), 'Toplam Çalma'),
                  (formatCompact(st.minutes), 'Dakika'),
                  (formatCompact(st.liked), 'Beğenilen Şarkı'),
                ],
                onTap: [null, null, () => ShellNav.push(const LikedScreen())],
              ),
              if (st.topArtists.isNotEmpty)
                HorizontalRow(
                  title: 'En Çok Dinlediğin Sanatçılar',
                  count: st.topArtists.length,
                  height: 140,
                  action: st.topArtists.length > 4 ? 'Tümünü Gör' : null,
                  onAction: () =>
                      ShellNav.push(_ArtistsPage(artists: st.topArtists)),
                  itemBuilder: (context, i) => ArtistCard(
                    artist: st.topArtists[i],
                    width: 84,
                    subtitle: '',
                  ),
                ),
              if (st.recent.isNotEmpty) ...[
                const SectionHeader('Son Dinlediklerin'),
                for (var i = 0; i < st.recent.length && i < 10; i++)
                  TrackTile(
                    track: st.recent[i],
                    onTap: () => playList(
                      context,
                      st.recent,
                      index: i,
                      name: 'Son Dinlediklerin',
                    ),
                  ),
              ],
              if (st.plays == 0)
                const Padding(
                  padding: EdgeInsets.fromLTRB(32, 30, 32, 0),
                  child: Text(
                    'Dinledikçe en sevdiğin sanatçılar ve son çaldıkların burada görünür.',
                    style: T.dim,
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 1234 → "1.234", 12800 → "12,8B", 2500000 → "2,5Mn".
String formatCompact(int n) {
  String one(double v) {
    final s = v.toStringAsFixed(v >= 100 ? 0 : 1).replaceAll('.', ',');
    return s.endsWith(',0') ? s.substring(0, s.length - 2) : s;
  }

  if (n >= 1000000) return '${one(n / 1000000)}Mn';
  if (n >= 10000) return '${one(n / 1000)}B';
  if (n >= 1000) {
    final s = '$n';
    return '${s.substring(0, s.length - 3)}.${s.substring(s.length - 3)}';
  }
  return '$n';
}

class _Header extends StatelessWidget {
  final AppState app;
  const _Header({required this.app});
  @override
  Widget build(BuildContext context) {
    final p = app.profile;
    final top = MediaQuery.paddingOf(context).top;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, top + 6, 8, 8),
      child: Column(
        children: [
          Row(
            children: [
              if (Navigator.of(context).canPop()) ...[
                Transform.translate(
                  offset: const Offset(-10, 0),
                  child: NeuIconButton(
                    Icons.arrow_back_ios_new_rounded,
                    plain: true,
                    size: 40,
                    iconSize: 19,
                    tooltip: 'Geri',
                    onTap: () => Navigator.maybePop(context),
                  ),
                ),
              ],
              const Expanded(child: Text('Profil', style: T.h1)),
              NeuIconButton(
                Icons.settings_outlined,
                plain: true,
                size: 42,
                iconSize: 23,
                tooltip: 'Ayarlar',
                onTap: () => ShellNav.push(const SettingsScreen()),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: accentGradient,
                ),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: C.bg,
                  ),
                  child: ProfileAvatar(profile: p, size: 70),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p?.name ?? '',
                      style: T.h2.copyWith(fontSize: 21),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${app.server?.name ?? ''} • ${app.online ? 'bağlı' : 'çevrimdışı'}',
                      style: T.faint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: app.switchProfile,
                      child: const Text('Profili değiştir', style: T.link),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final List<(String, String)> items;
  final List<VoidCallback?> onTap;
  const _StatsRow({required this.items, this.onTap = const []});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: NeuBox(
        radius: 16,
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) Container(width: 1, height: 30, color: C.divider),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: i < onTap.length ? onTap[i] : null,
                  child: Column(
                    children: [
                      Text(
                        items[i].$1,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: C.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(items[i].$2, style: T.faint),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OfflineStats extends StatelessWidget {
  const _OfflineStats();
  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final dl = context.watch<Downloads>();
    return Column(
      children: [
        _StatsRow(
          items: [
            (formatCompact(dl.tracks.length), 'İndirilen Şarkı'),
            (formatCompact(app.liked.value.length), 'Beğenilen Şarkı'),
          ],
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(32, 30, 32, 0),
          child: Text(
            'Çevrimdışısın. Dinleme istatistiklerin bağlantı gelince görünür.',
            style: T.dim,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class _ArtistsPage extends StatelessWidget {
  final List<Artist> artists;
  const _ArtistsPage({required this.artists});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SubPage(
        title: 'En Çok Dinlediğin Sanatçılar',
        child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 150),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 130,
            mainAxisSpacing: 16,
            crossAxisSpacing: 14,
            childAspectRatio: 0.78,
          ),
          itemCount: artists.length,
          itemBuilder: (context, i) => LayoutBuilder(
            builder: (context, c) =>
                ArtistCard(artist: artists[i], width: c.maxWidth),
          ),
        ),
      ),
    );
  }
}
