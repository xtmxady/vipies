#!/usr/bin/env bash
# ============================================================
# vipies — Modul 13: Migrasi VPS (install Hermes + 9router + restore config)
# Dipakai di VPS BARU setelah modul 1-12. Menyiapkan Hermes,
# 9router, PM2, rclone, lalu restore config server dari R2.
# ============================================================
set -u
NC='\033[0m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
log() { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
err() { echo -e "${RED}✗${NC} $*"; }

# ---------- 1. Install rclone (kalau belum) ----------
if ! command -v rclone >/dev/null 2>&1; then
  log "Install rclone..."
  curl -fsSL https://rclone.org/install.sh | bash >/dev/null 2>&1 || { err "Gagal install rclone."; exit 1; }
else
  log "rclone sudah ada ($(rclone --version | head -1))"
fi

# ---------- 2. Install Hermes (installer resmi) ----------
if ! command -v hermes >/dev/null 2>&1; then
  log "Install Hermes Agent..."
  curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash >/dev/null 2>&1 || { err "Gagal install Hermes."; exit 1; }
else
  log "Hermes sudah ada ($(hermes --version 2>&1 | head -1))"
fi

# ---------- 3. Install 9router + PM2 (npm global) ----------
if ! command -v 9router >/dev/null 2>&1; then
  log "Install 9router..."
  npm i -g 9router >/dev/null 2>&1 || { err "Gagal install 9router."; exit 1; }
else
  log "9router sudah ada"
fi
if ! command -v pm2 >/dev/null 2>&1; then
  log "Install PM2..."
  npm i -g pm2 >/dev/null 2>&1 || { err "Gagal install PM2."; exit 1; }
else
  log "PM2 sudah ada"
fi

# ---------- 4. Restore config dari R2 ----------
echo ""
echo "=============================================="
echo "  Restore config server dari R2"
echo "  (butuh remote rclone 'r2' — bucket 'hermes')"
echo "=============================================="
if rclone lsf r2:hermes/server-config >/dev/null 2>&1; then
  read -rp "Tanggal backup config [YYYY-MM-DD, kosong = terbaru]: " R_DATE
  # Pakai script dari repo (scripts/migrate-restore.sh) — salin ke /root dulu
  if [ -f /root/migrate-restore.sh ]; then
    bash /root/migrate-restore.sh "${R_DATE:-}"
  elif [ -f "$(dirname "$0")/../scripts/migrate-restore.sh" ]; then
    bash "$(dirname "$0")/../scripts/migrate-restore.sh" "${R_DATE:-}"
  else
    warn "migrate-restore.sh tidak ditemukan — download dari GitHub dulu?"
    warn "  wget -O /root/migrate-restore.sh https://raw.githubusercontent.com/xtmxady/vipies/main/scripts/migrate-restore.sh"
  fi
else
  warn "Remote r2 belum bisa diakses — lewati restore."
  warn "Konfigurasi dulu: rclone config (remote 'r2' → bucket 'hermes')"
fi

# ---------- 5. Aktifkan service ----------
log "Restart service..."
systemctl restart nginx fail2ban 2>/dev/null || true
command -v pm2 >/dev/null 2>&1 && pm2 resurrect 2>/dev/null || true

echo ""
log "Modul 13 selesai. Hermes, 9router, PM2, rclone siap."
log "Config dipulihkan (kalau remote r2 tersedia)."
echo "  - Jalankan gateway Hermes:  hermes gateway run"
echo "  - Cek PM2:                  pm2 status"
echo "  - Cek Nginx:                nginx -t; systemctl status nginx"