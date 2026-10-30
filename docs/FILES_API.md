# Dosya API

Home Dosya uygulamasının kullandığı uç noktalar. Sunucu aynıdır (port 8420). Yanıtlar JSON'dur;
hata yanıtları `{"error": "Türkçe açıklama"}` biçimindedir.

## Oturum

Giriş, sunucunun **ayarlar (yönetici) şifresiyle** yapılır. Başarılı girişte uzun ömürlü bir
belirteç (token) döner; uygulama "Beni hatırla" açıksa bunu saklar ve bir daha şifre sormaz.
Sunucu belirteci yalnızca SHA-256 özeti olarak tutar.

- Her istekte `Authorization: Bearer <token>` (indirme / küçük resim bağlantılarında `?token=` da olur).
- Belirteç geçersizse `401`; uygulama giriş ekranına döner.
- Üst üste 5 yanlış şifreden sonra giriş 30 sn kilitlenir, her yeni hatada süre ikiye katlanır (en fazla 15 dk), `429`.

| İstek | Açıklama |
|---|---|
| `POST /api/files/login` `{password, device, platform}` | `{token, session, server}` |
| `POST /api/files/logout` | bu oturumu kapatır |
| `GET /api/files/session` | oturum bilgisi + tüm bağlı cihazlar (`online`, `current`) |
| `DELETE /api/files/sessions/{id}` | başka bir cihazın oturumunu kapatır (o cihaza canlı `revoked` olayı gider) |

## Gezinme

Yollar sunucudaki mutlak yollardır (`/home/omer/HomeStream/...`).

| İstek | Açıklama |
|---|---|
| `GET /api/files/roots` | kısayollar: ev klasörü, HomeStream kütüphanesi, eklenen klasörler, takılı diskler, `/`; her biri `total/free` ile |
| `GET /api/files/list?path=&hidden=1` | klasör içeriği (`name, path, dir, size, mtime, count, ...`) + klasörün `free/writable` bilgisi |
| `GET /api/files/stat?path=&deep=1` | tek öğe; `deep=1` klasörde toplam boyut ve dosya sayısı |
| `GET /api/files/tree?path=` | klasör altındaki tüm dosyalar (klasör indirmek için; en fazla 200 000) |
| `GET /api/files/search?path=&q=` | ada göre arama (Türkçe harf duyarsız, en fazla 500 sonuç / 15 sn) |
| `GET /api/files/thumb?path=&w=` | resim / kapak küçük resmi (JPEG, önbellekli) |
| `GET /api/files/hash?path=` | `{sha256}` — aktarım sonrası doğrulama için |

## Aktarım

**İndirme:** `GET /api/files/download?path=` (`HEAD` da olur). `Range` / `If-Range` desteklenir, kopan
indirme kaldığı bayttan devam eder. `X-File-Size` ve `X-File-Mtime` başlıkları döner; `inline=1` tarayıcıda açar.

**Yükleme (devam ettirilebilir):**

1. `GET /api/files/upload?path=` → `{offset, exists, size, mtime, free, writable}`. Daha önce yarım kalan
   yükleme varsa `offset` oradan başlar (veri `.ad.hspart` adlı geçici dosyada tutulur).
2. `PUT /api/files/upload?path=&offset=N&size=TOPLAM&mtime=MS&conflict=overwrite|rename|fail` gövde = dosyanın `N`'den sonrası.
   - `409 {offset}`: sunucudaki ofset farklı; istemci o ofsetten devam eder.
   - `409 {exists:true}`: dosya zaten var (ve `conflict` verilmemiş).
   - `507`: diskte yer yok (yüklemeden önce kontrol edilir).
   - Son bayt gelince geçici dosya asıl adına taşınır, `mtime` korunur; `rename` seçiliyse `ad (2).uzantı`.
3. `DELETE /api/files/upload?path=` yarım kalan yüklemeyi siler.

Aynı dosyaya iki cihaz aynı anda yükleyemez (`409`). Okuma/yazma zaman aşımı her parça için ayrı uygulanır,
bu yüzden çok büyük dosyalar da kesilmez; bağlantı 45 sn hiç ilerlemezse istemci kopmuş sayar ve yeniden dener.

## Dosya işlemleri

| İstek | Açıklama |
|---|---|
| `POST /api/files/mkdir` `{path}` | klasör oluştur |
| `POST /api/files/rename` `{path, name}` | yeniden adlandır |
| `POST /api/files/delete` `{paths, permanent}` | çöp kutusuna taşı (ya da kalıcı sil); öğe başına sonuç |
| `POST /api/files/copy` `{paths, dest, move, conflict}` | arka planda kopyala / taşı → `{job}` |
| `GET /api/files/jobs` · `DELETE /api/files/jobs/{id}` | işler, iptal |
| `GET /api/files/trash` | çöp kutusu (`id, name, orig, deleted, dir, size`) |
| `POST /api/files/trash/restore` `{ids}` | geri yükle (yer doluysa `ad (2)`) |
| `POST /api/files/trash/delete` `{ids}` / `{all:true}` | kalıcı sil / çöpü boşalt |

Çöp kutusu her diskte `.homestream-trash` klasörüdür (yazılamıyorsa `~/.local/share/homestream/trash`).
Sistem klasörleri, ev klasörü, kütüphane kökü ve disk bağlama noktaları silinemez / taşınamaz (`403`).
Kütüphane klasörlerinde değişiklik olunca video/müzik kütüphanesi kısa bir gecikmeyle yeniden taranır.

## Sunucu ve cihazlar

| İstek | Açıklama |
|---|---|
| `GET /api/files/system` | ad, işletim sistemi, çalışma süresi, CPU, bellek, sıcaklık, ağ hızı, IP adresleri |
| `GET /api/files/devices` | diskler ve bölümleri (`lsblk`): model, bağlantı türü, dosya sistemi, doluluk, `canEject` |
| `POST /api/files/devices/eject` `{path}` | USB diski güvenle çıkar |
| `POST /api/files/devices/mount` `{device}` | takılı olmayan bölümü bağla |

Çıkarma ve bağlama için `install.sh` tarafından kurulan `/usr/local/sbin/homestream-disk` yardımcısı
(`sudo -n` ile, yalnızca bu komut için izin) kullanılır. Yardımcı yoksa `503` ve açıklama döner.
Çıkarılan disk, fiziksel olarak sökülene kadar otomatik bağlanmaz.

## Canlı olaylar

`GET /api/files/events?watch=/a&watch=/b` — Server-Sent Events akışı:

| Olay | Veri |
|---|---|
| `hello` | `{id, session, server}` — bağlantı açıldı |
| `ping` | her 10 sn; istemci 25 sn bir şey gelmezse bağlantıyı kopmuş sayar ve yeniden bağlanır |
| `change` | `{dir}` — izlenen klasör değişti (uygulama listeyi yeniler) |
| `job` | kopyalama / taşıma ilerlemesi |
| `disks` | disk takıldı / çıkarıldı |
| `sessions` | bir cihaz bağlandı / ayrıldı |
| `revoked` | bu oturum başka cihazdan kapatıldı |

`PUT /api/files/events/{id}/watch` `{dirs}` izlenen klasörleri (en fazla birkaç) bağlantıyı kesmeden değiştirir.
Klasörler ayrıca her 2 sn yoklanır, böylece sunucuda elle yapılan değişiklikler de görünür.
