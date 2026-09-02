#!/bin/bash
# ============================================================
#  vipies — 08-monitoring.sh
#  Monitoring layanan + notif Telegram (cron tiap 30 menit)
#  Credentials disimpan di /etc/vipies.conf (dibaca saat cron,
#  karena cron tidak mewarisi env dari setup.sh)
# ============================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source modules/lib.sh

# Tulis file config terpusat (idempotent — hanya jika ada nilai)
step "Menulis /etc/vipies.conf (credentials utk cron)..."
mkdir -p /etc/vipies
cat > /etc/vipies.conf <<CONF
# vipies — credentials (dibaca oleh script yang jalan via cron)
# Di-generate otomatis oleh setup.sh dari .env. JANGAN edit manual.
TG_BOT_TOKEN=${TG_BOT_TOKEN:-}
TG_CHAT_ID=${TG_CHAT_ID:-}
R2_REMOTE_NAME=${R2_REMOTE_NAME:-r2}
R2_BUCKET=${R2_BUCKET:-hermes}
CONF
chmod 600 /etc/vipies.conf
ok "/etc/vipies.conf ditulis (chmod 600)"

step "Membuat script monitor (/usr/local/bin/vipies-monitor)..."
cat > /usr/local/bin/vipies-monitor <<'MON'
#!/bin/bash
# vipies-monitor — cek kesehatan layanan, kirim alarm ke Telegram jika down
# Dibaca config dari /etc/vipies.conf (karena cron tidak mewarisi env).
MON

cat >> /usr/local/bin/vipies-monitor <<'MON'
[ -f /etc/vipies.conf ] && source /etc/vipies.conf
TG_BOT="${TG_BOT_TOKEN:-}"
TG_CHAT="${TG_CHAT_ID:-}"
[ -z "$TG_BOT" ] || [ -z "$TG_CHAT" ] && exit 0

check() { systemctl is-active --quiet "$1"; }

ALERTS=""
# Deteksi service php-fpm otomatis
PHP_FPM=$(ls /lib/systemd/system/php*-fpm.service 2>/dev/null | head -1 | xargs -n1 basename 2>/dev/null | sed 's/.service//' || echo php8.3-fpm)
for svc in nginx mysql "$PHP_FPM"; do
  check "$svc" || ALERTS+="\U0001F534 <b>$svc</b> DOWN!\n"
done

if command -v pm2 >/dev/null 2>&1; then
  DEAD=$(pm2 jlist 2>/dev/null | grep -o '"status":"[a-z]*"' | grep -cv online || true)
  [ "$DEAD" != "0" ] && ALERTS+="\U0001F534 PM2: $DEAD proses mati\n"
fi

RAM_USED=$(free -m | awk '/^Mem:/{printf "%d", $3}')
RAM_TOT=$(free -m | awk '/^Mem:/{printf "%d", $2}')
DISK_USED=$(df / | awk 'NR==2{print $5}')
LOAD=$(uptime | grep -oE 'load average:.*' | sed 's/load average: //')

# Cek status backup (jika ada log backup terakhir)
BACKUP_TXT=""
[ -f /root/backup-report.txt ] && BACKUP_TXT="\nLast backup: $(tail -3 /root/backup-report.txt | tr '\n' ' ')"

if [ -n "$ALERTS" ]; then
  MSG="⚠️ <b>MONITOR VIPIES</b> [ALARM]\n$ALERTS\nRAM: ${RAM_USED}/${RAM_TOT}MB | Disk: $DISK_USED | Load: $LOAD$BACKUP_TXT"
else
  MSG="✅ <b>MONITOR VIPIES</b> — semua normal\nRAM: ${RAM_USED}/${RAM_TOT}MB | Disk: $DISK_USED | Load: $LOAD$BACKUP_TXT"
fi
curl -s -o /dev/null "https://api.telegram.org/bot${TG_BOT}/sendMessage" \
  -d "chat_id=${TG_CHAT}" --data-urlencode "text=${MSG}" -d "parse_mode=HTML" 2>/dev/null || true
MON
chmod +x /usr/local/bin/vipies-monitor

step "Memasang cron monitoring (tiap 30 menit)..."
if ! crontab -l 2>/dev/null | grep -q 'vipies-monitor'; then
  ( crontab -l 2>/dev/null; echo "*/30 * * * * /usr/local/bin/vipies-monitor >/dev/null 2>&1" ) | crontab -
  ok "Cron monitoring aktif (tiap 30 menit)"
else
  ok "Cron monitoring sudah ada"
fi

# Jalankan sekali untuk test
if [ -n "${TG_BOT_TOKEN:-}" ]; then
  ok "Menjalankan monitor test..."
  /usr/local/bin/vipies-monitor 2>/dev/null || true
else
  warn "TG_BOT_TOKEN kosong — lewati test monitor (isi .env)"
fi

ok "Module 08 selesai — Monitoring + notif Telegram."
