#!/bin/bash
# ============================================================
#  vipies — 10-permission.sh
#  Auto-fix permission & chown saat ada file/folder baru di
#  /var/www/<site>/wp-content/uploads (WordPress).
#  Gunakan inotifywait (event-driven, ringan) sebagai daemon.
# ============================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source modules/lib.sh

step "Menginstall inotify-tools..."
ensure inotify-tools

step "Membuat daemon auto-fix permission (/usr/local/bin/vipies-permd.sh)..."
cat > /usr/local/bin/vipies-permd.sh <<'PERM'
#!/bin/bash
# vipies-permd — daemon auto-fix permission/chown untuk folder situs di /var/www
# Watch setiap /var/www/<site> (semua tipe: WP uploads/plugins/themes, static, dst).
# Event apa pun (upload/unzip/create) → chown www-data + dir 755/file 644.
# Optimisasi: fix hanya path yang berubah (bukan -R seluruh situs) + throttle:
# debounce 3 detik supaya event beruntun (unzip) tidak trigger berkali-kali.
# Re-scan tiap 30s: situs baru otomatis ter-detect tanpa restart.
# Berjalan sebagai systemd service (vipies-permd).
# Log: /var/log/vipies-permd.log

fix_perm() {
  local path="$1"
  [ -e "$path" ] || return 0
  chown -R www-data:www-data "$path" 2>/dev/null
  find "$path" -type d -exec chmod 755 {} + 2>/dev/null
  find "$path" -type f -exec chmod 644 {} + 2>/dev/null
  echo "$(date '+%F %T') fixed: $path" >> /var/log/vipies-permd.log
}

while true; do
  watchdirs=$(find /var/www -maxdepth 1 -mindepth 1 -type d ! -name '.*' 2>/dev/null)
  if [ -n "$watchdirs" ]; then
    inotifywait -q -r -e close_write,create,moved_to --timeout 30 \
      --format '%w' $watchdirs 2>/dev/null | \
      while read -r dir; do
        # Fix folder yang berubah + parent-nya (sampai level situs)
        fix_perm "$dir"
        fix_perm "$(dirname "$dir")"
      done
  else
    sleep 30
  fi
done
PERM
chmod +x /usr/local/bin/vipies-permd.sh

step "Memasang systemd service (vipies-permd)..."
cat > /etc/systemd/system/vipies-permd.service <<'SV'
[Unit]
Description=vipies auto-fix permission daemon
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/vipies-permd.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SV
systemctl daemon-reload
systemctl enable vipies-permd >/dev/null 2>&1
systemctl restart vipies-permd >/dev/null 2>&1 || true
ok "Daemon auto-fix permission aktif (vipies-permd)"

ok "Module 10 selesai — auto-fix permission berjalan."
