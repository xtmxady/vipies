#!/bin/bash
# ============================================================
#  vipies — 11-newsite.sh
#  Helper 'vipies-new-site' — buat situs WordPress lengkap
#  dalam satu perintah: Nginx + DB + WP install + permission.
# ============================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source modules/lib.sh

step "Memasang helper 'vipies-new-site'..."
cat > /usr/local/bin/vipies-new-site <<'HELPER'
#!/bin/bash
# vipies-new-site — buat situs WordPress baru secara lengkap.
# Usage: vipies-new-site <domain> [dbname] [dbuser] [dbpass]
#   dbname/dbuser/dbpass optional — kalau kosong, dibuat otomatis dari domain.
set -euo pipefail

DOMAIN="$1"
[ -z "$DOMAIN" ] && { echo "Usage: vipies-new-site <domain> [dbname] [dbuser] [dbpass]"; exit 1; }
SLUG=$(echo "$DOMAIN" | tr '.-' '__')          # domain.com -> domain_com
DBNAME="${2:-wp_${SLUG}}"
DBUSER="${3:-${SLUG}}"
DBPASS="${4:-$(openssl rand -hex 12)}"
WEBROOT="/var/www/$DOMAIN"

echo "=== [1/6] Nginx config ==="
vipies-add-site "$DOMAIN" wp
# Ganti root di config Nginx agar mengarah ke WEBROOT (template root /var/www/<domain> sudah benar)

echo "=== [2/6] Database & user ==="
if ! mysql -u root -e "USE \`$DBNAME\`" 2>/dev/null; then
  mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`$DBNAME\`; CREATE USER IF NOT EXISTS '$DBUSER'@'localhost' IDENTIFIED BY '$DBPASS'; GRANT ALL PRIVILEGES ON \`$DBNAME\`.* TO '$DBUSER'@'localhost'; FLUSH PRIVILEGES;"
  echo "  ✓ DB '$DBNAME' + user '$DBUSER' dibuat"
else
  echo "  ✓ DB '$DBNAME' sudah ada"
fi

echo "=== [3/6] Download WordPress ==="
mkdir -p "$WEBROOT"
wp core download --path="$WEBROOT" --allow-root >/dev/null 2>&1 || { echo "  ✗ Gagal download WP"; exit 1; }

echo "=== [4/6] Buat wp-config ==="
wp config create --path="$WEBROOT" --dbname="$DBNAME" --dbuser="$DBUSER" --dbpass="$DBPASS" --allow-root >/dev/null 2>&1

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
echo ""
echo "  Langkah terakhir (manual):"
echo "    certbot --nginx -d $DOMAIN -d www.$DOMAIN"
echo "    # install WP: buka https://$DOMAIN di browser"
echo "=============================================="
HELPER
chmod +x /usr/local/bin/vipies-new-site
ok "Helper 'vipies-new-site' terpasang"

ok "Module 11 selesai."
