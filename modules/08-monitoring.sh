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
SITE_URL=${SITE_URL:-https://www.seribukafetrk.com}
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

# Cek status backup R2 terakhir (dari report backup harian)
BACKUP_TXT=""
if [ -f /root/backup-report.txt ]; then
  # Deteksi tanda gagal pada 15 baris terakhir report
  if grep -q "⚠️\|gagal\|error" /root/backup-report.txt 2>/dev/null; then
    ALERTS+="🟠 <b>Backup R2</b>: ada komponen gagal (cek log)\n"
  fi
  LAST=$(grep -E "\.sql\.gz|\.zip" /root/backup-report.txt | tail -6 | sed 's/^[0-9-]* [0-9:]* | *//' | tr '\n' ' ')
  BACKUP_TXT="
📦 <b>Backup R2 terakhir</b>: $LAST"
fi

if [ -n "$ALERTS" ]; then
  MSG="⚠️ <b>MONITOR VIPIES</b> [ALARM]\n$ALERTS\nRAM: ${RAM_USED}/${RAM_TOT}MB | Disk: $DISK_USED | Load: $LOAD$BACKUP_TXT"
else
  MSG="✅ <b>MONITOR VIPIES</b> — semua normal\nRAM: ${RAM_USED}/${RAM_TOT}MB | Disk: $DISK_USED | Load: $LOAD$BACKUP_TXT"
fi
curl -s -o /dev/null "https://api.telegram.org/bot${TG_BOT}/sendMessage" \
  -d "chat_id=${TG_CHAT}" --data-urlencode "text=${MSG}" -d "parse_mode=HTML" 2>/dev/null || true
MON
chmod +x /usr/local/bin/vipies-monitor

step "Membuat monitor Node standalone (/var/www/monitor.js)..."
cat > /var/www/monitor.js <<'MONJS'
const https = require('https');
const os = require('os');
const fs = require('fs');
const { execSync } = require('child_process');

// Token & config dibaca dari /etc/vipies.conf (dibuat modul 08 dari .env saat install)
function readConf(key) {
  try {
    const txt = fs.readFileSync('/etc/vipies.conf', 'utf8');
    const m = txt.match(new RegExp('^' + key + '=(.*)$', 'm'));
    return m ? m[1].trim() : '';
  } catch (e) { return ''; }
}

const BOT_TOKEN = readConf('TG_BOT_TOKEN');
const CHAT_ID = readConf('TG_CHAT_ID');

if (!BOT_TOKEN || !CHAT_ID) {
  console.error('TG_BOT_TOKEN / TG_CHAT_ID kosong di /etc/vipies.conf');
  process.exit(1);
}

// Daftar situs: dari SITES di conf (comma-sep), fallback auto-detect nginx sites-enabled
function getSites() {
  const fromConf = readConf('SITES');
  if (fromConf) return fromConf.split(',').map(s => s.trim()).filter(Boolean);
  try {
    const out = execSync("grep -h 'server_name' /etc/nginx/sites-enabled/* | grep -v 'server_name _;' | tr -s ' ' | sed 's/^ *server_name //' | tr ' ' '\\n' | sort -u").toString();
    var sites = out.split('\n').map(s => s.trim().replace(/;$/, '')).filter(s => s && s !== '_' && s !== 'example.com' && s.indexOf('#') !== 0);
    // Normalize: buang www (cek bare domain), dedupe
    var seen = {};
    return sites.map(function(s) { return s.replace(/^www\./, ''); })
      .filter(function(s) { if (seen[s]) return false; seen[s] = true; return true; });
  } catch (e) { return ['seribukafetrk.com']; }
}

function checkSite(url) {
  return new Promise(function(resolve) {
    var done = false;
    var req = https.get('https://' + url, { agent: false }, function(res) {
      done = true;
      var ok = res.statusCode === 200 || res.statusCode === 301 || res.statusCode === 302;
      resolve({ url: url, status: ok ? '✅ Online' : '⚠️ Status ' + res.statusCode });
      res.resume();
    });
    req.on('error', function() {
      if (!done) { done = true; resolve({ url: url, status: '🔴 DOWN' }); }
    });
    req.setTimeout(8000, function() {
      if (!done) {
        done = true;
        req.destroy();
        resolve({ url: url, status: '⏱️ Timeout' });
      }
    });
  });
}

function sendTelegram(msg) {
  const body = JSON.stringify({ chat_id: CHAT_ID, text: msg, parse_mode: 'HTML' });
  const req = https.request({
    hostname: 'api.telegram.org',
    path: '/bot' + BOT_TOKEN + '/sendMessage',
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) }
  });
  req.write(body);
  req.end();
}

