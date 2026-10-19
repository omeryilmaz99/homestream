#!/usr/bin/env bash
# Home Stream sunucu kurulum / güncelleme betiği
#
#   curl -fsSL <adres>/install.sh | bash        # kur veya güncelle
#   bash install.sh                             # (yanında homestream-server-linux-<mimari> varsa onu kullanır)
#   bash install.sh uninstall                   # kaldır (filmlerinize dokunmaz)
#
# Normal (sudo yetkili) kullanıcıyla çalıştırın; gerektiğinde sudo şifresi sorulur.
set -euo pipefail

# ---- ayarlar -------------------------------------------------------------
HOMESTREAM_DOWNLOAD_BASE="${HOMESTREAM_DOWNLOAD_BASE:-https://github.com/omeryilmaz99/homestream/releases/latest/download}"
ROOT="${HOMESTREAM_TEST_ROOT:-}"   # only for testing the script
INSTALL_DIR=$ROOT/opt/homestream
DATA_DIR=$ROOT/var/lib/homestream
SERVICE=homestream
UNIT_FILE=$ROOT/etc/systemd/system/${SERVICE}.service
PORT=8420
DISCOVERY_PORT=8421
LAN_NETS="10.0.0.0/8 172.16.0.0/12 192.168.0.0/16"
SMB_CONF=$ROOT/etc/samba/smb.conf
# Unattended options: HOMESTREAM_SAMBA=yes|no, HOMESTREAM_SAMBA_PASSWORD=...,
# HOMESTREAM_LIBRARY=/path, HOMESTREAM_USER=name
# -------------------------------------------------------------------------

msg()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m  %s\n' "$*" >&2; }
die()  { printf '\033[1;31mHATA:\033[0m %s\n' "$*" >&2; exit 1; }

have_tty() { ( exec </dev/tty ) 2>/dev/null; }

# ask "soru" → 0 = evet (varsayılan), 1 = hayır. Terminal yoksa sormadan "hayır".
ask() {
  have_tty || return 1
  local ans=""
  printf '%s [E/h] ' "$1" >/dev/tty
  read -r ans </dev/tty || ans=""
  case "$ans" in [hHnN]*) return 1 ;; *) return 0 ;; esac
}

# ask_no "soru" → varsayılan hayır
ask_no() {
  have_tty || return 1
  local ans=""
  printf '%s [e/H] ' "$1" >/dev/tty
  read -r ans </dev/tty || ans=""
  case "$ans" in [eEyY]*) return 0 ;; *) return 1 ;; esac
}

# ---- kullanıcı / yetki ----------------------------------------------------
if [ "$(id -u)" -eq 0 ]; then
  RUN_USER="${HOMESTREAM_USER:-${SUDO_USER:-}}"
  if [ -z "$RUN_USER" ] || { [ "$RUN_USER" = "root" ] && [ "${HOMESTREAM_USER:-}" != "root" ]; }; then
    die "Bu betiği root olarak değil, normal kullanıcınızla çalıştırın (örn: bash install.sh). Gerekirse HOMESTREAM_USER=kullanici ile belirtin."
  fi
  SUDO=""
else
  RUN_USER="$(id -un)"
  command -v sudo >/dev/null 2>&1 || die "sudo bulunamadı."
  SUDO="sudo"
fi
getent passwd "$RUN_USER" >/dev/null || die "Kullanıcı bulunamadı: $RUN_USER"
RUN_HOME="$(getent passwd "$RUN_USER" | cut -d: -f6)"
RUN_GROUP="$(id -gn "$RUN_USER")"

as_user() {
  if [ "$(id -un)" = "$RUN_USER" ]; then "$@"
  elif [ "$(id -u)" -eq 0 ]; then runuser -u "$RUN_USER" -- "$@"
  else sudo -u "$RUN_USER" "$@"; fi
}

server_ip() {
  local ip=""
  if command -v ip >/dev/null 2>&1; then
    ip="$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)"
  fi
  [ -n "$ip" ] || ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  [ -n "$ip" ] || ip="127.0.0.1"
  echo "$ip"
}

ufw_active() { command -v ufw >/dev/null 2>&1 && $SUDO ufw status 2>/dev/null | grep -q "Status: active"; }

