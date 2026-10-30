# Home Dosya

Bilgisayar veya telefon ile ev sunucusu arasında dosya aktarımı (Windows, Linux, Android).
Ekran ikiye bölünür: solda bu cihazın dosyaları, sağda sunucunun dosyaları. Telefonda iki panel
arasında sekmeyle geçilir.

## Özellikler

- **Sürükle-bırak:** paneller arasında ya da Windows Gezgini'nden uygulamaya; klasörler de aktarılır.
- **Kopmaya dayanıklı aktarım:** bağlantı koparsa aktarım durmaz, "bağlantı bekleniyor" olur ve
  geri gelince kaldığı bayttan devam eder. Uygulama kapansa bile açılışta devam eder.
- **Kuyruk:** aynı anda 1-4 dosya, duraklat / devam / iptal, hız ve kalan süre. Aktarım bitince
  istersen SHA-256 ile doğrulama.
- **Çakışma sorusu:** dosya zaten varsa üzerine yaz / ikisini de tut / atla, "hepsine uygula".
- **Gerçek zamanlı:** sunucudaki klasör başka bir cihazdan ya da elle değişirse liste kendiliğinden yenilenir.
  Bağlantı kopunca üstte uyarı çıkar, otomatik yeniden bağlanır.
- **Sunucu yönetimi:** klasör oluştur, yeniden adlandır, kopyala / taşı, sil (çöp kutusuyla geri alınabilir),
  arama, resim önizleme.
- **Cihazlar:** sunucuya takılı diskler, doluluk, USB diski güvenle çıkarma / bağlama; CPU, bellek, sıcaklık, ağ.
- **Bağlı cihazlar:** hangi bilgisayar / telefonun bağlı olduğu, uzaktan oturum kapatma.
- **Birden fazla sunucu:** ağdaki sunucular otomatik bulunur; sunucunun IP'si değişirse (ör. başka eve
  taşınınca) uygulama yeni adresi kendisi bulur.
- **Beni hatırla:** şifre bir kez girilir, sunucu başına ayrı saklanır.
- **Android:** aktarım arka planda bildirimle sürer, ekran kapansa da kesilmez.

Giriş şifresi, sunucunun ayarlar şifresiyle aynıdır. Aktarımlar yerel ağda HTTP ile yapılır;
uygulamayı ev ağında kullan.

## Geliştirme

```
cd files
flutter pub get
flutter run -d windows   # ya da linux / android
```

Sunucu tarafındaki uç noktalar: [docs/FILES_API.md](../docs/FILES_API.md).
