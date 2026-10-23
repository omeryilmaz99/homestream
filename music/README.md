# Home Müzik

Evdeki Home Stream sunucusundaki müzikler için Spotify tarzı Android uygulaması
(Flutter + mpv). Koyu, düz yüzeyli, mor vurgulu tasarım.

## Özellikler

- **Ana Sayfa, Keşfet, Kitaplık, Profil** sekmeleri; albüm, sanatçı, tür ve çalma listesi
  sayfaları. Ana sayfada her seferinde yeni bir "Sana Özel Mix". Kitaplık: çalma listeleri
  (Beğenilen Şarkılar dahil), sanatçılar, albümler, indirilenler ve sunucudaki klasör yapısını
  olduğu gibi açan Klasörler. Profil: dinleme sayıları, en çok dinlenen sanatçılar, son
  dinlenenler.
- **Profiller şifresiz**; "Beni hatırla" açıksa uygulama her açılışta profil sormaz.
- **Arka planda çalma**: bildirim ve kilit ekranı kontrolleri, kulaklık tuşları, telefon
  gelince durup sonra devam etme, kulaklık çıkınca duraklatma.
- **Kaldığı yerden devam**: kapatırken çalan şarkı, saniyesi ve çalma sırası saklanır;
  açılınca aynı yerde duraklatılmış olarak gelir (kendiliğinden başlamaz).
- **Yumuşak geçiş** (0–12 sn, eşit güç eğrisi) ve aynı albümün ardışık şarkılarında geçişi
  atlayan "akıllı geçiş". Sıradaki şarkı önceden yüklenir; şarkılar arası boşluk olmaz.
- **Ses kalitesi**: dosyalar dönüştürülmeden çalınır (FLAC, ALAC, 24-bit/192 kHz, DSD…);
  Android'de 32-bit kayan nokta çıkış (sorun çıkaran telefonlarda kendiliğinden uyumlu
  moda geçer), isteğe bağlı ReplayGain.
- **İndirme**: şarkı, albüm, çalma listesi, sanatçı, klasör ya da tüm beğenilenler
  indirilebilir; yarıda kalan indirme kaldığı yerden devam eder. İndirilenler yalnızca
  uygulama içinde, sunucu olmadan da çalınır. Ayarlar > "İndirilenleri sil".
- **Çevrimdışı mod**: sunucuya ulaşılamazsa uygulama son profille açılır, indirilenler
  çalınır, bağlantı gelince kendiliğinden toparlanır; dinleme sayıları sonra gönderilir.
- Uyku zamanlayıcısı, çalma sırası düzenleme, kapak renginden hareketli arka plan.

## Ayarlar

- **Cihaz ayarları** (şifresiz, yalnızca bu telefonu etkiler): yumuşak geçiş, ses
  eşitleme, ses çıkışı, indirilenler, önbellek, profil.
- **Sunucu ayarları** (şifreli, herkesi etkiler): müzik klasörleri, internetten kapak
  bulma, otomatik tarama sıklığı, şimdi tara / kapakları yenile. Şifre video
  uygulamasındakiyle aynıdır ve sunucuda doğrulanır.

## Derleme

```bash
flutter pub get
flutter build apk --release --target-platform android-arm,android-arm64
```

GitHub Actions her gönderimde `HomeMuzik-Android.apk` dosyasını üretir. Sunucu arayüzü:
[../docs/MUSIC_API.md](../docs/MUSIC_API.md).