# ---- kaldırma ---------------------------------------------------------------
uninstall() {
  msg "Home Stream kaldırılıyor…"
  $SUDO systemctl disable --now "$SERVICE" 2>/dev/null || true
  $SUDO rm -f "$UNIT_FILE"
  $SUDO systemctl daemon-reload || true
  $SUDO rm -rf "$INSTALL_DIR"
  if ufw_active; then
    for net in $LAN_NETS; do
      $SUDO ufw delete allow from "$net" to any port "$PORT" proto tcp >/dev/null 2>&1 || true
      $SUDO ufw delete allow from "$net" to any port "$DISCOVERY_PORT" proto udp >/dev/null 2>&1 || true
    done
  fi
  if [ -f "$SMB_CONF" ] && grep -q '^# BEGIN HOMESTREAM' "$SMB_CONF"; then
    if ask "Windows paylaşımı (\\\\$(server_ip)\\HomeStream) da kaldırılsın mı?"; then
      $SUDO sed -i '/^# BEGIN HOMESTREAM/,/^# END HOMESTREAM/d' "$SMB_CONF"
      $SUDO systemctl reload smbd 2>/dev/null || $SUDO systemctl restart smbd 2>/dev/null || true
    fi
  fi
  if [ -d "$DATA_DIR" ] && ask_no "İzleme geçmişi, profiller ve önbellek ($DATA_DIR) silinsin mi?"; then
    $SUDO rm -rf "$DATA_DIR"
  fi
  msg "Kaldırıldı. Film ve dizi dosyalarınıza dokunulmadı."
  exit 0
}

[ "${1:-}" = "uninstall" ] && uninstall
[ -z "${1:-}" ] || [ "${1:-}" = "install" ] || die "Bilinmeyen komut: $1 (kullanım: install.sh [uninstall])"

# ---- mimari ve ikili dosya ---------------------------------------------------
case "$(uname -m)" in
  x86_64|amd64) ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) die "Desteklenmeyen işlemci mimarisi: $(uname -m)" ;;
esac
BIN_NAME="homestream-server-linux-$ARCH"

if [ -n "$SUDO" ]; then
  msg "Yönetici (sudo) yetkisi gerekiyor…"
  $SUDO -v || die "sudo yetkisi alınamadı."
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
BIN=""
for cand in "${SCRIPT_DIR:+$SCRIPT_DIR/$BIN_NAME}" "./$BIN_NAME" "${SCRIPT_DIR:+$SCRIPT_DIR/dist/$BIN_NAME}"; do
  if [ -n "$cand" ] && [ -f "$cand" ]; then BIN="$cand"; break; fi
done
if [ -n "$BIN" ]; then
  msg "Yerel dosya kullanılıyor: $BIN"
  cp "$BIN" "$TMP/homestream-server"
else
  URL="$HOMESTREAM_DOWNLOAD_BASE/$BIN_NAME"
  msg "İndiriliyor: $URL"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --progress-bar -o "$TMP/homestream-server" "$URL" || die "İndirme başarısız: $URL"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$TMP/homestream-server" "$URL" || die "İndirme başarısız: $URL"
  else
    die "curl veya wget gerekli (sudo apt install curl)"
  fi
fi
chmod 0755 "$TMP/homestream-server"
NEW_VERSION="$("$TMP/homestream-server" --version 2>/dev/null)" || die "İndirilen dosya bu sistemde çalışmıyor (yanlış mimari?)."

# ---- ffmpeg ------------------------------------------------------------------
if ! command -v ffprobe >/dev/null 2>&1 || ! command -v ffmpeg >/dev/null 2>&1; then
  msg "ffmpeg kuruluyor (süre ve küçük resimler için)…"
  $SUDO env DEBIAN_FRONTEND=noninteractive apt-get update -qq
  $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ffmpeg || warn "ffmpeg kurulamadı; sunucu yine de çalışır ama küçük resimler oluşmaz."
fi

