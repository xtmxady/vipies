#!/usr/bin/env bash
# ============================================================
# migrate-restore.sh — restore config server (jalankan di VPS BARU)
# Download ZIP config dari R2 → taruh tiap bagian ke folder target.
# Prasyarat di VPS baru: rclone terpasang & remote "r2" sudah ada.
# ============================================================
set -u
R2="r2:hermes/server-config"
STAGE="/root/.migrate-restore"
ZIP="$STAGE/config.zip"
LOG="/root/migrate-restore.log"

# --- argumen: tanggal backup (format YYYY-MM-DD), default: paling baru ---
DATE="${1:-}"
mkdir -p "$STAGE"
echo "== migrate-restore $(date +%F) ==" > "$LOG"

# cari zip terbaru kalau tanggal tidak dikasih
if [ -z "$DATE" ]; then
  DATE=$(rclone lsf "$R2" --files-only 2>/dev/null | grep -oE 'migrate-config-[0-9-]+' | sort | tail -1 | sed 's/migrate-config-//')
fi
[ -z "$DATE" ] && { echo "❌ Tidak ada backup config di R2."; exit 1; }

echo ">> Download migrate-config-${DATE}.zip ..." | tee -a "$LOG"
rclone copyto "$R2/migrate-config-${DATE}.zip" "$ZIP" >> "$LOG" 2>&1 || { echo "❌ Download gagal."; exit 1; }
cd "$STAGE" && unzip -oq "$ZIP" && echo ">> Extract OK" | tee -a "$LOG"

restore() { # $1=src(rel) $2=dest
  [ -e "$STAGE/$1" ] && { mkdir -p "$2"; cp -a "$STAGE/$1" "$2/"; echo "   ✔ $1 → $2" | tee -a "$LOG"; }
}

echo "== Restore config ==" | tee -a "$LOG"

# ---------- Hermes ----------
for item in config.yaml SOUL.md install_id state.db memories skills cron sessions pairing platforms hooks scripts kanban.db; do
  [ -e "$STAGE/hermes/$item" ] && { mkdir -p "$HOME/.hermes"; cp -a "$STAGE/hermes/$item" "$HOME/.hermes/"; echo "   ✔ hermes/$item" | tee -a "$LOG"; }
done

# ---------- 9router ----------
restore "9router" "$HOME/.9router"

# ---------- Nginx ----------
restore "nginx/nginx.conf" "/etc/nginx"
restore "nginx/sites-available" "/etc/nginx"
restore "nginx/sites-enabled" "/etc/nginx"
restore "nginx/conf.d" "/etc/nginx"
restore "nginx/snippets" "/etc/nginx"

# ---------- LetsEncrypt certs ----------
restore "letsencrypt" "/etc"

# ---------- cron ----------
[ -f "$STAGE/crontab.txt" ] && { crontab "$STAGE/crontab.txt" 2>/dev/null; echo "   ✔ crontab" | tee -a "$LOG"; }

# ---------- fail2ban ----------
restore "fail2ban/jail.local" "/etc/fail2ban"
restore "fail2ban/filter.d" "/etc/fail2ban"
restore "fail2ban/action.d" "/etc/fail2ban"

# ---------- envs (taruh ke path asli?) — tidak, biar user pilih manual ----------
mkdir -p /root/migrate-envs
[ -d "$STAGE/envs" ] && cp -a "$STAGE/envs/." /root/migrate-envs/ && echo "   ✔ envs → /root/migrate-envs/ (periksa & salin manual ke situs)" | tee -a "$LOG"
[ -d "$STAGE/rclone" ] && { mkdir -p "$HOME/.config/rclone"; cp -a "$STAGE/rclone/." "$HOME/.config/rclone/"; echo "   ✔ rclone.conf" | tee -a "$LOG"; }

# ---------- MySQL root + vipies creds ----------
[ -f "$STAGE/mysql-root.cnf" ] && { cp -a "$STAGE/mysql-root.cnf" "$HOME/.my.cnf"; chmod 600 "$HOME/.my.cnf"; echo "   ✔ mysql-root.cnf → ~/.my.cnf (chmod 600)" | tee -a "$LOG"; }
[ -f "$STAGE/vipies.conf" ] && { cp -a "$STAGE/vipies.conf" /etc/vipies.conf; echo "   ✔ vipies.conf" | tee -a "$LOG"; }

# ---------- PM2 restore ----------
if [ -f "$STAGE/pm2/dump.pm2" ]; then
  mkdir -p "$HOME/.pm2"
  cp -a "$STAGE/pm2/dump.pm2" "$HOME/.pm2/"
  pm2 resurrect 2>/dev/null && echo "   ✔ pm2 resurrect" | tee -a "$LOG" || echo "   ⚠️ pm2 resurrect gagal — install PM2 dulu" | tee -a "$LOG"
fi

echo ""
echo "✅ Selesai. Catatan:" | tee -a "$LOG"
echo "   - Hermes/9router/Nginx/cron/fail2ban/certs sudah dipulihkan" | tee -a "$LOG"
echo "   - PM2: aplikasi perlu path folder yang sama di VPS baru (mis. /var/www/seribukafetrk.com)" | tee -a "$LOG"
echo "   - envs di /root/migrate-envs/ — salin manual ke masing-masing situs setelah folder situs ada" | tee -a "$LOG"
echo "   - Restart service: systemctl restart nginx fail2ban; pm2 restart all" | tee -a "$LOG"