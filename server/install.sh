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
# ---- otomatik disk bağlama ----------------------------------------------------------
# Takılan her veri diski /media/homestream/<disk adı> altına bağlanır; sunucu bu
# klasörleri kendiliğinden kütüphaneye ekler. Sistem diski ve küçük/özel bölümler atlanır.
AUTOMOUNT_BIN=$ROOT/usr/local/sbin/homestream-automount
AUTOMOUNT_UNIT=$ROOT/etc/systemd/system/homestream-automount.service
AUTOMOUNT_TIMER=$ROOT/etc/systemd/system/homestream-automount.timer
AUTOMOUNT_RULE=$ROOT/etc/udev/rules.d/99-homestream-automount.rules
DRIVES_DIR=/media/homestream
DISK_HELPER=$ROOT/usr/local/sbin/homestream-disk
DISK_SUDOERS=$ROOT/etc/sudoers.d/homestream-disk

setup_automount() {
  msg "Otomatik disk bağlama kuruluyor ($DRIVES_DIR)"
  if ! command -v ntfs-3g >/dev/null 2>&1 || ! command -v mkfs.exfat >/dev/null 2>&1; then
    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ntfs-3g exfatprogs >/dev/null 2>&1 || true
  fi
  $SUDO mkdir -p "$(dirname "$AUTOMOUNT_BIN")" "$(dirname "$AUTOMOUNT_RULE")"
  cat <<'AMEOF' | sed "s/@UID@/$(id -u "$RUN_USER")/; s/@GID@/$(getent group "$RUN_GROUP" | cut -d: -f3)/" | $SUDO tee "$AUTOMOUNT_BIN" >/dev/null
#!/bin/bash
# Home Stream: mount every unmounted data partition under /media/homestream/<name>.
set -u
BASE=/media/homestream
OWN_UID=@UID@
OWN_GID=@GID@
MIN_BYTES=$((2 * 1024 * 1024 * 1024))
SKIP=/run/homestream-automount.skip
EJECTED=/run/homestream-automount.ejected
exec 9>/run/homestream-automount.lock
flock 9
mkdir -p "$BASE"

# disks ejected from the app stay unmounted until they are unplugged
if [ -s "$EJECTED" ]; then
  tmp=$(mktemp)
  while IFS= read -r l; do [ -b "${l%%:*}" ] && printf '%s\n' "$l"; done < "$EJECTED" > "$tmp"
  cat "$tmp" > "$EJECTED"; rm -f "$tmp"
fi

# 1) drop mounts whose disk was unplugged, and leftover empty folders
for d in "$BASE"/*/; do
  d=${d%/}
  [ -d "$d" ] || continue
  if mountpoint -q "$d"; then
    src=$(findmnt -no SOURCE --mountpoint "$d" 2>/dev/null)
    case "$src" in /dev/*) [ -b "$src" ] || umount -l "$d" ;; esac
  fi
  mountpoint -q "$d" || rmdir "$d" 2>/dev/null
done

# 2) disks that hold the running system are never touched
sys_disks=" "
for mp in / /boot /boot/efi /home /var /usr; do
  src=$(findmnt -no SOURCE --mountpoint "$mp" 2>/dev/null) || continue
  case "$src" in /dev/*) ;; *) continue ;; esac
  for parent in $(lsblk -nso NAME,TYPE -p "$src" 2>/dev/null | awk '$2=="disk"{print $1}'); do
    sys_disks="$sys_disks$parent "
  done
done

# 3) mount the rest
lsblk -bPnpo NAME,TYPE,FSTYPE,SIZE,LABEL,UUID,PARTTYPE,PKNAME,MOUNTPOINT | while read -r line; do
  NAME= TYPE= FSTYPE= SIZE=0 LABEL= UUID= PARTTYPE= PKNAME= MOUNTPOINT=
  eval "$line"
  [ "$TYPE" = part ] || [ "$TYPE" = disk ] || { [ -n "${HS_AUTOMOUNT_TEST:-}" ] && [ "$TYPE" = loop ]; } || continue
  if [ -z "$FSTYPE" ]; then
    FSTYPE=$(blkid -o value -s TYPE "$NAME" 2>/dev/null)
    LABEL=$(blkid -o value -s LABEL "$NAME" 2>/dev/null)
    UUID=$(blkid -o value -s UUID "$NAME" 2>/dev/null)
  fi
  [ -z "$MOUNTPOINT" ] || continue
  case "$FSTYPE" in ntfs|exfat|vfat|ext4|ext3|ext2|btrfs|xfs) ;; *) continue ;; esac
  [ "${SIZE:-0}" -ge "$MIN_BYTES" ] || continue
  disk=${PKNAME:-$NAME}
  case "$sys_disks" in *" $disk "*) continue ;; esac
  case "${PARTTYPE,,}" in
    c12a7328-f81f-11d2-ba4b-00a0c93ec93b|e3c9e316-0b5c-4db8-817d-f92df00215ae|de94bba4-06d1-4d40-a16a-bfd50179d6ac|0x27|0xef) continue ;;
  esac
  findmnt -rn -S "$NAME" >/dev/null 2>&1 && continue
  grep -qsxF "$NAME:$UUID" "$SKIP" && continue
  grep -qsxF "$NAME:$UUID" "$EJECTED" && continue
  grep -qsE "^[[:space:]]*(UUID=$UUID|$NAME)[[:space:]]" /etc/fstab && [ -n "$UUID" ] && continue

  name=${LABEL:-Disk-${UUID:0:8}}
  name=$(printf '%s' "$name" | tr '/\\' '__' | sed 's/^\.*//')
  [ -n "$name" ] || name=Disk
  dir="$BASE/$name"; n=2
  while mountpoint -q "$dir" || [ -n "$(ls -A "$dir" 2>/dev/null)" ]; do
    dir="$BASE/$name-$n"; n=$((n + 1))
  done
  mkdir -p "$dir"
  own="uid=$OWN_UID,gid=$OWN_GID,umask=022"
  ok=1
  case "$FSTYPE" in
    ntfs)
      mount -t ntfs3 -o "$own,noatime" "$NAME" "$dir" 2>/dev/null ||
      mount -t ntfs3 -o "$own,noatime,force" "$NAME" "$dir" 2>/dev/null ||
      mount -t ntfs-3g -o "$own,noatime" "$NAME" "$dir" 2>/dev/null ||
      mount -t ntfs-3g -o "$own,ro" "$NAME" "$dir" 2>/dev/null || ok=0 ;;
    exfat|vfat)
      mount -o "$own,noatime" "$NAME" "$dir" 2>/dev/null || ok=0 ;;
    *)
      mount -o noatime "$NAME" "$dir" 2>/dev/null || ok=0 ;;
  esac
  # an operating system partition (old Linux/Windows install) is not a media disk
  if [ "$ok" = 1 ] && { [ -e "$dir/etc/os-release" ] || [ -d "$dir/Windows/System32" ]; }; then
    umount "$dir" 2>/dev/null; rmdir "$dir" 2>/dev/null
    echo "$NAME:$UUID" >> "$SKIP"
    logger -t homestream-automount "atlandı (işletim sistemi bölümü): $NAME"
    continue
  fi
  if [ "$ok" = 1 ]; then
    logger -t homestream-automount "$NAME ($FSTYPE) -> $dir"
  else
    rmdir "$dir" 2>/dev/null
    echo "$NAME:$UUID" >> "$SKIP"
    logger -t homestream-automount "bağlanamadı: $NAME ($FSTYPE)"
  fi