function getStats() {
  const totalMem = os.totalmem();
  const freeMem = os.freemem();
  const memPct = (((totalMem - freeMem) / totalMem) * 100).toFixed(1);

  const disk = execSync("df -h / | tail -1").toString().trim().split(/\s+/);
  const diskStr = disk[2] + '/' + disk[1] + ' (' + disk[4] + ' used)';

  const procs = JSON.parse(execSync('pm2 jlist 2>/dev/null').toString());
  const pm2Lines = procs.map(function(p) {
    const cpu = p.monit ? p.monit.cpu + '%' : 'N/A';
    const mem = p.monit ? (p.monit.memory / 1024 / 1024).toFixed(1) + 'MB' : 'N/A';
    return p.name + ': ' + p.pm2_env.status + ' (CPU ' + cpu + ', RAM ' + mem + ')';
  }).join('\n');

  const loadAvg = os.loadavg()[0].toFixed(2);

  const u = os.uptime();
  const uptime = Math.floor(u / 3600) + 'j ' + Math.floor((u % 3600) / 60) + 'm';

  return { memPct: memPct, disk: diskStr, pm2Lines: pm2Lines, loadAvg: loadAvg, uptime: uptime };
}

async function main() {
  const stats = getStats();
  const sites = getSites();
  const results = await Promise.all(sites.map(checkSite));

  const lines = results.map(function(r) {
    return '🌐 Site ' + r.url + ' : ' + r.status;
  }).join('\n');

  const msg = '📊 <b>Monitor VPS</b>\n\n' +
    lines + '\n\n' +
    '⚙️ <b>Proses PM2:</b>\n' + stats.pm2Lines + '\n\n' +
    '🧠 RAM Server: ' + stats.memPct + '%\n' +
    '💾 Disk: ' + stats.disk + '\n' +
    '📈 Load Avg: ' + stats.loadAvg + '\n' +
    '⏱ Uptime: ' + stats.uptime;

  sendTelegram(msg);
}

main().catch(function(e) {
  sendTelegram('❌ Monitor error: ' + e.message);
});
MONJS
chmod 755 /var/www/monitor.js
ok "Monitor Node standalone dibuat (/var/www/monitor.js)"

step "Memasang cron monitoring (tiap 30 menit)..."
if ! crontab -l 2>/dev/null | grep -q 'vipies-monitor'; then
  ( crontab -l 2>/dev/null; echo "*/30 * * * * /usr/local/bin/vipies-monitor >/dev/null 2>&1" ) | crontab -
  ok "Cron monitoring aktif (tiap 30 menit)"
else
  ok "Cron monitoring sudah ada"
fi
if ! crontab -l 2>/dev/null | grep -q '/var/www/monitor.js'; then
  ( crontab -l 2>/dev/null; echo "*/30 * * * * node /var/www/monitor.js >> /var/log/monitor.log 2>&1" ) | crontab -
  ok "Cron monitor Node aktif (/var/www/monitor.js)"
else
  ok "Cron monitor Node sudah ada"
fi

# Jalankan sekali untuk test
if [ -n "${TG_BOT_TOKEN:-}" ]; then
  ok "Menjalankan monitor test..."
  /usr/local/bin/vipies-monitor 2>/dev/null || true
else
  warn "TG_BOT_TOKEN kosong — lewati test monitor (isi .env)"
fi

ok "Module 08 selesai — Monitoring + notif Telegram."
