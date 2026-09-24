#!/bin/bash
# ============================================================
#  vipies — 11-newsite.sh
#  Helper 'vipies-new-site' — buat situs baru (WordPress atau Static).
# ============================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source modules/lib.sh

step "Memasang helper 'vipies-new-site'..."
cat > /usr/local/bin/vipies-new-site << 'HELPER'
#!/bin/bash
# vipies-new-site — buat situs baru (WordPress atau Static).
# Usage: vipies-new-site <domain> [wp|static] [dbname] [dbuser] [dbpass] [nonwww]
#   Tipe default: wp
#   Mode default: domain utama (www + non-www)
#   dbname/dbuser/dbpass: optional, dibuat otomatis dari domain (WP only)
set -euo pipefail

DOMAIN="${1:-}"
[ -z "$DOMAIN" ] && { echo "Usage: vipies-new-site <domain> [wp|static] [dbname] [dbuser] [dbpass] [nonwww]"; exit 1; }
TYPE="${2:-wp}"
WEBROOT="/var/www/$DOMAIN"

if [ "$TYPE" = "static" ]; then
  MODE="${3:-}"
  echo "=== [1/2] Nginx config (static) ==="
  vipies-add-site "$DOMAIN" static "$MODE"
  mkdir -p "$WEBROOT"
  echo ""
  echo "=============================================="
  echo "✅ Situs Static '$DOMAIN' siap!"
  echo "  Root:      $WEBROOT"
  echo "  Mode:      ${MODE:-www (domain utama)}"
  echo ""
  echo "  Langkah terakhir:"
  if [ -z "$MODE" ]; then
    echo "    1) Point DNS $DOMAIN + www.$DOMAIN ke IP server ini"
  else
    echo "    1) Point DNS $DOMAIN ke IP server ini"
  fi
  echo "    2) Upload file ke $WEBROOT"
  echo "    3) SSL otomatis (~5 menit setelah DNS pointing)"
  echo "=============================================="
  exit 0
fi

# Mode WordPress
SLUG=$(echo "$DOMAIN" | tr '.-' '__')
DBNAME="wp_${SLUG}"
case "${3:-}" in
  nonwww|subdomain) MODE="${3}";;
  *)                DBNAME="${3:-wp_${SLUG}}"; MODE="${6:-}";;
esac
DBUSER="${4:-${SLUG}}"
DBPASS="${5:-$(openssl rand -hex 12)}"

echo "=== [1/7] Nginx config ==="
vipies-add-site "$DOMAIN" wp "$MODE"

