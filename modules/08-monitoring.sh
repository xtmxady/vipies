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
CF_API_TOKEN=${CF_API_TOKEN:-}
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
    if (m && m[1]) return m[1].trim();
  } catch (e) {}

  // Fallback khusus CF_API_TOKEN dari /root/.cf/cache-token jika ada
  if (key === 'CF_API_TOKEN') {
    try {
      if (fs.existsSync('/root/.cf/cache-token')) {
        return fs.readFileSync('/root/.cf/cache-token', 'utf8').trim();
      }
    } catch (e) {}
  }

  return '';
}

const BOT_TOKEN = readConf('TG_BOT_TOKEN');
const CHAT_ID = readConf('TG_CHAT_ID');
const CF_TOKEN = readConf('CF_API_TOKEN');

if (!BOT_TOKEN || !CHAT_ID) {
  console.error('TG_BOT_TOKEN / TG_CHAT_ID kosong di /etc/vipies.conf');
  process.exit(1);
}

// State failover Cloudflare (hysteresis counter & last status)
const CF_STATE_FILE = '/etc/vipies/cf_state.json';

function readCfState() {
  try {
    if (fs.existsSync(CF_STATE_FILE)) {
      return JSON.parse(fs.readFileSync(CF_STATE_FILE, 'utf8'));
    }
  } catch (e) {}
  return {
    last_status: 'unknown',
    current_mode: 'unknown', // 'orange' | 'grey'
    degraded_count: 0,
    operational_count: 0,
    last_action: null,
    last_action_time: null
  };
}

function writeCfState(state) {
  try {
    fs.mkdirSync('/etc/vipies', { recursive: true });
    fs.writeFileSync(CF_STATE_FILE, JSON.stringify(state, null, 2), 'utf8');
  } catch (e) {
    console.error('Gagal menulis cf_state.json:', e.message);
  }
}

// Request helper Cloudflare API
function cfApiRequest(path, method = 'GET', body = null) {
  return new Promise((resolve, reject) => {
    if (!CF_TOKEN) return resolve({ success: false, errors: ['CF_API_TOKEN not set'] });
    const payload = body ? JSON.stringify(body) : null;
    const req = https.request({
      hostname: 'api.cloudflare.com',
      path: '/client/v4' + path,
      method: method,
      headers: {
        'Authorization': 'Bearer ' + CF_TOKEN,
        'Content-Type': 'application/json',
        'User-Agent': 'vipies-monitor/1.0',
        ...(payload ? { 'Content-Length': Buffer.byteLength(payload) } : {})
      },
      agent: false
    }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          resolve(JSON.parse(data));
        } catch (e) {
          reject(e);
        }
      });
    });
    req.on('error', reject);
    req.setTimeout(15000, () => {
      req.destroy();
      reject(new Error('CF API timeout'));
    });
    if (payload) req.write(payload);
    req.end();
  });
}

// Cek status Cloudflare StatusPage (Jakarta CGK)
function checkCgkStatus() {
  return new Promise((resolve) => {
    const req = https.request({
      hostname: 'www.cloudflarestatus.com',
      path: '/api/v2/summary.json',
      method: 'GET',
      headers: { 'User-Agent': 'vipies-monitor/1.0' },
      agent: false
    }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          const json = JSON.parse(data);
          const cgk = json.components ? json.components.find(c => c.name && c.name.includes('Jakarta')) : null;
          resolve(cgk ? cgk.status : 'unknown');
        } catch (e) {
          resolve('unknown');
        }
      });
    });
    req.on('error', () => resolve('unknown'));
    req.setTimeout(10000, () => {
      req.destroy();
      resolve('unknown');
    });
    req.end();
  });
}

// Dapatkan semua domain aktif yang di-host di server ini
function getManagedDomains() {
  try {
    const out = execSync("grep -h 'server_name' /etc/nginx/sites-enabled/* | grep -v 'server_name _;' | tr -s ' ' | sed 's/^ *server_name //' | tr ' ' '\\n' | sort -u").toString();
    const sites = out.split('\n').map(s => s.trim().replace(/;$/, '')).filter(s => s && s !== '_' && s !== 'example.com' && s.indexOf('#') !== 0);
    const seen = {};
    return sites.map(s => s.replace(/^www\./, '')).filter(s => {
      if (seen[s]) return false;
      seen[s] = true;
      return true;
    });
  } catch (e) {
    return [];
  }
}

