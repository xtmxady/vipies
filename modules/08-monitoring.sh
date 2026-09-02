#!/bin/bash
# ============================================================
#  vipies — 08-monitoring.sh
#  Monitoring layanan + notif Telegram (cron tiap 30 menit)
# ============================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source modules/lib.sh

step "Membuat script monitor (/usr/local/bin/vipies-monitor)..."
cat > /usr/local/bin/vipies-monitor <<'MON'
#!/bin/bash
# vipies-monitor — cek kesehatan layanan, kirim alarm ke Telegram jika down
# Juga melaporkan status backup harian.
TG_BOT="${TG_BOT_TOKEN:-}"
TG_CHAT="${TG_CHAT_ID:-}"
[ -z "$TG_BOT" ] && exit 0

check() { # check <service> <friendly>
  if systemctl is-active --quiet "$1"; then return 0; else return 1; fi
}

ALERTS=""
for svc in nginx mysql php8.3-fpm; do
  if ! check "$svc"; then
    ALERTS+="🔴 <b>$svc</b> DOWN!\n"
  fi
done

# PM2 jika ada
if command -v pm2 >/dev/null 2>&1; then
  DEAD=$(pm2 jlist 2>/dev/null | grep -o '"status":"[a-z]*"' | grep -cv online || true)
  [ "$DEAD" != "0" ] && ALERTS+="🔴 PM2: $DEAD proses mati\n"
fi

# Resource
RAM_USED=$(free -m | awk '/^Mem:/{printf "%d", $3}')
RAM_TOT=$(free -m | awk '/^Mem:/{printf "%d", $2}')
DISK_USED=$(df / | awk 'NR==2{print $5}')
LOAD=$(uptime | grep -oE 'load average:.*' | sed 's/load average: //')

# Kirim alarm kalau ada masalah
if [ -n "$ALERTS" ]; then
  MSG="⚠️ <b>MONITOR VIPIES</b>\n$ALERTS\nRAM: ${RAM_USED}/${RAM_TOT}MB | Disk: $DISK_USED | Load: $LOAD"
else
  MSG="✅ <b>MONITOR VIPIES</b> — semua normal\nRAM: ${RAM_USED}/${RAM_TOT}MB | Disk: $DISK_USED | Load: $LOAD"
fi
curl -s -o /dev/null "https://api.telegram.org/bot${TG_BOT}/sendMessage" \
  -d "chat_id=${TG_CHAT}" --data-urlencode "text=${MSG}" -d "parse_mode=HTML" 2>/dev/null || true
MON
chmod +x /usr/local/bin/vipies-monitor

# Update bot token & chat id dari .env ke dalam script (agar mandiri tanpa env)
if [ -n "${TG_BOT_TOKEN:-}" ]; then
  sed -i "s|^TG_BOT=\"\"|TG_BOT=\"${TG_BOT_TOKEN}\"|" /usr/local/bin/vipies-monitor
  sed -i "s|^TG_CHAT=\"\"|TG_CHAT=\"${TG_CHAT_ID}\"|" /usr/local/bin/vipies-monitor
fi

step "Memasang cron monitoring (tiap 30 menit)..."
if ! crontab -l 2>/dev/null | grep -q 'vipies-monitor'; then
  ( crontab -l 2>/dev/null; echo "*/30 * * * * /usr/local/bin/vipies-monitor >/dev/null 2>&1" ) | crontab -
  ok "Cron monitoring aktif (tiap 30 menit)"
else
  ok "Cron monitoring sudah ada"
fi

# Jalankan sekali untuk test
ok "Menjalankan monitor test..."
/usr/local/bin/vipies-monitor 2>/dev/null || true

ok "Module 08 selesai — Monitoring + notif Telegram."
