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

ok "Module 04 selesai."
