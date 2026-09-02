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
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
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

# --- Helper: vipies-add-site ---
cat > /usr/local/bin/vipies-add-site <<'HELPER'
#!/bin/bash
# vipies — tambah website baru
# Usage: vipies-add-site <domain> <wp|custom> [port]
set -euo pipefail
DOMAIN="$1"; TYPE="${2:-custom}"; PORT="${3:-4000}"
TMPL="/etc/nginx/templates/${TYPE}.conf"
[ -f "$TMPL" ] || { echo "Template '$TYPE' tidak ada (wp|custom)"; exit 1; }
[ -d "/var/www/$DOMAIN" ] || mkdir -p "/var/www/$DOMAIN"
sed -e "s/__DOMAIN__/$DOMAIN/g" -e "s/__PORT__/$PORT/g" "$TMPL" > "/etc/nginx/sites-available/$DOMAIN"
ln -sfn "/etc/nginx/sites-available/$DOMAIN" "/etc/nginx/sites-enabled/$DOMAIN"
nginx -t && systemctl reload nginx
echo "✓ Site $DOMAIN dibuat ($TYPE). Jalankan: certbot --nginx -d $DOMAIN -d www.$DOMAIN"
HELPER
chmod +x /usr/local/bin/vipies-add-site

step "Membuat placeholder.png (fallback gambar rusak)..."
mkdir -p /var/www/global-assets
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\nIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n\x2d\xb4\x00\x00\x00\x00IEND\xaeB\x60\x82' > /var/www/global-assets/placeholder.png

ok "Module 02 selesai — Nginx + template + helper 'vipies-add-site'"
