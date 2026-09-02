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
# vipies-permd — daemon auto-fix permission/chown untuk folder WordPress uploads
# Watch setiap /var/www/*/wp-content/uploads, lalu chown www-data + chmod saat ada perubahan.
# Berjalan sebagai systemd service (vipies-permd).
# Directorys: /var/www/<site>/wp-content/uploads (rekursif)
# Log: /var/log/vipies-permd.log

watchdirs=$(find /var/www -maxdepth 3 -type d -path '*/wp-content/uploads' 2>/dev/null)
[ -z "$watchdirs" ] && exit 0

fix_perm() {
  # chown semua ke www-data, dlm/krn (dir 755, file 644) utk folder uploads
  chown -R www-data:www-data "$1" 2>/dev/null
  find "$1" -type d -exec chmod 755 {} + 2>/dev/null
  find "$1" -type f -exec chmod 644 {} + 2>/dev/null
  echo "$(date '+%F %T') fixed: $1" >> /var/log/vipies-permd.log
}

# Initial fix sekali
for d in $watchdirs; do fix_perm "$d"; done

# Watch kontinu
inotifywait -m -q -r -e close_write,create,moved_to \
  --format '%w' $watchdirs 2>/dev/null | \
  while read -r dir; do
    fix_perm "$(dirname "$dir")"  # fix folder uploads penuh saat ada event
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
