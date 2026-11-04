# Home Stream — Samsung TV (Tizen)

Home Stream'in Samsung akıllı TV sürümü. Flutter Tizen'i resmi olarak desteklemediği için bu sürüm
bir **Tizen web uygulaması** (HTML + JavaScript). Görüntüyü TV'nin kendi donanım oynatıcısı
**AVPlay** oynatır, yani TV'nin USB oynatıcısının açtığı her dosya burada da açılır
(mkv, HEVC, 4K, HDR, E-AC3 ve gömülü altyazılar dahil). Sunucuyla aynı API'yi kullanır
([docs/API.md](../docs/API.md)); profiller, kaldığın yerler ve "izlendi" bilgisi diğer
uygulamalarla ortaktır.

2018 ve sonrası Samsung TV'ler (Tizen 4.0+) için yazıldı.

## Özellikler

- **Sunucu bulma:** TV'nin bağlı olduğu ağdaki (ör. 192.168.1.x) Home Stream sunucusunu kendisi
  arar. Bulamazsa adres elle yazılır; adres hatırlanır.
- **Profiller:** "Kim izliyor?" ekranı, yeni profil ekleme; son profil hatırlanır.
- **Ana sayfa:** öne çıkanlar, Devam Et, Sıradaki Bölümler, öneriler ve diğer satırlar.
- **Filmler / Diziler:** sıralama (son eklenen, A–Z, yıl, puan, son izlenen), izlenmiş/izlenmemiş/
  beğenilen süzgeci, tür seçimi.
- **Arama:** TV klavyesiyle film, dizi ve bölüm arama.
- **Ayrıntı:** Oynat / Devam et / Baştan başla, beğen, izlendi say, Devam Et'ten çıkar; dizilerde sezon
  sekmeleri ve bölüm listesi.
- **Oynatıcı:** kaldığı yerden başlar, her 10 saniyede ilerlemeyi sunucuya yazar; ses dili ve altyazı
  seçimi (videonun içindeki ve yanındaki srt/vtt/ass dosyaları); Türkçe altyazıyı kendisi açar;
  bölüm bitince 10 saniyelik "Sıradaki bölüm" kartı.
- **Ayarlar:** sunucu, profil, tercih edilen altyazı dili, tema rengi.

### Kumanda

| Tuş | Ne yapar |
|---|---|
| Yön tuşları / OK | Gezinme ve seçme |
| Geri | Bir önceki ekran; ana sayfada önce menüye, sonra uygulamadan çıkış. Oynatıcıda: oynatıcıyı kapatır |
| Oynatıcıda ◀ ▶ (çubuk kapalıyken) | 10 sn geri / ileri (art arda basılırsa toplanır) |
| Oynatıcıda OK | Duraklat / devam |
| Oynatıcıda ▲ ▼ | Kontrol çubuğunu gösterir |
| ⏯ ⏸ ▶ ⏹ ⏪ ⏩ | Oynat/duraklat, durdur, 10 sn geri, 30 sn ileri |
| CH + / CH − | 5 dk ileri / geri |

## TV'ye kurulum

Samsung, mağaza dışı uygulamaları yalnızca **geliştirici modundaki** TV'ye, **kendi Samsung
sertifikanla imzalanmış** olarak kurdurur. Bu sertifika TV'ye özeldir (TV'nin DUID'sine bağlı), bu
yüzden GitHub'daki derleme imzasız paket çıkarır; imzalama bir kez bilgisayarda yapılır.

### 1. TV'de geliştirici modunu aç

1. TV ve bilgisayar aynı ağda olsun. Bilgisayarın IP adresini öğren (Windows: `ipconfig`).
2. TV'de **Uygulamalar** ekranını aç, kumandada sırayla **1 2 3 4 5** tuşlarına bas.
3. Açılan pencerede **Developer mode: On** seç, **Host PC IP** kısmına bilgisayarın IP'sini yaz.
4. TV'yi kapatıp aç (fişten çekip takmak en garantisi).

### 2. Bilgisayara Tizen Studio kur

1. [Tizen Studio](https://developer.tizen.org/development/tizen-studio/download)'yu kur.
2. **Package Manager** açılır: **Extension SDK** sekmesinde **Samsung Certificate Extension** ve
   **TV Extensions** kur.

### 3. Sertifika oluştur (bir kez)

1. Tizen Studio'da **Tools → Device Manager** aç, **Remote Device Manager**'dan TV'nin IP adresini ekle,
   bağlan (TV listede görünür).
2. **Tools → Certificate Manager → +** → **Samsung** → **TV** seç.
3. Yeni bir author sertifikası oluştur (ad ve şifre senin), Samsung hesabınla giriş yap.
4. Distributor sertifikasında TV'nin **DUID**'si otomatik gelir (TV bağlıyken). Bitir.

### 4. Paketle ve kur

Komut satırı (Tizen Studio'nun `tools/ide/bin` ve `tools` klasörleri PATH'te olmalı; Windows'ta
Git Bash'te çalışır, istersen aşağıdaki arayüz yolunu kullan):

```
cd tizen
./build.sh                 # imzalı HomeStream.wgt üretir (Certificate Manager'daki etkin profille)
sdb connect 192.168.1.50   # TV'nin IP'si
tizen install -n HomeStream.wgt -t $(sdb devices | awk 'NR==2{print $3}')
```

Tizen Studio arayüzüyle: **File → New → Tizen Project → Template → TV → Web Application → Basic
Project** ile "HomeStream" adlı boş bir proje aç, içindeki dosyaları silip bu klasördeki
`config.xml`, `index.html`, `icon.png`, `css/` ve `js/`'yi kopyala. Projeye sağ tıkla →
**Run As → Tizen Web Application**: uygulama imzalanır, TV'ye kurulur ve açılır.

GitHub'daki "latest" sürümünde imzasız `HomeStream-Tizen.wgt` da var (içi düz zip). Kaynağı
indirmek istemezsen onu bir klasöre açıp kendi sertifikanla imzalayabilirsin:
`tizen package -t wgt -s <profil> -- <klasör>`.

Kurulunca uygulama TV'nin **Uygulamalar** ekranında "Home Stream" adıyla görünür. Geliştirici
modunda kurulan uygulamalar TV'de kalır; yalnızca sertifikanın süresi dolunca (birkaç yıl) yeniden
imzalayıp kurmak gerekir.

## Geliştirme

Uygulama sıradan bir web sayfası gibi masaüstü tarayıcıda da açılır (AVPlay yerine `<video>`
kullanır, yani tarayıcının açamadığı mkv/hevc dosyaları orada oynamaz). Kumanda yerine klavye:
yön tuşları, Enter, Esc / Backspace (geri).

```
cd tizen
python3 -m http.server 8090
# tarayıcıda: http://localhost:8090/?server=192.168.1.20
```

Ekran 1920×1080 düzeninde tasarlandı. Eski TV tarayıcılarında çalışsın diye kodda `?.`, `??`,
nesne yayma (`{...x}`) ve CSS grid kullanılmıyor; CI bunu denetler.

Dosyalar:

- `config.xml` — Tizen uygulama tanımı (kimlik `HmStrmTV01.HomeStream`, izinler: internet, avplay, kumanda tuşları)
- `js/api.js` — sunucu API'si ve ağda sunucu arama
- `js/nav.js` — kumanda tuşları ve odak gezinmesi
- `js/player.js` — AVPlay / `<video>` oynatıcı, ses ve altyazı seçimi
- `js/subs.js` — srt / vtt / ass altyazı okuma
- `js/screens.js` — ekranlar
