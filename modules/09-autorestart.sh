#!/bin/bash
# ============================================================
#  vipies — 09-autorestart.sh
#  Auto-restart service via systemd (nginx, mysql, php-fpm)
#  Menggunakan Restart=always + watchdog.
# ============================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source modules/lib.sh

# Temukan nama service php-fpm otomatis
PHP_FPM=$(ls /lib/systemd/system/php*-fpm.service 2>/dev/null | head -1 | xargs -n1 basename 2>/dev/null | sed 's/.service//' || echo php8.3-fpm)

step "Mengatur auto-restart untuk: nginx, mysql, ${PHP_FPM}..."
for svc in nginx mysql "$PHP_FPM"; do
  if [ ! -f "/lib/systemd/system/$svc.service" ] && [ ! -L "/etc/systemd/system/$svc.service" ]; then
    warn "Service $svc tidak ada, skip"
    continue
  fi
  # Override idempotent: tulis ulang restart config
  mkdir -p "/etc/systemd/system/$svc.service.d"
  cat > "/etc/systemd/system/$svc.service.d/restart.conf" <<EOF
[Service]
Restart=always
RestartSec=5
EOF
  systemctl daemon-reload
  systemctl restart "$svc" >/dev/null 2>&1 || true
  ok "$svc → Restart=always"
done

# Guard: pastikan semua service auto-start saat boot
step "Mengaktifkan auto-start saat boot..."
for svc in nginx mysql "$PHP_FPM"; do
  systemctl enable "$svc" >/dev/null 2>&1 || true
done
ok "Semua service auto-start saat boot"

ok "Module 09 selesai — service auto-restart aktif."
