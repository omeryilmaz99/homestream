# Home Stream

Ev sunucusundaki filmler ve diziler için Netflix tarzı bir uygulama.

- `server/` — Ubuntu sunucuda çalışan küçük program (Go, tek dosya). HomeStream klasörünü ve eklenen diğer klasörleri tarar, kapakları, profilleri ve kaldığın yerleri tutar. Ayrıntı: [server/README.md](server/README.md)
- `client/` — Windows uygulaması (Flutter + mpv). Aynı kod ileride Android TV ve telefon için de kullanılacak.
- `music/` — **Home Müzik**: Spotify tarzı müzik uygulaması (Android telefon, Flutter + mpv). Aynı sunucuya ve aynı profillere bağlanır. Ayrıntı: [music/README.md](music/README.md)
- `files/` — **Home Dosya**: bilgisayar / telefon ile sunucu arasında dosya aktarımı ve sunucu yönetimi (Windows + Android, Flutter). Ayrıntı: [files/README.md](files/README.md)
- `docs/API.md` — sunucu ile uygulama arasındaki arayüz; müzik için `docs/MUSIC_API.md`, dosya aktarımı için `docs/FILES_API.md`.

## Derleme

GitHub'a her gönderimde `.github/workflows/build.yml` çalışır ve "latest" sürümüne şunları koyar:
- `HomeStream-Setup.exe` (Windows kurulum dosyası) ve `HomeStream-Windows-Portable.zip`
- `HomeStream-Android.apk` / `HomeStream-AndroidTV.apk` (video) ve `HomeMuzik-Android.apk` (müzik)
- `HomeDosya-Setup.exe`, `HomeDosya-Windows-Portable.zip` ve `HomeDosya-Android.apk` (dosya aktarımı)
- `homestream-server-linux-amd64` / `-arm64` ve `install.sh`

## Sunucu kurulumu (tek komut)

```
curl -fsSL https://github.com/omeryilmaz99/homestream/releases/latest/download/install.sh | bash
```
