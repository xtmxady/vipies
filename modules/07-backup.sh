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
if ! rclone lsd "${R2_REMOTE_NAME}:" >/dev/null 2>&1; then
  warn "Remote '$R2_REMOTE_NAME' belum dikonfigurasi."
  warn "Jalankan: rclone config (provider S3, R2 Cloudflare)"
  warn "Atau isi .env dengan R2 token lalu jalankan:"
  echo "  rclone config create $R2_REMOTE_NAME s3 provider 'Cloudflare' \\"
  echo "    access_key_id 'AKID' secret_access_key 'SECRET' \\"
  echo "    endpoint 'https://<ACCOUNT>.r2.cloudflarestorage.com'"
  return 0 2>/dev/null || exit 0
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