# ---- dosyalar ------------------------------------------------------------------
OLD_VERSION=""
[ -x "$INSTALL_DIR/homestream-server" ] && OLD_VERSION="$("$INSTALL_DIR/homestream-server" --version 2>/dev/null || true)"
msg "Sunucu yükleniyor: $INSTALL_DIR (sürüm $NEW_VERSION${OLD_VERSION:+, önceki: $OLD_VERSION})"
$SUDO mkdir -p "$INSTALL_DIR"
$SUDO install -m 0755 "$TMP/homestream-server" "$INSTALL_DIR/homestream-server.new"
$SUDO mv -f "$INSTALL_DIR/homestream-server.new" "$INSTALL_DIR/homestream-server"

$SUDO mkdir -p "$DATA_DIR"
$SUDO chown "$RUN_USER:$RUN_GROUP" "$DATA_DIR"

# library folder: keep a previously configured one
LIBRARY="${HOMESTREAM_LIBRARY:-}"
if [ -z "$LIBRARY" ] && [ -f "$UNIT_FILE" ]; then
  LIBRARY="$(sed -n 's/^Environment="\{0,1\}HOMESTREAM_LIBRARY=\([^"]*\)"\{0,1\}$/\1/p' "$UNIT_FILE" | head -n1)"
fi
[ -n "$LIBRARY" ] || LIBRARY="$RUN_HOME/HomeStream"
if [ ! -d "$LIBRARY" ]; then
  msg "Film klasörü oluşturuluyor: $LIBRARY"
  as_user mkdir -p "$LIBRARY/Filmler" "$LIBRARY/Diziler"
fi

# ---- systemd ---------------------------------------------------------------------
UNIT_CONTENT="[Unit]
Description=Home Stream medya sunucusu
Documentation=https://github.com/omeryilmaz99/homestream
Wants=network-online.target
After=network-online.target local-fs.target remote-fs.target

[Service]
Type=simple
User=$RUN_USER
Group=$RUN_GROUP
Environment=\"HOMESTREAM_PORT=$PORT\"
Environment=\"HOMESTREAM_DATA=$DATA_DIR\"
Environment=\"HOMESTREAM_LIBRARY=$LIBRARY\"
ExecStart=$INSTALL_DIR/homestream-server
Restart=always
RestartSec=3
Nice=5
IOSchedulingClass=best-effort
IOSchedulingPriority=6
LimitNOFILE=65536
TimeoutStopSec=15

[Install]
WantedBy=multi-user.target
"
if [ ! -f "$UNIT_FILE" ] || [ "$(cat "$UNIT_FILE")" != "$(printf '%s' "$UNIT_CONTENT")" ]; then
  msg "systemd servisi yazılıyor: $UNIT_FILE"
  printf '%s' "$UNIT_CONTENT" | $SUDO tee "$UNIT_FILE" >/dev/null
fi
$SUDO systemctl daemon-reload
$SUDO systemctl enable "$SERVICE" >/dev/null 2>&1
msg "Servis (yeniden) başlatılıyor…"
$SUDO systemctl restart "$SERVICE"

# ---- güvenlik duvarı ---------------------------------------------------------------
if ufw_active; then
  msg "Güvenlik duvarı (ufw): $PORT/tcp ve $DISCOVERY_PORT/udp yerel ağa açılıyor"
  for net in $LAN_NETS; do
    $SUDO ufw allow from "$net" to any port "$PORT" proto tcp comment 'Home Stream' >/dev/null
    $SUDO ufw allow from "$net" to any port "$DISCOVERY_PORT" proto udp comment 'Home Stream kesif' >/dev/null
  done
fi

# ---- Samba (Windows paylaşımı) --------------------------------------------------------
setup_samba() {
  msg "Samba kuruluyor…"
  $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq samba || { warn "Samba kurulamadı."; return 0; }
  [ -f "$SMB_CONF.homestream-yedek" ] || $SUDO cp "$SMB_CONF" "$SMB_CONF.homestream-yedek" 2>/dev/null || true
  if ! grep -q '^# BEGIN HOMESTREAM' "$SMB_CONF" 2>/dev/null; then
    printf '\n# BEGIN HOMESTREAM\n[HomeStream]\n   comment = Home Stream filmler ve diziler\n   path = %s\n   browseable = yes\n   read only = no\n   valid users = %s\n   force user = %s\n   force group = %s\n   create mask = 0664\n   directory mask = 0775\n# END HOMESTREAM\n' \
      "$LIBRARY" "$RUN_USER" "$RUN_USER" "$RUN_GROUP" | $SUDO tee -a "$SMB_CONF" >/dev/null
  fi
  if ! $SUDO pdbedit -L 2>/dev/null | grep -q "^$RUN_USER:"; then
    local p1="${HOMESTREAM_SAMBA_PASSWORD:-}" p2=""
    while [ -z "$p1" ]; do
      have_tty || { warn "Şifre sorulamadı; sonra 'sudo smbpasswd -a $RUN_USER' çalıştırın."; break; }
      printf 'Windows paylaşımı için şifre belirleyin (kullanıcı adı: %s): ' "$RUN_USER" >/dev/tty
      read -rs p1 </dev/tty || true; printf '\n' >/dev/tty
      printf 'Şifre (tekrar): ' >/dev/tty
      read -rs p2 </dev/tty || true; printf '\n' >/dev/tty
      if [ -n "$p1" ] && [ "$p1" = "$p2" ]; then break; fi
      printf 'Şifreler boş ya da eşleşmiyor, tekrar deneyin.\n' >/dev/tty
      p1=""
    done
    if [ -n "$p1" ]; then
      printf '%s\n%s\n' "$p1" "$p1" | $SUDO smbpasswd -a -s "$RUN_USER" >/dev/null
      $SUDO smbpasswd -e "$RUN_USER" >/dev/null || true
    fi
  fi
  $SUDO systemctl enable smbd >/dev/null 2>&1 || true
  $SUDO systemctl restart smbd || warn "smbd başlatılamadı."
  if ufw_active; then
    for net in $LAN_NETS; do
      $SUDO ufw allow from "$net" to any port 139,445 proto tcp comment 'Samba' >/dev/null
      $SUDO ufw allow from "$net" to any port 137,138 proto udp comment 'Samba' >/dev/null
    done
  fi
  SAMBA_OK=1
}

SAMBA_OK=0
if [ -f "$SMB_CONF" ] && grep -q '^# BEGIN HOMESTREAM' "$SMB_CONF"; then
  SAMBA_OK=1   # already configured
elif [ "${HOMESTREAM_SAMBA:-}" = "yes" ]; then
  setup_samba
elif [ "${HOMESTREAM_SAMBA:-}" = "no" ] || [ -f "$INSTALL_DIR/.samba-hayir" ]; then
  :            # declined (now or earlier)
elif have_tty; then
  if ask "Filmleri Windows Gezgini'nden kopyalayabilmek için bir ağ paylaşımı (Samba) kurulsun mu?"; then
    setup_samba
  else
    $SUDO touch "$INSTALL_DIR/.samba-hayir"
  fi
fi

# ---- kontrol ve özet ---------------------------------------------------------------
ok=0
for _ in $(seq 1 20); do
  if command -v curl >/dev/null 2>&1; then
    curl -fs "http://127.0.0.1:$PORT/api/info" >/dev/null 2>&1 && { ok=1; break; }
  else
    $SUDO systemctl is-active --quiet "$SERVICE" && { ok=1; break; }
  fi
  sleep 0.5
done
if [ "$ok" != 1 ]; then
  warn "Servis yanıt vermiyor. Son kayıtlar:"
  $SUDO journalctl -u "$SERVICE" -n 30 --no-pager || true
  exit 1
fi

IP="$(server_ip)"
echo
printf '\033[1;32m✔ Home Stream kuruldu ve çalışıyor!\033[0m\n'
echo
echo "  Sunucu adresi        : $IP"
echo "  Uygulamada bağlanın  : http://$IP:$PORT"
echo "  Film klasörü         : $LIBRARY"
if [ "$SAMBA_OK" = 1 ]; then
  echo "  Windows Gezgini      : \\\\$IP\\HomeStream   (kullanıcı adı: $RUN_USER)"
fi
echo
echo "  Filmleri 'Filmler', dizileri 'Diziler' klasörüne koyun; birkaç dakika içinde"
echo "  uygulamada görünürler (veya uygulamadan 'Kütüphaneyi Tara' deyin)."
echo "  Kayıtlar: journalctl -u $SERVICE -f      Güncelleme: bu betiği tekrar çalıştırın."
echo