done
exit 0
AMEOF
  $SUDO chmod 0755 "$AUTOMOUNT_BIN"
  setup_disk_helper
  printf '%s\n' "[Unit]" "Description=Home Stream otomatik disk bağlama" "After=local-fs.target" "" \
    "[Service]" "Type=oneshot" "ExecStartPre=/bin/sleep 2" "ExecStart=/usr/local/sbin/homestream-automount" "" \
    "[Install]" "WantedBy=multi-user.target" | $SUDO tee "$AUTOMOUNT_UNIT" >/dev/null
  printf '%s\n' "[Unit]" "Description=Home Stream otomatik disk bağlama (yedek kontrol)" "" \
    "[Timer]" "OnBootSec=30" "OnUnitActiveSec=60" "" "[Install]" "WantedBy=timers.target" | $SUDO tee "$AUTOMOUNT_TIMER" >/dev/null
  printf '%s\n' 'ACTION=="add|remove|change", SUBSYSTEM=="block", RUN+="/usr/bin/systemctl --no-block start homestream-automount.service"' | $SUDO tee "$AUTOMOUNT_RULE" >/dev/null
  $SUDO systemctl daemon-reload
  $SUDO systemctl enable homestream-automount.service homestream-automount.timer >/dev/null 2>&1 || true
  $SUDO systemctl start homestream-automount.timer >/dev/null 2>&1 || true
  $SUDO udevadm control --reload-rules 2>/dev/null || true
  $SUDO systemctl start homestream-automount.service || warn "Disk bağlama çalıştırılamadı (journalctl -t homestream-automount)."
}

