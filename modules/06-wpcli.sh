#!/bin/bash
# ============================================================
#  vipies — 06-wpcli.sh
#  Install WP-CLI (global) + Certbot via snap (fixed, tidak
#  konflik dengan pyOpenSSL system pip)
# ============================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source modules/lib.sh

step "Menginstall WP-CLI (global)..."
if ! command -v wp >/dev/null 2>&1; then
  curl -fsSL -o /tmp/wp-cli.phar https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
  chmod +x /tmp/wp-cli.phar
  mv /tmp/wp-cli.phar /usr/local/bin/wp
fi
ok "WP-CLI terinstall: $(wp --version 2>/dev/null | head -1)"

step "Menginstall Certbot (via snap — aman)..."
if ! command -v certbot >/dev/null 2>&1; then
  apt-get install -y snapd >/dev/null 2>&1
  snap install core >/dev/null 2>&1
  snap refresh core >/dev/null 2>&1 || true
  snap install --classic certbot >/dev/null 2>&1
  ln -sfn /snap/bin/certbot /usr/local/bin/certbot
fi
ok "Certbot terinstall: $(certbot --version 2>/dev/null | head -1)"

ok "Module 06 selesai — WP-CLI + Certbot siap."