// Update DNS records Cloudflare (Orange <-> Grey)
async function setCloudflareProxy(targetProxied) {
  if (!CF_TOKEN) {
    console.error('CF_API_TOKEN tidak ditemukan, lewati DNS failover.');
    return { success: false, changed: 0, failed: 0 };
  }

  const domains = getManagedDomains();
  let changed = 0;
  let failed = 0;
  const targetNames = [];

  try {
    const zonesResp = await cfApiRequest('/zones?per_page=50');
    if (!zonesResp || !zonesResp.result) {
      console.error('Gagal mengambil daftar zona CF:', zonesResp ? zonesResp.errors : 'null');
      return { success: false, changed: 0, failed: 0 };
    }

    for (const zone of zonesResp.result) {
      // Cek apakah zone ini mengelola salah satu domain/subdomain di server ini
      const isManagedZone = domains.some(d => d === zone.name || d.endsWith('.' + zone.name));
      if (!isManagedZone) continue;

      const recsResp = await cfApiRequest('/zones/' + zone.id + '/dns_records?per_page=100');
      if (!recsResp || !recsResp.result) continue;

      for (const rec of recsResp.result) {
        if (!['A', 'CNAME'].includes(rec.type)) continue;

        // Hanya ubah record yang relevan dengan domain yang di-serve Nginx
        const matchesDomain = domains.some(d => rec.name === d || rec.name === 'www.' + d);
        if (!matchesDomain) continue;

        if (rec.proxied !== targetProxied) {
          try {
            const patchResp = await cfApiRequest('/zones/' + zone.id + '/dns_records/' + rec.id, 'PATCH', {
              proxied: targetProxied
            });
            if (patchResp && patchResp.success) {
              changed++;
              targetNames.push(rec.name);
            } else {
              failed++;
            }
          } catch (e) {
            failed++;
          }
        }
      }
    }
  } catch (e) {
    console.error('Error saat proses setCloudflareProxy:', e.message);
  }

  return { success: failed === 0, changed, failed, targetNames };
}

// Logika failover otomatis dengan hysteresis
async function evaluateCloudflareFailover() {
  if (!CF_TOKEN) return null;

  const cgkStatus = await checkCgkStatus();
  if (cgkStatus === 'unknown') return null;

  const state = readCfState();
  let eventNotice = null;

  if (cgkStatus === 'degraded_performance' || cgkStatus === 'partial_outage' || cgkStatus === 'major_outage') {
    state.degraded_count = (state.degraded_count || 0) + 1;
    state.operational_count = 0;

    // Hysteresis: butuh 2x berturut-turut terdeteksi degraded
    if (state.degraded_count >= 2 && state.current_mode !== 'grey') {
      const res = await setCloudflareProxy(false);
      state.current_mode = 'grey';
      state.last_action = 'SWITCH_TO_GREY';
      state.last_action_time = new Date().toISOString();
      eventNotice = `🚨 <b>Cloudflare Failover: GREY CLOUD Aktif</b>\n` +
        `• Status CGK (Jakarta): <code>${cgkStatus}</code> (terdeteksi ${state.degraded_count}x)\n` +
        `• DNS diubah: <b>DNS-Only (Grey)</b> direct origin\n` +
        `• Rekord diperbarui: ${res.changed} record (gagal: ${res.failed})\n` +
        `• Web tetap aman dilayani langsung via Nginx origin cache.`;
    }
  } else if (cgkStatus === 'operational') {
    state.operational_count = (state.operational_count || 0) + 1;
    state.degraded_count = 0;

    // Hysteresis: butuh 3x berturut-turut stabil operational
    if (state.operational_count >= 3 && state.current_mode === 'grey') {
      const res = await setCloudflareProxy(true);
      state.current_mode = 'orange';
      state.last_action = 'SWITCH_TO_ORANGE';
      state.last_action_time = new Date().toISOString();
      eventNotice = `✅ <b>Cloudflare Recovery: ORANGE CLOUD Aktif</b>\n` +
        `• Status CGK (Jakarta): <code>operational</code> (stabil ${state.operational_count}x)\n` +
        `• DNS diubah: <b>Proxied (Orange)</b> via Cloudflare CDN & WAF\n` +
        `• Rekord diperbarui: ${res.changed} record (gagal: ${res.failed})\n` +
        `• Edge caching dan proteksi Cloudflare kembali normal.`;
    }
  }

  state.last_status = cgkStatus;
  writeCfState(state);

  return { cgkStatus, state, eventNotice };
}

// Daftar situs: dari SITES di conf (comma-sep), fallback auto-detect nginx sites-enabled
function getSites() {
  const fromConf = readConf('SITES');
  if (fromConf) return fromConf.split(',').map(s => s.trim()).filter(Boolean);
  const sites = getManagedDomains();
  return sites.length > 0 ? sites : ['seribukafetrk.com'];
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
  return new Promise((resolve) => {
    const body = JSON.stringify({ chat_id: CHAT_ID, text: msg, parse_mode: 'HTML' });
    const req = https.request({
      hostname: 'api.telegram.org',
      path: '/bot' + BOT_TOKEN + '/sendMessage',
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) },
      agent: false
    }, (res) => {
      res.resume();
      resolve();
    });
    req.on('error', (e) => {
      console.error('Telegram send error:', e.message);
      resolve();
    });
    req.write(body);
    req.end();
  });
}

function readCpu() {
  const s = fs.readFileSync('/proc/stat', 'utf8').split('\n')[0];
  const v = s.split(/\s+/).slice(1).map(Number);
  const user = v[0] || 0;
  const nice = v[1] || 0;
  const system = v[2] || 0;
  const idle = v[3] || 0;
  const iowait = v[4] || 0;
  const irq = v[5] || 0;
  const softirq = v[6] || 0;
  const steal = v[7] || 0;
  const total = v.reduce((a, b) => a + b, 0);
  return { user: user + nice, system, idle: idle + iowait, steal, total };
}

