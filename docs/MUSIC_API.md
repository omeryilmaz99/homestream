# Müzik API

Home Müzik uygulamasının kullandığı uç noktalar. Sunucu aynıdır (port 8420); profiller
video uygulamasıyla ortaktır (`/api/profiles`). Yanıtlar JSON'dur, büyük listeler gzip ile
sıkıştırılır.

**Başlıklar**

- `X-Profile: <profil id>` — beğeniler, çalma listeleri ve dinleme geçmişi bu profile aittir.
- `X-Admin-Password: <şifre>` — yalnızca sunucu genelindeki ayarları değiştiren isteklerde
  (aşağıda 🔒). Şifre yanlışsa `403`.

## Kütüphane

| İstek | Açıklama |
|---|---|
| `GET /api/music/info` | şarkı / albüm / sanatçı sayısı, tarama durumu |
| `GET /api/music/home` | ana sayfa: `quick` (kısayollar), `rows` (Son Dinlediklerin, Senin İçin Hazırlandı, Son Eklenenler, En Çok Dinlediklerin, Sanatçılar, Yeniden Keşfet) |
| `GET /api/music/mix?n=50` | "Sana Özel Mix": profilin sevdiği sanatçı ve türlerden, her çağrıda yeni bir şarkı karışımı |
| `GET /api/music/stats` | profil sayfası: `plays`, `minutes`, `liked`, `playlists`, `topArtists`, `recent` |
| `GET /api/music/tracks?sort=title\|artist\|album\|added\|plays\|recent&genre=` | şarkılar |
| `POST /api/music/tracks/batch` `{ids}` | id listesinden şarkılar |
| `POST /api/music/tracks/{id}/played` `{at}` | dinlendi (30 sn ya da şarkının yarısı) |
| `GET /api/music/albums?sort=title\|artist\|year\|added\|recent` | albümler |
| `GET /api/music/albums/{id}` | albüm, şarkıları ve sanatçının diğer albümleri |
| `GET /api/music/artists` · `GET /api/music/artists/{id}` | sanatçılar / sanatçı (popüler şarkılar, albümler, yer aldığı albümler) |
| `GET /api/music/genres` | türler |
| `GET /api/music/search?q=` | şarkı, albüm, sanatçı, çalma listesi ve klasör araması (Türkçe harf duyarsız) |
| `GET /api/music/browse?path=&recursive=1` | klasörler: `path` boşsa müzik klasörleri; `recursive=1` alt klasörlerdeki tüm şarkılar |

Şarkı alanları: `id, title, artist, artistId, album, albumId, albumArtist, trackNo, discNo,
year, genre, duration, cover, coverId, isVideo, codec, bitrate, sampleRate, bitDepth,
channels, lossless, size, ext, path, dir, addedAt, liked, playCount, lastPlayedAt`.
`dir`, şarkının klasörünün `browse` anahtarıdır.

## Kullanıcı verisi (profil başına)

| İstek | Açıklama |
|---|---|
| `GET /api/music/liked` | beğenilen şarkılar (son beğenilen önce) |
| `POST /api/music/like` `{ids, liked}` | beğen / beğeniyi kaldır |
| `GET/POST /api/music/playlists` | çalma listeleri / yeni liste `{name, ids}` |
| `GET/PUT/DELETE /api/music/playlists/{id}` | liste (şarkılarıyla), ad değiştir `{name}`, sil |
| `PUT /api/music/playlists/{id}/tracks` `{ids}` | sırayı / içeriği değiştir |
| `POST /api/music/playlists/{id}/tracks` `{ids, skipDuplicates}` | sona ekle → `{added}` |

Profil silinince müzik verileri de silinir.

## Çalma ve kapaklar

- `GET /api/music/stream/{id}` — dosyanın kendisi (Range destekli, dönüştürme yok → kayıpsız
  kalite). MP4/MKV gibi video dosyalarında yalnızca ses kopyalanır (`.mka`, yeniden
  kodlanmaz) ve önbelleğe alınır.
- `GET /api/music/covers/{id}?w=320` — kapak. Sıra: klasördeki resim (`cover.jpg`,
  `folder.jpg`…) → dosyaya gömülü kapak → video karesi → internet (Deezer, iTunes; anahtar
  gerekmez) → otomatik oluşturulan kapak (mor-pembe tonlarda soyut dağ ya da dalga resmi). Yanıt başlığı `X-Cover-Generated: 1` ise kapak
  oluşturulmuştur. URL'deki `?v=` değeri kapak değişince değişir.

## Sunucu ayarları

| İstek | Açıklama |
|---|---|
| `GET /api/music/settings` | klasörler, internetten kapak, tarama aralığı, ffmpeg var mı |
| 🔒 `PUT /api/music/settings` `{onlineCovers, scanIntervalMinutes}` | değiştir |
| 🔒 `POST /api/music/folders` `{path, name}` | müzik klasörü ekle |
| 🔒 `DELETE /api/music/folders/{id}` | klasörü kaldır (dosyalar silinmez) |
| 🔒 `POST /api/music/admin/check` | şifreyi doğrula |
| `POST /api/music/scan` `{refreshCovers}` | taramayı başlat |
| `GET /api/music/scan/status` | tarama ve kapak hazırlama durumu |

Varsayılan müzik klasörü `<kütüphane>/Müzik`'tir; video taraması müzik klasörlerini atlar.
