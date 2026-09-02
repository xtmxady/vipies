#!/bin/bash
# ============================================================
#  vipies — 01-system.sh
#  Update sistem + install dependensi dasar
# ============================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source modules/lib.sh

step "Update apt & upgrade sistem..."
export DEBIAN_FRONTEND=noninteractive
apt-get update >/dev/null 2>&1
apt-get upgrade -y >/dev/null 2>&1
ok "Sistem di-update"

step "Menginstall dependensi dasar..."
APT_PKGS="curl wget git unzip zip build-essential software-properties-common ca-certificates gnupg lsb-release ufw"
for pkg in $APT_PKGS; do ensure "$pkg"; done
ok "Dependensi dasar terinstall"

step "Mengaktifkan firewall (UFW)..."
apt-get install -y ufw >/dev/null 2>&1
ufw allow OpenSSH >/dev/null 2>&1
ufw allow 80/tcp >/dev/null 2>&1
ufw allow 443/tcp >/dev/null 2>&1
if command -v systemctl >/dev/null 2>&1 && [ "$(ufw status | grep -c 'Status: active')" = "0" ]; then
  echo "y" | ufw enable >/dev/null 2>&1
  ok "UFW aktif (22/80/443)"
else
  warn "UFW sudah aktif atau tidak bisa di-enable otomatis"
fi

# timezone default UTC, ganti bila perlu
timedatectl set-timezone UTC >/dev/null 2>&1 || true

ok "Module 01 selesai."
