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
# Usage: vipies-new-site <domain> [wp|static] [dbname] [dbuser] [dbpass] [subdomain]
#   Tipe default: wp
#   Mode default: domain utama (www + non-www)
#   dbname/dbuser/dbpass: optional, dibuat otomatis dari domain (WP only)
set -euo pipefail

DOMAIN="${1:-}"
[ -z "$DOMAIN" ] && { echo "Usage: vipies-new-site <domain> [wp|static] [dbname] [dbuser] [dbpass] [subdomain]"; exit 1; }
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
DBNAME="${3:-wp_${SLUG}}"
DBUSER="${4:-${SLUG}}"
DBPASS="${5:-$(openssl rand -hex 12)}"
MODE="${6:-}"

echo "=== [1/6] Nginx config ==="
vipies-add-site "$DOMAIN" wp "$MODE"

echo "=== [2/6] Database & user ==="
if ! mysql -u root -e "USE \`$DBNAME\`" 2>/dev/null; then
  mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`$DBNAME\`; CREATE USER IF NOT EXISTS '$DBUSER'@'localhost' IDENTIFIED BY '$DBPASS'; GRANT ALL PRIVILEGES ON \`$DBNAME\`.* TO '$DBUSER'@'localhost'; FLUSH PRIVILEGES;"
  echo "  ✓ DB '$DBNAME' + user '$DBUSER' dibuat"
else
  echo "  ✓ DB '$DBNAME' sudah ada"
fi

echo "=== [3/6] Download WordPress ==="
mkdir -p "$WEBROOT"
wp core download --path="$WEBROOT" --allow-root > /dev/null 2>&1 || { echo "  ✗ Gagal download WP"; exit 1; }

echo "=== [4/6] Buat wp-config ==="
wp config create --path="$WEBROOT" --dbname="$DBNAME" --dbuser="$DBUSER" --dbpass="$DBPASS" --allow-root > /dev/null 2>&1

echo "=== [5/6] Permission www-data ==="
chown -R www-data:www-data "$WEBROOT"
find "$WEBROOT" -type d -exec chmod 755 {} +
find "$WEBROOT" -type f -exec chmod 644 {} +

echo "=== [6/6] Tambah ke r2-sites.conf (backup) ==="
if ! grep -q "^${DOMAIN}|" /root/r2-sites.conf 2>/dev/null; then
  echo "${DOMAIN}|${DBNAME}|${DBUSER}|${DBPASS}" >> /root/r2-sites.conf
  echo "  ✓ Ditambahkan ke /root/r2-sites.conf"
fi

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

ok "Module 11 selesai."
