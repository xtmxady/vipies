#!/bin/bash
# ============================================================
#  vipies — 07-backup.sh
#  Install rclone + pasang script backup R2 (dari /root/r2-backup.sh)
#  + cron harian tengah malam
# ============================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source modules/lib.sh

if [ "${R2_ENABLED:-0}" != "1" ]; then
  warn "R2_ENABLED != 1 — lewati. Set .env R2_ENABLED=1 untuk aktifkan."
  return 0 2>/dev/null || exit 0
fi

step "Menginstall rclone..."
if ! command -v rclone >/dev/null 2>&1; then
  curl -fsSL https://rclone.org/install.sh | bash >/dev/null 2>&1
fi
ok "rclone $(rclone --version | head -1 | grep -oE '[0-9.]+') terinstall"

step "Memeriksa konfigurasi remote rclone ($R2_REMOTE_NAME -> $R2_BUCKET)..."
# Auto-create remote rclone dari .env bila credentials tersedia
if ! rclone lsd "${R2_REMOTE_NAME}:" >/dev/null 2>&1; then
  if [ -n "${R2_ACCOUNT_ID:-}" ] && [ -n "${R2_ACCESS_KEY_ID:-}" ] && [ -n "${R2_SECRET_ACCESS_KEY:-}" ]; then
    ok "Membuat remote rclone '$R2_REMOTE_NAME' dari .env..."
    rclone config create "$R2_REMOTE_NAME" s3 \
      provider "Cloudflare" \
      access_key_id "${R2_ACCESS_KEY_ID}" \
      secret_access_key "${R2_SECRET_ACCESS_KEY}" \
      endpoint "https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com" \
      >/dev/null 2>&1
    rclone lsd "${R2_REMOTE_NAME}:" >/dev/null 2>&1 \
      && ok "Remote '$R2_REMOTE_NAME' dibuat & terhubung" \
      || warn "Remote dibuat tapi belum terhubung — cek credentials"
  else
    warn "Remote '$R2_REMOTE_NAME' belum dikonfigurasi & R2 credentials kosong di .env."
    warn "Isi .env: R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, lalu jalankan ulang modul 07."
  fi
fi

step "Memastikan r2-sites.conf (fallback DB config)..."
# Auto-scan /var/www/ untuk situs WordPress (DB dari wp-config) & custom
# User bisa menambah baris manual: <site>|<db>|<user>|<pass> bila DB bukan dari .env
if [ ! -f /root/r2-sites.conf ]; then
  : > /root/r2-sites.conf
  for webdir in /var/www/*/; do
    site=$(basename "$webdir" | tr -d '/')
    [ -d "$webdir/wp-content" ] || continue
    # Skip adminer/html
    case "$site" in adminer|html) continue;; esac
    if [ -f "$webdir/wp-config.php" ]; then
      db=$(grep "DB_NAME" "$webdir/wp-config.php" | head -1 | cut -d"'" -f4)
      du=$(grep "DB_USER" "$webdir/wp-config.php" | head -1 | cut -d"'" -f4)
      dp=$(grep "DB_PASSWORD" "$webdir/wp-config.php" | head -1 | cut -d"'" -f4)
      [ -n "$db" ] && echo "${site}|${db}|${du}|${dp}" >> /root/r2-sites.conf
    fi
  done
  ok "r2-sites.conf dibuat (auto-scan dari wp-config.php)"
else
  ok "r2-sites.conf sudah ada"
fi

step "Memasang script backup + cron..."
# JIKA VPS BARU (tidak ada script existing), salin template dari repo.
# Di VPS ini kita pakai /root/r2-backup.sh yang sudah ada.
if [ -f /root/r2-backup.sh ]; then
  ok "Menggunakan /root/r2-backup.sh yang sudah ada"
else
  if [ -f templates/r2-backup.sh ]; then
    cp templates/r2-backup.sh /root/r2-backup.sh
    chmod +x /root/r2-backup.sh
    ok "Script backup dipasang dari template"
  else
    warn "r2-backup.sh tidak ada — install manual"
  fi
fi

# Cron 00:00 harian
if ! crontab -l 2>/dev/null | grep -q 'r2-backup.sh'; then
  ( crontab -l 2>/dev/null; echo "0 0 * * * bash /root/r2-backup.sh >> /var/log/r2-backup-cron.log 2>&1" ) | crontab -
  ok "Cron backup dipasang: 0 0 * * * (tiap tengah malam)"
else
  ok "Cron backup sudah ada"
fi

ok "Module 07 selesai — Backup R2 + cron aktif."
