# Home Stream

Ev sunucusundaki filmler ve diziler için Netflix tarzı bir uygulama.

- `server/` — Ubuntu sunucuda çalışan küçük program (Go, tek dosya). HomeStream klasörünü ve eklenen diğer klasörleri tarar, kapakları, profilleri ve kaldığın yerleri tutar. Ayrıntı: [server/README.md](server/README.md)
- `client/` — Windows uygulaması (Flutter + mpv). Aynı kod ileride Android TV ve telefon için de kullanılacak.
- `docs/API.md` — sunucu ile uygulama arasındaki arayüz.

## Derleme

GitHub'a her gönderimde `.github/workflows/build.yml` çalışır ve "latest" sürümüne şunları koyar:
- `HomeStream-Setup.exe` (Windows kurulum dosyası) ve `HomeStream-Windows-Portable.zip`
- `homestream-server-linux-amd64` / `-arm64` ve `install.sh`

## Sunucu kurulumu (tek komut)

```
curl -fsSL https://github.com/omeryilmaz99/homestream/releases/latest/download/install.sh | bash
```
