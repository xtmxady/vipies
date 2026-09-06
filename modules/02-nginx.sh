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
# vipies — tambah website baru
# Usage: vipies-add-site <domain> <wp|custom> [port]
#   otomatis: buat config nginx + certbot SSL + reload (kalau DNS sudah pointing)
set -euo pipefail
DOMAIN="$1"; TYPE="${2:-custom}"; PORT="${3:-4000}"
TMPL="/etc/nginx/templates/${TYPE}.conf"
# alias: wp -> wordpress.conf
if [ ! -f "$TMPL" ] && [ "$TYPE" = "wp" ]; then
  TMPL="/etc/nginx/templates/wordpress.conf"
fi
[ -f "$TMPL" ] || { echo "Template '$TYPE' tidak ada (wp|custom)"; exit 1; }
[ -d "/var/www/$DOMAIN" ] || mkdir -p "/var/www/$DOMAIN"

# Generate config nginx dari template.
# Kalau cert SSL belum ada, buat versi HTTP-only (hapus blok 443) biar nginx tetap valid.
HAS_CERT=0
[ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ] && HAS_CERT=1
sed -e "s/__DOMAIN__/$DOMAIN/g" -e "s/__PORT__/$PORT/g" "$TMPL" > "/etc/nginx/sites-available/$DOMAIN"
if [ "$HAS_CERT" = "0" ] && grep -q "listen 443" "/etc/nginx/sites-available/$DOMAIN"; then
  python3 - "$DOMAIN" <<'PYEOF'
import re, sys
p = f"/etc/nginx/sites-available/{sys.argv[1]}"
s = open(p).read()
# Hapus blok server 443 SSL (cert belum ada) — nginx tetap valid HTTP-only
s = re.sub(r'server \{\s*\n\s*listen 443 ssl.*?\n\}', '# (blok 443 nonaktif — belum ada cert)', s, flags=re.S)
open(p, 'w').write(s)
PYEOF
  echo "  → Config HTTP-only (belum ada cert SSL)"
fi
ln -sfn "/etc/nginx/sites-available/$DOMAIN" "/etc/nginx/sites-enabled/$DOMAIN"

# Certbot SSL (otomatis) — butuh DNS sudah pointing ke server ini.
if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
  echo "  ✓ Cert SSL sudah ada"
else
  echo "  → Request cert SSL via certbot (butuh DNS $DOMAIN → IP server ini)..."
  if certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" --non-interactive --agree-tos -m admin@"$DOMAIN" --redirect >/dev/null 2>&1; then
    echo "  ✓ Cert SSL terpasang"
  else
    echo "  ⚠ certbot belum bisa (DNS belum pointing / port 80 belum terbuka?)"
    echo "    Jalankan manual nanti: certbot --nginx -d $DOMAIN -d www.$DOMAIN"
  fi
fi

# Reload hanya kalau config valid (cert ada = test lolos)
if nginx -t >/dev/null 2>&1; then
  systemctl reload nginx
  echo "✓ Site $DOMAIN dibuat ($TYPE) + nginx reload"
else
  echo "⚠ Site $DOMAIN dibuat, TAPI nginx belum reload (butuh cert SSL dulu)"
  echo "  Jalankan: certbot --nginx -d $DOMAIN -d www.$DOMAIN"
fi
HELPER
chmod +x /usr/local/bin/vipies-add-site

# alias template: wp -> wordpress.conf (kinerja helper: vipies-add-site <d> wp)
ln -sf wordpress.conf /etc/nginx/templates/wp.conf

step "Membuat placeholder.png (fallback gambar rusak)..."
mkdir -p /var/www/global-assets
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\nIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n\x2d\xb4\x00\x00\x00\x00IEND\xaeB\x60\x82' > /var/www/global-assets/placeholder.png

ok "Module 02 selesai — Nginx + template + helper 'vipies-add-site'"
