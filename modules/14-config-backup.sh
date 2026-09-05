#!/usr/bin/env bash
# ============================================================
# vipies — Modul 14: Backup/Restore Config Server (TERPISAH)
# Backup & pulihkan konfigurasi server ke/dari R2:
#   Hermes (~/.hermes), 9router (~/.9router), Nginx, LetsEncrypt,
#   PM2 dump, crontab, fail2ban, envs situs, rclone.conf,
#   mysql-root.cnf, vipies.conf + migrate-restore.sh
# Jalan SETELAH modul 13 (9router + Hermes terinstall).
# ============================================================
set -u
cd "$(dirname "$0")/.."
source modules/lib.sh

NC='\033[0m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
log() { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
err() { echo -e "${RED}✗${NC} $*"; }

ACTION=""
if [ $# -ge 1 ]; then ACTION="$1"; fi
while [ -z "$ACTION" ]; do
  read -rp "Pilih aksi [backup/restore]: " ACTION
done

# ---------- Butuh rclone ----------
if ! command -v rclone >/dev/null 2>&1; then
  warn "rclone belum ada — install dulu..."
  curl -fsSL https://rclone.org/install.sh | bash >/dev/null 2>&1 || { err "Gagal install rclone."; exit 1; }
fi
if ! rclone lsf r2:hermes/server-config >/dev/null 2>&1; then
  err "Remote rclone 'r2' (bucket 'hermes') belum bisa diakses."
  err "Konfigurasi dulu: rclone config (remote 'r2' → bucket 'hermes')"
  exit 1
fi

R2="r2:hermes/server-config"
STAMP=$(date +%F)
STAGE="/root/.migrate-backup"
LOG="/root/migrate-backup.log"
ZIP="/root/migrate-config-${STAMP}.zip"

backup() {
  echo "== migrate-backup ${STAMP} $(date +%T) ==" >> "$LOG"
  rm -rf "$STAGE"; mkdir -p "$STAGE"

  # Hermes (config, memories, skills, sessions, state, cron, credentials, dll)
  [ -d "$HOME/.hermes" ] && cp -a "$HOME/.hermes" "$STAGE/hermes"
  rm -rf "$STAGE/hermes/logs" "$STAGE/hermes/audio_cache" "$STAGE/hermes/cache" 2>/dev/null

  # 9router
  [ -d "$HOME/.9router" ] && cp -a "$HOME/.9router" "$STAGE/9router"
  rm -rf "$STAGE/9router/logs" 2>/dev/null

  # Nginx
  mkdir -p "$STAGE/nginx"
  cp -a /etc/nginx/nginx.conf "$STAGE/nginx/" 2>/dev/null
  cp -a /etc/nginx/sites-available "$STAGE/nginx/" 2>/dev/null
  cp -a /etc/nginx/sites-enabled "$STAGE/nginx/" 2>/dev/null
  cp -a /etc/nginx/conf.d "$STAGE/nginx/" 2>/dev/null
  cp -a /etc/nginx/snippets "$STAGE/nginx/" 2>/dev/null

  # LetsEncrypt
  cp -a /etc/letsencrypt "$STAGE/letsencrypt" 2>/dev/null

  # PM2 dump
  mkdir -p "$STAGE/pm2"
  [ -f "$HOME/.pm2/dump.pm2" ] && cp -a "$HOME/.pm2/dump.pm2" "$STAGE/pm2/"
  [ -f "$HOME/.pm2/dump.pm2.bak" ] && cp -a "$HOME/.pm2/dump.pm2.bak" "$STAGE/pm2/"

  # Crontab
  crontab -l > "$STAGE/crontab.txt" 2>/dev/null || true

  # fail2ban
  mkdir -p "$STAGE/fail2ban"
  cp -a /etc/fail2ban/jail.local "$STAGE/fail2ban/" 2>/dev/null
  cp -a /etc/fail2ban/filter.d "$STAGE/fail2ban/" 2>/dev/null
  cp -a /etc/fail2ban/action.d "$STAGE/fail2ban/" 2>/dev/null

  # envs situs
  mkdir -p "$STAGE/envs"
  for envfile in $(find /var/www -maxdepth 4 -name ".env" 2>/dev/null); do
    rel=$(echo "$envfile" | sed 's|/var/www/||; s|/|_|g')
    cp -a "$envfile" "$STAGE/envs/${rel}"
  done
  for cfg in $(find /var/www -maxdepth 4 -name "config.json" -path "*scraper*" 2>/dev/null); do
    rel=$(echo "$cfg" | sed 's|/var/www/||; s|/|_|g')
    cp -a "$cfg" "$STAGE/envs/${rel}"
  done

  # rclone.conf
  [ -f "$HOME/.config/rclone/rclone.conf" ] && { mkdir -p "$STAGE/rclone"; cp -a "$HOME/.config/rclone/rclone.conf" "$STAGE/rclone/"; }

  # MySQL root + vipies creds
  [ -f "$HOME/.my.cnf" ] && cp -a "$HOME/.my.cnf" "$STAGE/mysql-root.cnf"
  [ -f /etc/vipies.conf ] && cp -a /etc/vipies.conf "$STAGE/vipies.conf"

  # migrate-restore.sh (self-contained)
  [ -f "$HOME/migrate-restore.sh" ] && cp -a "$HOME/migrate-restore.sh" "$STAGE/migrate-restore.sh"

  cd "$STAGE" && zip -rq "$ZIP" . 2>/dev/null
  rclone copyto "$ZIP" "${R2}/migrate-config-${STAMP}.zip" >> "$LOG" 2>&1
  log "Migrate config ${STAMP} ($(du -h "$ZIP" | cut -f1)) terupload"
  rm -f "$ZIP"

  # Retensi > 7 hari
  rclone delete "$R2" --min-age "7d" >> "$LOG" 2>&1 || true
  log "Backup config selesai. Retensi 7 hari."
}

restore() {
  read -rp "Tanggal backup config [YYYY-MM-DD, kosong = terbaru]: " R_DATE
  if [ -f /root/migrate-restore.sh ]; then
    bash /root/migrate-restore.sh "${R_DATE:-}"
  elif [ -f "$(dirname "$0")/../scripts/migrate-restore.sh" ]; then
    bash "$(dirname "$0")/../scripts/migrate-restore.sh" "${R_DATE:-}"
  else
    warn "migrate-restore.sh tidak ditemukan — download dari GitHub dulu?"
    warn "  wget -O /root/migrate-restore.sh https://raw.githubusercontent.com/xtmxady/vipies/main/scripts/migrate-restore.sh"
  fi
}

case "$ACTION" in
  backup)  backup ;;
  restore) restore ;;
  *) err "Aksi tidak dikenal: $ACTION (pilih backup/restore)"; exit 1 ;;
esac