function getStats() {
  const totalMem = os.totalmem();
  const freeMem = os.freemem();
  const usedMem = totalMem - freeMem;
  const memPct = ((usedMem / totalMem) * 100).toFixed(1);
  const ramStr = (usedMem / 1024 / 1024).toFixed(0) + 'MB/' + (totalMem / 1024 / 1024).toFixed(0) + 'MB (' + memPct + '%)';

  // CPU: delta 2 sampel 200ms
  const c1 = readCpu();
  const start = Date.now();
  while (Date.now() - start < 200) { /* spin */ }
  const c2 = readCpu();
  const deltaTotal = c2.total - c1.total;
  const idlePct = deltaTotal > 0 ? (((c2.idle - c1.idle) / deltaTotal) * 100).toFixed(1) : '0.0';
  const userPct = deltaTotal > 0 ? (((c2.user - c1.user) / deltaTotal) * 100).toFixed(1) : '0.0';
  const stealPct = deltaTotal > 0 ? (((c2.steal - c1.steal) / deltaTotal) * 100).toFixed(1) : '0.0';
  const cpuStr = idlePct + '%, User ' + userPct + '%, Steal ' + stealPct + '%';

  const swapInfo = (() => {
    try {
      const mem = fs.readFileSync('/proc/meminfo', 'utf8');
      const t = (mem.match(/^SwapTotal:\s+(\d+)\s+kB/m) || [])[1];
      const f = (mem.match(/^SwapFree:\s+(\d+)\s+kB/m) || [])[1];
      if (t && f) {
        const tt = parseInt(t, 10) * 1024;
        const ff = parseInt(f, 10) * 1024;
        const uu = tt - ff;
        const pp = tt > 0 ? ((uu / tt) * 100).toFixed(1) : '0.0';
        return (uu / 1024 / 1024).toFixed(0) + 'MB/' + (tt / 1024 / 1024).toFixed(0) + 'MB (' + pp + '%)';
      }
    } catch (e) {}
    return '0MB/0MB (0%)';
  })();

  const disk = execSync("df -h / | tail -1").toString().trim().split(/\s+/);
  const diskStr = disk[2] + '/' + disk[1] + ' (' + disk[4] + ' used)';

  let pm2Lines = 'N/A';
  try {
    const procs = JSON.parse(execSync('pm2 jlist 2>/dev/null').toString());
    pm2Lines = procs.map(function(p) {
      const cpu = p.monit ? p.monit.cpu + '%' : 'N/A';
      const mem = p.monit ? (p.monit.memory / 1024 / 1024).toFixed(1) + 'MB' : 'N/A';
      return p.name + ': ' + p.pm2_env.status + ' (CPU ' + cpu + ', RAM ' + mem + ')';
    }).join('\n');
  } catch (e) {}

  const loadAvg = os.loadavg()[0].toFixed(2);

  const u = os.uptime();
  const uptime = Math.floor(u / 3600) + 'j ' + Math.floor((u % 3600) / 60) + 'm';

  return { ramStr, swapStr: swapInfo, cpuStr, disk: diskStr, pm2Lines, loadAvg, uptime };
}

async function main() {
  // 1. Evaluasi Failover Cloudflare (jika dikonfigurasi)
  let cfInfoStr = '';
  try {
    const cfResult = await evaluateCloudflareFailover();
    if (cfResult && cfResult.eventNotice) {
      await sendTelegram(cfResult.eventNotice);
    }
    if (cfResult) {
      const modeEmoji = cfResult.state.current_mode === 'grey' ? '☁️ (Grey/Direct)' : (cfResult.state.current_mode === 'orange' ? '🟠 (Orange/Proxied)' : '❓');
      cfInfoStr = `\n☁️ <b>Cloudflare Edge:</b> CGK <code>${cfResult.cgkStatus}</code> | Mode: ${modeEmoji}`;
    }
  } catch (e) {
    console.error('CF Failover check error:', e.message);
  }

  // 2. Cek resource & status website
  const stats = getStats();
  const sites = getSites();
  const results = await Promise.all(sites.map(checkSite));

  const lines = results.map(function(r) {
    return '🌐 Site ' + r.url + ' : ' + r.status;
  }).join('\n');

  const msg = '📊 <b>Monitor VPS</b>\n\n' +
    lines + '\n\n' +
    '⚙️ <b>Proses PM2:</b>\n' + stats.pm2Lines + '\n\n' +
    '🧠 RAM Server: ' + stats.ramStr + '\n' +
    '💾 SWAP Server: ' + stats.swapStr + '\n' +
    '⚡ CPU Idle: ' + stats.cpuStr + '\n' +
    '💾 Disk: ' + stats.disk + '\n' +
    '📈 Load Avg: ' + stats.loadAvg + '\n' +
    '⏱ Uptime: ' + stats.uptime +
    cfInfoStr;

  await sendTelegram(msg);
  process.exit(0);
}

main().catch(async function(e) {
  try {
    await sendTelegram('❌ Monitor error: ' + e.message);
  } catch (err) {}
  process.exit(1);
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