echo "=== [2/7] Database & user ==="
if ! mysql -u root -e "USE \`$DBNAME\`" 2>/dev/null; then
  mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`$DBNAME\`; CREATE USER IF NOT EXISTS '$DBUSER'@'localhost' IDENTIFIED BY '$DBPASS'; GRANT ALL PRIVILEGES ON \`$DBNAME\`.* TO '$DBUSER'@'localhost'; FLUSH PRIVILEGES;"
  echo "  ✓ DB '$DBNAME' + user '$DBUSER' dibuat"
else
  echo "  ✓ DB '$DBNAME' sudah ada"
fi

echo "=== [3/7] Download WordPress ==="
mkdir -p "$WEBROOT"
wp core download --path="$WEBROOT" --allow-root > /dev/null 2>&1 || { echo "  ✗ Gagal download WP"; exit 1; }

echo "=== [4/7] Buat wp-config ==="
wp config create --path="$WEBROOT" --dbname="$DBNAME" --dbuser="$DBUSER" --dbpass="$DBPASS" --allow-root > /dev/null 2>&1

# Disable WP-Cron internal (hemat CPU): pindah ke system cron
echo " * DISABLE_WP_CRON"
wp config set DISABLE_WP_CRON true --raw --path="$WEBROOT" --allow-root 2>/dev/null || \
  sed -i "/That's all, stop editing/i define('DISABLE_WP_CRON', true);" "$WEBROOT/wp-config.php"

# Stagger jadwal wp-cron: cari slot menit yang belum dipakai situs lain.
# Semua situs di menit sama = 8 proses PHP boot serentak tiap 10 menit (load spike).
# Pola: menit ke-N, N+10, N+20, N+30, N+40, N+50.
if ! crontab -l 2>/dev/null | grep -q "/var/www/$DOMAIN/wp-cron.php"; then
  OFFSET=""
  for n in $(seq 1 9); do
    if ! crontab -l 2>/dev/null | grep -qE "^$n(,[0-9]+)* \* \* \* \*.*wp-cron"; then
      OFFSET="$n"; break
    fi
  done
  [ -z "$OFFSET" ] && OFFSET=$(( $(crontab -l 2>/dev/null | grep -c 'wp-cron.php') % 9 + 1 ))
  MINS=$(for i in 0 1 2 3 4 5; do printf "%d," $(( (OFFSET + i*10) % 60 )); done | sed 's/,$//')
  ( crontab -l 2>/dev/null; echo "$MINS * * * * /usr/bin/php /var/www/$DOMAIN/wp-cron.php >/dev/null 2>&1" ) | crontab -
  echo "  ✓ System cron wp-cron: menit $MINS (stagger, bukan */10)"
fi

echo "=== [5/7] Permission www-data ==="
chown -R www-data:www-data "$WEBROOT"
find "$WEBROOT" -type d -exec chmod 755 {} +
find "$WEBROOT" -type f -exec chmod 644 {} +

echo "=== [6/7] Tambah ke r2-sites.conf (backup) ==="
if ! grep -q "^${DOMAIN}|" /root/r2-sites.conf 2>/dev/null; then
  echo "${DOMAIN}|${DBNAME}|${DBUSER}|${DBPASS}" >> /root/r2-sites.conf
  echo "  ✓ Ditambahkan ke /root/r2-sites.conf"
fi

echo "=== [7/7] Proteksi WordPress (xmlrpc + wp-login rate limit) ==="
vipies-limit "$DOMAIN" 2>/dev/null || echo "  ⚠ vipies-limit tidak tersedia — jalankan manual setelahnya"

echo ""
echo "=============================================="
echo "✅ Situs WordPress '$DOMAIN' siap!"
echo "  Root:      $WEBROOT"
echo "  DB:        $DBNAME (user $DBUSER)"
echo "  DB pass:   $DBPASS       <-- simpan! di /root/r2-sites.conf"
echo "  Mode:      ${MODE:-www (domain utama)}"
echo ""
echo "  Langkah terakhir:"
if [ -z "$MODE" ]; then
  echo "    1) Point DNS $DOMAIN + www.$DOMAIN ke IP server ini"
else
  echo "    1) Point DNS $DOMAIN ke IP server ini"
fi
echo "    2) Install WP: buka https://$DOMAIN di browser"
echo "    3) SSL otomatis (~5 menit setelah DNS pointing)"
echo "=============================================="
HELPER
chmod +x /usr/local/bin/vipies-new-site
ok "Helper 'vipies-new-site' terpasang"

# --- Helper: vipies-limit (proteksi WP) ---
step "Memasang helper 'vipies-limit'..."
cat > /usr/local/bin/vipies-limit <<'HELPER'
#!/bin/bash
# vipies-limit — aktifkan proteksi WP untuk domain yang sudah ada.
# Blokir xmlrpc.php (403) + rate limit wp-login.php (1r/s burst=5 → 429).
# Idempotent: aman dijalankan berulang.
# Usage: vipies-limit <domain>
set -euo pipefail

DOMAIN="${1:-}"
[ -z "$DOMAIN" ] && { echo "Usage: vipies-limit <domain>"; exit 1; }

CONF="/etc/nginx/sites-available/$DOMAIN"
[ ! -f "$CONF" ] && { echo "✗ Config $CONF tidak ditemukan"; exit 1; }

ADDED=0

# Cari baris penutup server block TERAKHIR (bukan semua '}' — config punya >1 blok).
# Sisip sebelum '}' terakhir supaya tidak duplikat di tiap blok.
LAST_BRACE=$(grep -n '^}' "$CONF" | tail -1 | cut -d: -f1)

# --- xmlrpc block (cocok format lama `location ~*` maupun baru `location =`) ---
if grep -qE '^[[:space:]]*location[^;]*xmlrpc' "$CONF"; then
  echo "  ✓ xmlrpc sudah diblokir"
else
  sed -i "${LAST_BRACE}i\\    # Blokir xmlrpc.php (brute force + DDoS amplification)\n    location = /xmlrpc.php { return 403; }" "$CONF"
  echo "  + xmlrpc → 403"
  ADDED=1
  LAST_BRACE=$((LAST_BRACE + 2))
fi

# --- wp-login rate limit ---
if grep -qE '^[[:space:]]*location[^;]*wp-login' "$CONF"; then
  echo "  ✓ wp-login rate limit sudah ada"
else
  sed -i "${LAST_BRACE}i\\    # Brute force protection\n    location = /wp-login.php {\n        limit_req zone=wp-login burst=5 nodelay;\n        limit_req_status 429;\n        include snippets/fastcgi-php.conf;\n        fastcgi_pass unix:/run/php/php8.3-fpm.sock;\n    }" "$CONF"
  echo "  + wp-login rate limit 1r/s burst=5"
  ADDED=1
fi

if [ "$ADDED" -eq 1 ]; then
  nginx -t 2>/dev/null && { systemctl reload nginx; echo "✓ Nginx reloaded"; } \
    || { echo "✗ Nginx config error — tidak jadi reload!"; exit 1; }
fi

echo "✅ Proteksi '$DOMAIN' aktif"
HELPER
chmod +x /usr/local/bin/vipies-limit
ok "Helper 'vipies-limit' terpasang"

ok "Module 11 selesai."
