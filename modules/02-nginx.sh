#!/bin/bash
# ============================================================
#  vipies — 02-nginx.sh
#  Install Nginx + template WordPress & Custom site
#  Membuat helper script: /usr/local/bin/vipies-add-site
# ============================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source modules/lib.sh

step "Menginstall Nginx..."
ensure nginx
systemctl enable nginx >/dev/null 2>&1
ok "Nginx $(nginx -v 2>&1 | grep -oE '[0-9.]+') terinstall"

# --- Salin template ke /etc/nginx/templates ---
step "Memasang template site ke /etc/nginx/templates..."
mkdir -p /etc/nginx/templates
cat > /etc/nginx/templates/wordpress.conf <<'TMPL'
# vipies template — WordPress site
# Nama file: /etc/nginx/sites-available/<domain>
server {
    listen 80;
    server_name __DOMAIN__ www.__DOMAIN__;
    return 301 https://www.__DOMAIN__$request_uri;
}

server {
    listen 443 ssl http2;
    server_name www.__DOMAIN__;

    ssl_certificate     /etc/letsencrypt/live/__DOMAIN__/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/__DOMAIN__/privkey.pem;

    root /var/www/__DOMAIN__;
    index index.php index.html;

    client_max_body_size 128M;

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/__PHP_SOCK__;
    }

    location ~* \.(css|js|jpg|jpeg|png|gif|ico|webp|svg|woff2?)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    location ^~ /wp-content/uploads/ {
        try_files $uri /wp-content/uploads/placeholder.png;
    }
}
TMPL

cat > /etc/nginx/templates/custom.conf <<'TMPL'
# vipies template — Custom site (Express/Node/PHP)
# Nama file: /etc/nginx/sites-available/<domain>
server {
    listen 80;
    server_name __DOMAIN__ www.__DOMAIN__;
    return 301 https://www.__DOMAIN__$request_uri;
}

server {
    listen 443 ssl http2;
    server_name www.__DOMAIN__;

    ssl_certificate     /etc/letsencrypt/live/__DOMAIN__/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/__DOMAIN__/privkey.pem;

    root /var/www/__DOMAIN__;
    index index.html;

    client_max_body_size 128M;

    # Static langsung, sisanya proxy ke Node/backend di PORT
    location / {
        try_files $uri $uri.html $uri/ @backend;
    }
    location @backend {
        proxy_pass http://127.0.0.1:__PORT__;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
TMPL

cat > /etc/nginx/templates/static.conf <<'TMPL'
# vipies template — Static site (HTML/CSS/JS saja, tanpa backend)
# Nama file: /etc/nginx/sites-available/<domain>
server {
    listen 80;
    server_name __DOMAIN__ www.__DOMAIN__;
    return 301 https://www.__DOMAIN__$request_uri;
}

server {
    listen 443 ssl http2;
    server_name www.__DOMAIN__;

    ssl_certificate     /etc/letsencrypt/live/__DOMAIN__/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/__DOMAIN__/privkey.pem;

    root /var/www/__DOMAIN__;
    index index.html;

    client_max_body_size 128M;

    # Static murni — tanpa proxy backend
    location / {
        try_files $uri $uri.html $uri/ =404;
    }

    location ~* \.(css|js|jpg|jpeg|png|gif|ico|webp|svg|woff2?)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
}
TMPL

# --- Substitusi socket PHP (mendukung multi-versi: 8.1, 8.3, dll) ---
# Deteksi versi PHP-FPM yang terinstal/direpo; fallback php8.3-fpm
PHP_SOCK=$(ls /run/php/php*-fpm.sock 2>/dev/null | head -1 | xargs -n1 basename 2>/dev/null || echo php8.3-fpm.sock)
# Kalau belum ada socket (PHP belum install disini), cek paket tersedia di apt
if [ "$PHP_SOCK" = "php8.3-fpm.sock" ] && ! ls /run/php/php*-fpm.sock >/dev/null 2>&1; then
  DETECTED=$(apt-cache search '^php[0-9.]+-fpm$' 2>/dev/null | head -1 | grep -oE '[0-9.]+')
  [ -n "$DETECTED" ] && PHP_SOCK="php${DETECTED}-fpm.sock"
fi
sed -i "s/__PHP_SOCK__/$PHP_SOCK/g" /etc/nginx/templates/wordpress.conf
ok "Socket PHP-FPM template: $PHP_SOCK"

# --- Helper: vipies-add-site ---
cat > /usr/local/bin/vipies-add-site <<'HELPER'
#!/bin/bash
# vipies — tambah website baru (config nginx saja)
# Usage: vipies-add-site <domain> <wp|static> [nonwww]
#
#   Mode (opsional, default www + non-www):
#     nonwww = non-www only (tidak ada www block) — untuk subdomain
#              atau domain yang tidak mau www
#
#   wp     = WordPress (PHP-FPM)
#   static = HTML/CSS/JS statis
#   SSL: otomatis via auto-cert (cron 5 menit) atau manual vipies-cert
set -euo pipefail

DOMAIN="${1:-}"
TYPE="${2:-static}"
MODE="${3:-}"

[ -z "$DOMAIN" ] && { echo "Usage: vipies-add-site <domain> <wp|static> [nonwww]"; exit 1; }

# Pilih template
case "$TYPE" in
  wp) TMPL="/etc/nginx/templates/wordpress.conf" ;;
  static) TMPL="/etc/nginx/templates/static.conf" ;;
  *) echo "Type '$TYPE' tidak valid (wp|static)"; exit 1 ;;
