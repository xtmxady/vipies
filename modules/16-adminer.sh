#!/bin/bash
# ============================================================
#  vipies — 16-adminer.sh
#  Install Adminer (alternatif phpMyAdmin — 1 file PHP, ringan)
#  Akses: http://<IP_VPS>/adminer  (atau /adminer/index.php)
#  Lokasi: /var/www/html/adminer/
#  Auth:   basic auth (admin / password dari .env ADMINER_PASS)
# ============================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source modules/lib.sh

WEBROOT=/var/www/html
ADM_DIR=$WEBROOT/adminer
PHP_SOCK=$(ls /run/php/php*-fpm.sock 2>/dev/null | head -1)
[ -z "$PHP_SOCK" ] && PHP_SOCK=/run/php/php8.3-fpm.sock

step "Install adminer (single-file PHP)..."
mkdir -p "$ADM_DIR"
if [ ! -f "$ADM_DIR/index.php" ]; then
  curl -fsSL -o "$ADM_DIR/index.php" "https://www.adminer.org/latest.php" 2>/dev/null \
    || { warn "Gagal download dari adminer.org — coba mirror github."; \
         curl -fsSL -o "$ADM_DIR/index.php" "https://raw.githubusercontent.com/vrana/adminer/master/adminer.php" 2>/dev/null || { err "Gagal download Adminer."; exit 1; }; }
fi
chown -R www-data:www-data "$ADM_DIR" 2>/dev/null
ok "Adminer: $ADM_DIR/index.php ($(du -h $ADM_DIR/index.php | cut -f1))"

step "Nginx: tambah location /adminer di default server..."
if ! grep -q "location.*adminer" /etc/nginx/sites-available/default; then
  # Sisipkan: block location adminer sebelum penutup server block
  TMPL=$(cat <<NGINX

    # Adminer — http://<ip>/adminer (login pakai user/pass MySQL, tanpa popup)
    location ^~ /adminer {
        alias $ADM_DIR/;
        index index.php;
        location ~ \.php$ {
            fastcgi_pass unix:$PHP_SOCK;
            include snippets/fastcgi-php.conf;
            fastcgi_param SCRIPT_FILENAME \$request_filename;
        }
    }
NGINX
  )
  # sisipkan sebelum "}" terakhir (akhir file server block)
  python3 - "$TMPL" <<'PY'
import sys
p = "/etc/nginx/sites-available/default"
s = open(p).read()
block = sys.argv[1]
# sisipkan sebelum baris "}" terakhir (penutup server block default)
idx = s.rstrip().rfind("\n}")
if idx > 0:
    s = s[:idx+1] + block + s[idx+1:]
open(p, "w").write(s)
PY
fi
nginx -t 2>&1 | tail -1 && systemctl reload nginx && ok "Nginx reload OK — adminer live di http://<IP>/adminer"

ok "Module 16 selesai. Adminer: http://<IP>/adminer (login pakai user/pass MySQL)"