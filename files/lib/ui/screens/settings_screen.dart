import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/platform.dart';
import '../../core/prefs.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'connect_screen.dart';

const appVersion = '1.0.0';

/// Device settings (this computer / phone only).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = app.prefs;
    final wide = MediaQuery.sizeOf(context).width >= 860;
    void set(VoidCallback f) {
      f();
      setState(() {});
    }

    return ListView(
      padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 16, vertical: 12),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const GradientText('Ayarlar', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('Bu ayarlar yalnızca bu cihazı etkiler.', style: TextStyle(color: C.muted)),
                const SectionTitle('Bu cihaz'),
                SoftCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: Icon(AppPlatform.isAndroid ? Icons.smartphone_rounded : Icons.computer_rounded, color: C.teal),
                    title: const Text('Cihaz adı'),
                    subtitle: Text('${app.deviceName}\nSunucunun "Bağlı cihazlar" listesinde böyle görünür (yeni girişlerde).'),
                    isThreeLine: true,
                    trailing: const Icon(Icons.edit_rounded, color: C.muted),
                    onTap: () async {
                      final v = await prompt(context, title: 'Cihaz adı', initial: app.deviceName);
                      if (v != null) app.setDeviceName(v);
                    },
                  ),
                ),
                const SectionTitle('Sunucular'),
                SoftCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      for (final s in app.servers) _serverTile(app, s),
                      ListTile(
                        leading: const Icon(Icons.add_rounded, color: C.teal),
                        title: const Text('Sunucu ekle / değiştir'),
                        onTap: () => openServerPicker(context),
                      ),
                    ],
                  ),
                ),
                const SectionTitle('Aktarım'),
                SoftCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.call_split_rounded, color: C.teal),
                        title: const Text('Aynı anda aktarılan dosya'),
                        subtitle: const Text('Çok sayıda küçük dosyada 3-4 daha hızlıdır.'),
                        trailing: SegmentedButton<int>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(value: 1, label: Text('1')),
                            ButtonSegment(value: 2, label: Text('2')),
                            ButtonSegment(value: 3, label: Text('3')),
                            ButtonSegment(value: 4, label: Text('4')),
                          ],
                          selected: {p.parallel},
                          onSelectionChanged: (v) => set(() => p.parallel = v.first),
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.file_copy_rounded, color: C.teal),
                        title: const Text('Dosya zaten varsa'),
                        trailing: DropdownButton<String>(
                          value: p.conflict,
                          underline: const SizedBox.shrink(),
                          borderRadius: BorderRadius.circular(14),
                          items: const [
                            DropdownMenuItem(value: 'ask', child: Text('Sor')),
                            DropdownMenuItem(value: 'rename', child: Text('İkisini de tut')),
                            DropdownMenuItem(value: 'overwrite', child: Text('Üzerine yaz')),
                            DropdownMenuItem(value: 'skip', child: Text('Atla')),
                          ],
                          onChanged: (v) => set(() => p.conflict = v ?? 'ask'),
                        ),
                      ),
                      SwitchListTile(
                        secondary: const Icon(Icons.verified_rounded, color: C.teal),
                        title: const Text('Aktarımdan sonra doğrula'),
                        subtitle: const Text('Dosyanın bozulmadan geldiğini SHA-256 ile kontrol eder. Büyük dosyalarda biraz sürer.'),
                        value: p.verify,
                        onChanged: (v) => set(() => p.verify = v),
                      ),
                      SwitchListTile(
                        secondary: const Icon(Icons.play_circle_outline_rounded, color: C.teal),
                        title: const Text('Yarım kalanlara açılışta devam et'),
                        subtitle: const Text('Uygulama kapansa da aktarımlar kaldığı yerden sürer.'),
                        value: p.autoResume,
                        onChanged: (v) => set(() => p.autoResume = v),
                      ),
                      SwitchListTile(
                        secondary: const Icon(Icons.history_toggle_off_rounded, color: C.teal),
                        title: const Text('Değiştirilme tarihini koru'),
                        value: p.keepMtime,
                        onChanged: (v) => set(() => p.keepMtime = v),
                      ),
                    ],
                  ),
                ),
                const SectionTitle('Görünüm'),
                SoftCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.visibility_rounded, color: C.teal),
                        title: const Text('Gizli dosyaları göster'),
                        value: p.showHidden,
                        onChanged: (v) => set(() => p.showHidden = v),
                      ),
                      SwitchListTile(
                        secondary: const Icon(Icons.grid_view_rounded, color: C.teal),
                        title: const Text('Izgara görünümü'),
                        value: p.gridView,
                        onChanged: (v) => set(() => p.gridView = v),
                      ),
                      ListTile(
                        leading: const Icon(Icons.history_rounded, color: C.teal),
                        title: const Text('Aktarım geçmişini temizle'),
                        onTap: () async {
                          if (await confirm(context, title: 'Geçmiş temizlensin mi?', text: 'Dosyalar silinmez, sadece liste ve sayaçlar sıfırlanır.', ok: 'Temizle')) {
                            set(() {
                              p.history = [];
                              p.totalSent = 0;
                              p.totalReceived = 0;
                              p.filesSent = 0;
                              p.filesReceived = 0;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SectionTitle('Hakkında'),
                const SoftCard(
                  child: Text(
                    'Home Dosya $appVersion\n'
                    'Home Stream sunucusuyla bilgisayar / telefon arasında dosya aktarımı. '
                    'Aktarımlar yerel ağda şifresiz HTTP ile yapılır; uygulamayı yalnızca ev ağında kullan.',
                    style: TextStyle(color: C.text, height: 1.45),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _serverTile(AppState app, ServerConfig s) {
    final active = app.server?.id == s.id && app.phase == Phase.ready;
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(gradient: active ? C.gradient : null, color: active ? null : C.tint, borderRadius: BorderRadius.circular(12)),
        child: Icon(Icons.dns_rounded, color: active ? Colors.white : C.teal),
      ),
      title: Text(s.name),
      subtitle: Text('${s.url}${app.remembered(s) ? ' · hatırlanıyor' : ''}${active ? ' · bağlı' : ''}'),
      trailing: PopupMenuButton<String>(
        itemBuilder: (_) => [
          if (!active) const PopupMenuItem(value: 'connect', child: Text('Bağlan')),
          const PopupMenuItem(value: 'rename', child: Text('Adını değiştir')),
          const PopupMenuItem(value: 'url', child: Text('Adresi değiştir')),
          if (active) const PopupMenuItem(value: 'logout', child: Text('Oturumu kapat (şifre sorulsun)')),
          const PopupMenuItem(value: 'forget', child: Text('Bu sunucuyu unut')),
        ],
        onSelected: (v) async {
          switch (v) {
            case 'connect':
              if (app.tokenFor(s) != null) {
                app.connect(s);
              } else {
                await showLoginSheet(context, url: s.url, name: s.name);
              }
            case 'rename':
              final n = await prompt(context, title: 'Sunucu adı', initial: s.name);
              if (n != null) app.renameServer(s, n);
            case 'url':
              final u = await prompt(
                context,
                title: 'Sunucu adresi',
                initial: s.url,
                hint: '192.168.1.20',
              );
              if (u != null) {
                s.url = normalizeServerUrl(u);
                app.renameServer(s, s.name);
                app.connect(s);
              }
            case 'logout':
              await app.logout();
            case 'forget':
              if (mounted &&
                  await confirm(context, title: '"${s.name}" unutulsun mu?', text: 'Kayıtlı giriş bu cihazdan silinir.', ok: 'Unut', danger: true)) {
                app.forgetServer(s);
              }
          }
        },
      ),
      onTap: active ? null : () => app.tokenFor(s) != null ? app.connect(s) : showLoginSheet(context, url: s.url, name: s.name),
    );
  }
}
