import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../audio/handler.dart';
import '../../core/downloads.dart';
import '../../core/format.dart';
import '../../core/image_cache.dart';
import '../../core/platform.dart';
import '../../state/app_state.dart';
import '../nav.dart';
import '../neu.dart';
import '../theme.dart';
import '../track_menu.dart';
import '../widgets/collection.dart';
import '../widgets/common.dart';
import 'downloads_screen.dart';
import 'home_screen.dart' show ProfileAvatar;
import 'server_settings_screen.dart';

const appVersion = '1.0.0';

/// Device settings: no password, they only change this phone.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int? _dlBytes;
  int? _cacheBytes;
  bool? _battery;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    final dl = context.read<Downloads>();
    final a = await dl.diskUsage();
    final b = await DiskCache.sizeBytes();
    final c = await AppPlatform.ignoringBatteryOptimizations();
    if (!mounted) return;
    setState(() {
      _dlBytes = a;
      _cacheBytes = b;
      _battery = c;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final dl = context.watch<Downloads>();
    final s = app.player.settings;
    final p = app.profile;
    final remembered =
        app.server != null &&
        app.prefs.rememberedProfile(app.server!.id) == p?.id;

    return Scaffold(
      body: SubPage(
        title: 'Ayarlar',
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 150),
          children: [
            // ---- profile ----
            NeuBox(
              radius: 20,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      ProfileAvatar(profile: p, size: 52),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p?.name ?? '', style: T.h3),
                            const SizedBox(height: 2),
                            Text(
                              '${app.server?.name ?? ''} • ${app.online ? 'bağlı' : 'çevrimdışı'}',
                              style: T.faint,
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: app.switchProfile,
                        child: const Text('Değiştir'),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Beni hatırla', style: T.body),
                    subtitle: const Text(
                      'Uygulama açılınca profil sorulmaz',
                      style: T.faint,
                    ),
                    value: remembered,
                    onChanged: p == null || app.server == null
                        ? null
                        : (v) {
                            app.prefs.setRememberedProfile(
                              app.server!.id,
                              v ? p.id : null,
                            );
                            setState(() {});
                          },
                  ),
                ],
              ),
            ),

            // ---- playback ----
            const _Header('Çalma'),
            _Card(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Şarkılar arası yumuşak geçiş',
                    style: T.body,
                  ),
                  subtitle: Text(
                    s.crossfade == 0 ? 'Kapalı' : '${s.crossfade} saniye',
                    style: T.faint,
                  ),
                ),
                Slider(
                  value: s.crossfade.toDouble(),
                  min: 0,
                  max: 12,
                  divisions: 12,
                  label: s.crossfade == 0 ? 'Kapalı' : '${s.crossfade} sn',
                  onChanged: (v) {
                    s.crossfade = v.round();
                    setState(() {});
                  },
                  onChangeEnd: (_) => app.applyPlayerSettings(),
                ),
                _Switch(
                  title: 'Akıllı geçiş',
                  subtitle:
                      'Aynı albümün şarkıları arasında geçiş yapılmaz (canlı albümler, kesintisiz kayıtlar)',
                  value: s.smartCrossfade,
                  onChanged: s.crossfade == 0
                      ? null
                      : (v) {
                          s.smartCrossfade = v;
                          app.applyPlayerSettings();
                        },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ses seviyesini eşitle', style: T.body),
                  subtitle: const Text(
                    'Dosyadaki ReplayGain bilgisini kullanır',
                    style: T.faint,
                  ),
                  trailing: DropdownButton<String>(
                    value: s.replayGain,
                    underline: const SizedBox.shrink(),
                    dropdownColor: C.raisedTop,
                    items: const [
                      DropdownMenuItem(value: 'off', child: Text('Kapalı')),
                      DropdownMenuItem(value: 'track', child: Text('Şarkı')),
                      DropdownMenuItem(value: 'album', child: Text('Albüm')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      s.replayGain = v;
                      app.applyPlayerSettings();
                    },
                  ),
                ),
                _Switch(
                  title: 'Yüksek kaliteli ses çıkışı',
                  subtitle:
                      'Kayıpsız ve Hi-Res dosyalar için 32-bit kayan nokta çıkış. Ses sorunu olursa kapat.',
                  value: s.hiFi,
                  onChanged: (v) {
                    s.hiFi = v;
                    app.applyPlayerSettings();
                  },
                ),
                _Switch(
                  title: 'Kulaklık çıkınca duraklat',
                  subtitle:
                      'Kablolu ya da Bluetooth kulaklık ayrılınca müzik durur',
                  value: s.pauseOnUnplug,
                  onChanged: (v) {
                    s.pauseOnUnplug = v;
                    app.applyPlayerSettings();
                  },
                ),
              ],
            ),

            // ---- downloads ----
            const _Header('İndirilenler'),
            _Card(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.download_done_rounded),
                  title: const Text('İndirilenler', style: T.body),
                  subtitle: Text(
                    '${songCount(dl.tracks.length)} • ${_dlBytes == null ? '…' : formatSize(_dlBytes!)}'
                    '${dl.activeCount > 0 ? ' • ${dl.activeCount} indiriliyor' : ''}',
                    style: T.faint,
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => ShellNav.push(const DownloadsScreen()),
                ),
                _Switch(
                  title: 'İndirilen kopyayı çal',
                  subtitle:
                      'Bağlıyken de indirilen dosya kullanılır (daha az ağ, anında başlar)',
                  value: app.prefs.preferDownloads,
                  onChanged: (v) {
                    app.prefs.preferDownloads = v;
                    setState(() {});
                  },
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: C.danger,
                      side: BorderSide(color: C.danger.withValues(alpha: 0.6)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.delete_forever_rounded),
                    label: const Text('İndirilenleri sil'),
                    onPressed: () async {
                      final ok = await confirm(
                        context,
                        title: 'Tüm indirilenler silinsin mi?',
                        message:
                            'Bu telefondaki bütün indirilen şarkılar (tüm sunucular için) silinir. '
                            'Şarkılar sunucuda kalır, istediğin zaman tekrar indirebilirsin.',
                        ok: 'Hepsini sil',
                      );
                      if (!ok || !context.mounted) return;
                      final player = context.read<MusicHandler>();
                      final cur = player.current.value;
                      // a downloaded song that is playing offline can't continue
                      if (cur != null &&
                          dl.isDownloaded(cur.id) &&
                          !app.online) {
                        await player.pause();
                      }
                      await dl.removeAll();
                      await _measure();
                      if (context.mounted) {
                        showToast(context, 'İndirilenler silindi');
                      }
                    },
                  ),
                ),
                const SizedBox(height: 6),
              ],
            ),

            // ---- storage & app ----
            const _Header('Uygulama'),
            _Card(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.image_outlined),
                  title: const Text('Kapak önbelleğini temizle', style: T.body),
                  subtitle: Text(
                    _cacheBytes == null ? '…' : formatSize(_cacheBytes!),
                    style: T.faint,
                  ),
                  onTap: () async {
                    await DiskCache.clear();
                    PaintingBinding.instance.imageCache.clear();
                    await _measure();
                    if (context.mounted) {
                      showToast(context, 'Önbellek temizlendi');
                    }
                  },
                ),
                _Switch(
                  title: 'Hareketli arka plan',
                  subtitle:
                      'Çalma ekranındaki renk animasyonu (kapatmak pil tasarrufu sağlar)',
                  value: app.prefs.animations,
                  onChanged: (v) {
                    app.prefs.animations = v;
                    setState(() {});
                  },
                ),
                if (AppPlatform.isAndroid)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      _battery == true
                          ? Icons.battery_full_rounded
                          : Icons.battery_alert_rounded,
                      color: _battery == true ? C.accent : C.textDim,
                    ),
                    title: const Text(
                      'Arka planda kesintisiz çalma',
                      style: T.body,
                    ),
                    subtitle: Text(
                      _battery == true
                          ? 'Pil kısıtlaması kapalı'
                          : 'Ekran kapalıyken durmaması için izin ver',
                      style: T.faint,
                    ),
                    onTap: _battery == true
                        ? null
                        : () async {
                            await AppPlatform.requestIgnoreBatteryOptimizations();
                            await Future.delayed(const Duration(seconds: 1));
                            await _measure();
                          },
                  ),
              ],
            ),

            // ---- server (password) ----
            const _Header('Sunucu'),
            _Card(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.admin_panel_settings_outlined),
                  title: const Text('Sunucu ayarları', style: T.body),
                  subtitle: const Text(
                    'Müzik klasörleri, tarama, kapaklar • şifre gerekir',
                    style: T.faint,
                  ),
                  trailing: const Icon(Icons.lock_outline_rounded, size: 18),
                  onTap: () async {
                    if (!app.online) {
                      showToast(context, 'Sunucuya bağlı değilsin');
                      return;
                    }
                    if (await ensureAdmin(context) && context.mounted) {
                      ShellNav.push(const ServerSettingsScreen());
                    }
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.dns_outlined),
                  title: const Text('Sunucuyu değiştir', style: T.body),
                  subtitle: Text(app.server?.url ?? '', style: T.faint),
                  onTap: app.openSetup,
                ),
              ],
            ),
            const SizedBox(height: 26),
            Center(child: Text('Home Müzik $appVersion', style: T.faint)),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 26, 6, 10),
    child: Text(
      text.toUpperCase(),
      style: T.faint.copyWith(letterSpacing: 1.6, fontWeight: FontWeight.w800),
    ),
  );
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});
  @override
  Widget build(BuildContext context) => NeuBox(
    radius: 20,
    depth: 0.8,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    child: Column(children: children),
  );
}

class _Switch extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  const _Switch({
    required this.title,
    required this.subtitle,
    required this.value,
    this.onChanged,
  });
  @override
  Widget build(BuildContext context) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title, style: T.body),
    subtitle: Text(subtitle, style: T.faint),
    value: value,
    onChanged: onChanged,
  );
}
