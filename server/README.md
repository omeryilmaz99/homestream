# Home Stream Sunucusu

Evdeki mini bilgisayarınızdaki filmleri ve dizileri, Netflix benzeri Home Stream
uygulamasına (Windows, Android TV, telefon) sunan küçük bir sunucu. Dosyalar olduğu
gibi oynatılır (dönüştürme yok), bu yüzden işlemciyi yormaz.

## Kurulum

Sunucuya SSH ile bağlanın ve **normal kullanıcınızla** (root değil) çalıştırın:

```bash
curl -fsSL https://github.com/omeryilmaz99/homestream/releases/latest/download/install.sh | bash
```

Betik şunları yapar: `ffmpeg` kurar, sunucuyu `/opt/homestream` altına yükler,
`~/HomeStream` (içinde `Filmler` ve `Diziler`) klasörünü oluşturur, otomatik başlayan
bir servis kurar, güvenlik duvarında (ufw) yerel ağa 8420/tcp ve 8421/udp portlarını açar
ve isterseniz Windows'tan dosya kopyalamak için bir **HomeStream** ağ paylaşımı (Samba) kurar.

Sonunda ekranda şunlar yazar:

- Uygulamada bağlanılacak adres: `http://<sunucu-ip>:8420` (uygulama sunucuyu genelde kendisi bulur)
- Windows Gezgini adresi: `\\<sunucu-ip>\HomeStream`

**Güncelleme:** aynı komutu tekrar çalıştırın. Ayarlarınız, profilleriniz ve izleme geçmişiniz korunur.

**Kaldırma:** `curl -fsSL .../install.sh | bash -s uninstall` (film dosyalarınıza dokunulmaz).

## Filmleri nereye koymalı?

Klasör yapısı serbesttir, ama şöyle düzenlerseniz en iyi sonucu alırsınız:

```
HomeStream/
├── Filmler/
│   ├── Inception (2010)/Inception.mkv
│   ├── Inception (2010)/Inception.tr.srt        ← Türkçe altyazı
│   └── Görevimiz Gülmek 2019 1080p.mp4
└── Diziler/
    ├── Breaking Bad/Season 1/Breaking.Bad.S01E01.mkv
    └── Kurtlar Vadisi/1. Sezon/2. Bölüm.mp4
```

- Bölümler `S01E02`, `1x02`, `Sezon 1 / Bölüm 2`, `2. Bölüm` gibi adlardan tanınır.
- Altyazılar videoyla aynı adla başlamalı (`Film.tr.srt`, `Film.Turkish.srt`) ya da
  videonun yanındaki `Subs`/`Altyazı` klasöründe olmalı. Türkçe karakterli eski
  (Windows-1254) altyazılar otomatik düzeltilir.
- Kapak için klasöre `poster.jpg`, arka plan için `fanart.jpg` koyabilirsiniz. Yoksa
  videodan otomatik bir kare alınır.
- Yeni dosyalar en geç 30 dakikada bir görünür; uygulamadan "Kütüphaneyi Tara" ile hemen taratabilirsiniz.

## Müzikleri nereye koymalı?

Home Müzik uygulaması `HomeStream/Müzik` klasörünü kullanır (kurulum oluşturur). Başka
klasörler (ör. harici diskteki arşiv) uygulamanın Ayarlar > Sunucu ayarları bölümünden
şifreyle eklenebilir. Bu klasörlerden yalnızca müzik dosyaları alınır.

```
HomeStream/Müzik/
├── Tarkan/Karma (2001)/03 Kuzu Kuzu.mp3
├── Pink Floyd/The Wall/CD1/01 In the Flesh.flac
└── Klipler/Sezen Aksu - Gülümse.mp4        ← videonun yalnızca sesi çalınır
```

- Desteklenen biçimler: MP3, FLAC, ALAC/M4A, AAC, OGG, Opus, WAV, AIFF, APE, WavPack, WMA,
  DSD (DSF/DFF) ve ses olarak MP4, MKV, WEBM, MOV gibi videolar.
- Etiket yoksa ad, sanatçı, albüm ve parça numarası dosya/klasör adından çıkarılır
  (`03 - Sanatçı - Şarkı.mp3`, `Sanatçı - Albüm (2001)/`). Bozuk Türkçe etiketler (Ý, Þ, Ð)
  düzeltilir.
- Kapak: klasördeki `cover.jpg`/`folder.jpg`, dosyaya gömülü kapak, videodan bir kare,
  internet (Deezer/iTunes) ya da otomatik oluşturulan bir kapak — bu sırayla.

**Harici disk:** Uygulamanın Ayarlar ekranından "Klasör Ekle" ile `/media/...` veya
`/mnt/...` altındaki klasörü ekleyin. Disk takılı değilken içerikler gizlenir, silinmez;
disk geri takılınca izleme geçmişiyle birlikte geri gelir.

**Afiş ve özetler (isteğe bağlı):** themoviedb.org'dan ücretsiz bir API anahtarı alıp
uygulamanın Ayarlar ekranına girerseniz Türkçe özetler, türler, puanlar ve afişler indirilir.

## Sorun giderme

```bash
systemctl status homestream          # çalışıyor mu?
journalctl -u homestream -f          # canlı kayıtlar
sudo systemctl restart homestream    # yeniden başlat
```

- Uygulama sunucuyu bulamıyorsa adresi elle girin: `http://<sunucu-ip>:8420`
- Tarayıcıda `http://<sunucu-ip>:8420/api/info` açılıyorsa sunucu çalışıyordur.
- Veriler (veritabanı, resim önbelleği): `/var/lib/homestream`

## Geliştiriciler için

```bash
make test        # go vet + birim testleri
./build.sh       # dist/homestream-server-linux-amd64 ve -arm64 (statik, CGO_ENABLED=0)
```

Parametreler (bayrak / ortam değişkeni): `--port` / `HOMESTREAM_PORT` (8420),
`--data` / `HOMESTREAM_DATA` (`/var/lib/homestream`), `--library` / `HOMESTREAM_LIBRARY`
(`~/HomeStream`), `--name` / `HOMESTREAM_NAME` (bilgisayar adı),
`--discovery-port` / `HOMESTREAM_DISCOVERY_PORT` (8421). API: `../docs/API.md`.