esac

[ -f "$TMPL" ] || { echo "Template tidak ditemukan: $TMPL"; exit 1; }
[ -d "/var/www/$DOMAIN" ] || mkdir -p "/var/www/$DOMAIN"

# Kompatibilitas: subdomain lama = nonwww
[ "$MODE" = "subdomain" ] && MODE="nonwww"
IS_SUBDOMAIN=0
[ "$MODE" = "nonwww" ] && IS_SUBDOMAIN=1

# Generate config nginx dari template
sed -e "s/__DOMAIN__/$DOMAIN/g" "$TMPL" > "/etc/nginx/sites-available/$DOMAIN"

if [ "$IS_SUBDOMAIN" = "0" ]; then
  # Domain utama: server_name cover www + non-www.
  # Blok serve tetap satu; certbot --nginx yang menambah redirect
  # (non-www → www) otomatis saat request cert.
  echo "  → Mode domain utama (www + non-www)"
  sed -i "s/server_name $DOMAIN;/server_name www.$DOMAIN $DOMAIN;/" "/etc/nginx/sites-available/$DOMAIN"
else
  echo "  → Mode non-www (tanpa www)"
fi

ln -sfn "/etc/nginx/sites-available/$DOMAIN" "/etc/nginx/sites-enabled/$DOMAIN"

if nginx -t > /dev/null 2>&1; then
  systemctl reload nginx
  echo "✓ Site $DOMAIN dibuat ($TYPE, mode: ${MODE:-www}) + nginx reload"
  echo "  SSL otomatis ~5 menit setelah DNS pointing (auto-cert)"
else
  nginx -t
  echo "⚠ Site $DOMAIN dibuat, TAPI nginx belum reload — cek: nginx -t"
fi
HELPER
chmod +x /usr/local/bin/vipies-add-site

# alias template: wp -> wordpress.conf (kinerja helper: vipies-add-site <d> wp)
ln -sf wordpress.conf /etc/nginx/templates/wp.conf

step "Membuat placeholder.png (fallback gambar rusak)..."
mkdir -p /var/www/global-assets
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\nIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n\x2d\xb4\x00\x00\x00\x00IEND\xaeB\x60\x82' > /var/www/global-assets/placeholder.png

ok "Module 02 selesai — Nginx + template + helper 'vipies-add-site'"
