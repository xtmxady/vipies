#!/bin/bash
# ============================================================
#  vipies — 04-php.sh
#  Install PHP-FPM + extensions + optimasi OPcache
# ============================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source modules/lib.sh

# Deteksi PHP version yang tersedia di repo
if [ -z "${PHP_VERSION:-}" ]; then
  PHP_VERSION=$(apt-cache search '^php[0-9.]+-fpm$' | head -1 | grep -oE '[0-9.]+' | head -1)
  read -rp "  Versi PHP default [${PHP_VERSION:-8.3}]: " ans
  PHP_VERSION="${ans:-${PHP_VERSION:-8.3}}"
fi

step "Menginstall PHP $PHP_VERSION-FPM + extensions..."
apt-get install -y \
  php${PHP_VERSION}-fpm \
  php${PHP_VERSION}-mysql \
  php${PHP_VERSION}-curl \
  php${PHP_VERSION}-gd \
  php${PHP_VERSION}-mbstring \
  php${PHP_VERSION}-xml \
  php${PHP_VERSION}-zip \
  php${PHP_VERSION}-intl \
  php${PHP_VERSION}-bcmath \
  php${PHP_VERSION}-opcache \
  >/dev/null 2>&1
ok "PHP $PHP_VERSION terinstall"

step "Optimasi OPcache (128MB, 10k files)..."
INI=$(php -r 'echo php_ini_loaded_file();' 2>/dev/null || echo /etc/php/${PHP_VERSION}/fpm/php.ini)
# OPcache harus aktif via conf.d
cat > /etc/php/${PHP_VERSION}/fpm/conf.d/20-opcache.ini <<'OPC'
zend_extension=opcache.so
opcache.enable=1
opcache.memory_consumption=128
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=10000
opcache.revalidate_freq=60
opcache.validate_timestamps=1
OPC

systemctl enable php${PHP_VERSION}-fpm >/dev/null 2>&1
systemctl restart php${PHP_VERSION}-fpm >/dev/null 2>&1
ok "OPcache aktif (128MB, 10k files) — semua site baru otomatis dapat"

# ============================================================
# Pool www — disetel ke nilai yang TERBUKTI di VPS Biznetgio 137.59.126.191
#
# Kenapa tidak pakai default PHP:
# - pm=dynamic + max_children=5  → 5 worker yang hampir tidak pernah mati
# - tiap worker bisa tembus 200 MB RSS saat render halaman berat
# - 5 x 200 MB = 1 GB, di server RAM 1,9 GB itu hampir semua
#
# Data 2026-09-29 (live, 8 situs WP + 3 Node):
# - max_children 6 → 8  = RAM free 291 → 177 MB, load 10.68. MEMBURUK.
# - max_children 6 + max_requests 200 = 0 timeout selama 2 jam
# - RSS per worker saat sehat: ~40 MB; saat OPTIMIZE TABLE: 160-240 MB
# ============================================================
POOL="/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf"

step "Set pool www (max_children=6, ondemand, max_requests=200)..."
if [ -f "$POOL" ]; then
  cp -n "$POOL" "$POOL.vipies.bak" 2>/dev/null || true

  # PENTING: hanya baris yang Setting NYATA (tidak diawali ';').
  # Pool www bawaan PHP punya blok komentar dokumentasi yang juga memuat
  # "pm.max_children ..." — regex longgar akan mengaktifkan 3 baris sekaligus
  # dan php-fpm hanya membaca yang terakhir.
  set_pm() {  # $1 = key, $2 = value
    if grep -qE "^$1 *=" "$POOL"; then
      sed -i -E "s|^$1 *=.*|$1 = $2|" "$POOL"
    else
      printf "%s = %s\n" "$1" "$2" >> "$POOL"
    fi
  }
  set_pm pm.max_children        6
  set_pm pm.start_servers       3
  set_pm pm.max_requests        200
  set_pm pm.process_idle_timeout 10s

  # pm: ondemand = worker hanya hidup saat ada request.
  # JANGAN naikkan max_children di RAM < 3 GB.
  if grep -qE "^pm *= *dynamic" "$POOL"; then
    sed -i -E 's/^pm *= *dynamic/pm = ondemand/' "$POOL"
  elif ! grep -qE "^pm *=" "$POOL"; then
    printf "pm = ondemand\n" >> "$POOL"
  fi

  echo "  ▸ hasil:"
  grep -E '^pm *=|^pm\.' "$POOL" | sed 's/^/    /'

  php-fpm${PHP_VERSION} -t 2>&1 | grep -q "successful" \
    && systemctl reload php${PHP_VERSION}-fpm \
    && ok "pool www: max_children=6, pm=ondemand, max_requests=200" \
    || { echo "  ✗ php-fpm -t gagal, pool tidak diubah. Cek: $POOL"; exit 1; }
else
  echo "  ! Pool tidak ditemukan di $POOL — set manual max_children=6"
fi

ok "Module 04 selesai."
