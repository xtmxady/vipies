#!/bin/bash
# ============================================================
#  vipies — 03-node.sh
#  Install Node.js (default versi terbaru LTS, bisa pilih) + PM2
# ============================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source modules/lib.sh

# Pilih versi Node (default 22 LTS)
if [ -z "${NODE_VERSION:-}" ]; then
  read -rp "  Versi Node.js default [22] (22=LTS, 20, 18): " ans
  NODE_VERSION="${ans:-22}"
fi

install_node "$NODE_VERSION"

step "Menginstall PM2 (process manager)..."
if ! command -v pm2 >/dev/null 2>&1; then
  npm install -g pm2 >/dev/null 2>&1
fi
# PM2 startup biar auto-restart saat reboot
pm2 startup systemd -u "$(whoami)" --hp "$HOME" >/dev/null 2>&1 || true
ok "PM2 $(pm2 --version) terinstall + startup aktif"

ok "Module 03 selesai."