# Home Dosya: "Güvenle çıkar" / "Bağla" for disks, run by the service through sudo.
setup_disk_helper() {
  cat <<'DHEOF' | $SUDO tee "$DISK_HELPER" >/dev/null
#!/bin/bash
# Home Stream: eject or mount a data disk from the apps.
#   homestream-disk eject /media/homestream/<disk>
#   homestream-disk mount /dev/sdX1
set -u
BASE=/media/homestream
EJECTED=/run/homestream-automount.ejected
SKIP=/run/homestream-automount.skip
case "${1:-}" in
  eject)
    dir=$(realpath -m -- "${2:-}")
    [ "$(dirname "$dir")" = "$BASE" ] || { echo "geçersiz disk"; exit 2; }
    mountpoint -q "$dir" || { echo "disk bağlı değil"; exit 3; }
    src=$(findmnt -no SOURCE --mountpoint "$dir")
    uuid=$(blkid -o value -s UUID "$src" 2>/dev/null)
    sync
    if ! err=$(umount "$dir" 2>&1); then
      case "$err" in *busy*) echo "busy" ;; *) echo "$err" ;; esac
      exit 4
    fi
    rmdir "$dir" 2>/dev/null
    printf '%s:%s\n' "$src" "$uuid" >> "$EJECTED"
    # power the USB disk off when nothing else on it is mounted
    disk=$(lsblk -no PKNAME "$src" 2>/dev/null | head -n1)
    if [ -n "$disk" ] && ! lsblk -no MOUNTPOINT "/dev/$disk" 2>/dev/null | grep -q . &&
       [ "$(lsblk -dno TRAN "/dev/$disk" 2>/dev/null)" = usb ] && command -v udisksctl >/dev/null 2>&1; then
      udisksctl power-off -b "/dev/$disk" --no-user-interaction >/dev/null 2>&1 || true
    fi
    logger -t homestream-disk "çıkarıldı: $src ($dir)"
    ;;
  mount)
    dev="${2:-}"
    case "$dev" in /dev/sd*|/dev/nvme*|/dev/mmcblk*|/dev/vd*|/dev/hd*) ;; *) echo "geçersiz disk"; exit 2 ;; esac
    [ -b "$dev" ] || { echo "disk bulunamadı"; exit 3; }
    for f in "$EJECTED" "$SKIP"; do
      [ -f "$f" ] && sed -i "\\#^$dev:#d" "$f"
    done
    /usr/local/sbin/homestream-automount
    findmnt -rn -S "$dev" >/dev/null 2>&1 || { echo "disk bağlanamadı (dosya sistemi tanınmadı ya da sistem diski)"; exit 4; }
    ;;
  *) echo "kullanım: homestream-disk eject <klasör> | mount <aygıt>"; exit 2 ;;
esac
exit 0
DHEOF
  $SUDO chmod 0755 "$DISK_HELPER"
  local tmp
  tmp=$(mktemp)
  printf '%s ALL=(root) NOPASSWD: %s\n' "$RUN_USER" "/usr/local/sbin/homestream-disk" > "$tmp"
  if command -v visudo >/dev/null 2>&1 && ! visudo -cqf "$tmp" >/dev/null 2>&1; then
    warn "Disk izni (sudoers) yazılamadı; uygulamadan disk çıkarma çalışmayacak."
  else
    $SUDO mkdir -p "$(dirname "$DISK_SUDOERS")"
    $SUDO install -m 0440 "$tmp" "$DISK_SUDOERS"
  fi
  rm -f "$tmp"
}

remove_automount() {
  $SUDO systemctl disable --now homestream-automount.timer homestream-automount.service 2>/dev/null || true
  $SUDO rm -f "$AUTOMOUNT_BIN" "$AUTOMOUNT_UNIT" "$AUTOMOUNT_TIMER" "$AUTOMOUNT_RULE" "$DISK_HELPER" "$DISK_SUDOERS"
  $SUDO udevadm control --reload-rules 2>/dev/null || true
}

uninstall() {
  msg "Home Stream kaldırılıyor…"
  $SUDO systemctl disable --now "$SERVICE" 2>/dev/null || true
  $SUDO rm -f "$UNIT_FILE"
  $SUDO systemctl daemon-reload || true
  $SUDO rm -rf "$INSTALL_DIR"
  remove_automount
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
# music app: songs go to <library>/Müzik (also on updates of older installs)
if [ ! -d "$LIBRARY/Müzik" ]; then
  as_user mkdir -p "$LIBRARY/Müzik" || true
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
Environment=\"HOMESTREAM_DRIVES=$DRIVES_DIR\"
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

if [ "${HOMESTREAM_AUTOMOUNT:-yes}" != "no" ]; then
  setup_automount
fi

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
echo "  Müzik klasörü        : $LIBRARY/Müzik"
echo "  Takılan diskler      : $DRIVES_DIR altında otomatik bağlanır ve kütüphaneye eklenir"
if [ "$SAMBA_OK" = 1 ]; then
  echo "  Windows Gezgini      : \\\\$IP\\HomeStream   (kullanıcı adı: $RUN_USER)"
fi
echo
echo "  Filmleri 'Filmler', dizileri 'Diziler' klasörüne koyun; birkaç dakika içinde"
echo "  uygulamada görünürler (veya uygulamadan 'Kütüphaneyi Tara' deyin)."
echo "  Kayıtlar: journalctl -u $SERVICE -f      Güncelleme: bu betiği tekrar çalıştırın."
echo
