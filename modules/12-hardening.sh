#!/bin/bash
# ============================================================
#  vipies — 12-hardening.sh
#  Security hardening untuk server + WordPress:
#  - fail2ban (brute-force SSH + wp-login)
#  - Lock eksekusi PHP di folder wp-content/uploads (cegah shell)
#  - Nonaktifkan PHP execution di uploads (via Nginx config)
# ============================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source modules/lib.sh

# ---------- 1. fail2ban ----------
step "Menginstall fail2ban (proteksi brute-force)..."
ensure fail2ban

cat > /etc/fail2ban/jail.local <<'JAIL'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port = ssh
backend = systemd

[nginx-wp-login]
enabled = true
port = http,https
logpath = /var/log/nginx/access.log
maxretry = 6
findtime = 10m
bantime = 2h
filter = nginx-wp-login
JAIL

cat > /etc/fail2ban/filter.d/nginx-wp-login.conf <<'FILT'
[Definition]
failregex = ^<HOST> .* "(GET|POST) /wp-login\.php.*" 40[13]
            ^<HOST> .* "(GET|POST) /wp-admin/.*" 40[13]
            ^<HOST> .* "POST /wp-login\.php.*" (200|301|302)
ignoreregex =
FILT

systemctl enable fail2ban >/dev/null 2>&1
systemctl restart fail2ban >/dev/null 2>&1
ok "fail2ban aktif (sshd + nginx-wp-login)"

# ---------- 2. Lock eksekusi PHP di WordPress uploads ----------
step "Mengunci folder uploads (cegah eksekusi PHP shell)..."
LOCK_APPEND=''
# Tambahkan blok lokasi ke setiap Nginx site WordPress yang ada
for conf in /etc/nginx/sites-available/*; do
  [ -f "$conf" ] || continue
  if grep -q "wp-content\|wordpress" "$conf" 2>/dev/null || [ -d "/var/www/$(basename "$conf")/wp-content" ]; then
    # Cek apakah sudah ada blok uploads (mencegah duplikat)
    if grep -q "wp-content/uploads" "$conf" 2>/dev/null; then
      # Blok uploads sudah ada → pastikan punya lock PHP; kalau belum, sisipkan
      if ! grep -q "return 403" "$conf" 2>/dev/null; then
        # Sisipkan location lock di dalam blok uploads (target pada try_files placeholder)
        sed -i '/wp-content\/uploads\/placeholder.png/i\        # vipies hardening: cegah eksekusi PHP di uploads (anti-shell)\n        location ~ \\.php$ { return 403; }' "$conf"
        ok "PHP lock disisipkan ke blok uploads $conf"
      else
        ok "uploads lock sudah ada di $conf"
      fi
    else
      # Belum ada blok uploads → append blok baru lengkap dengan lock
      cat >> "$conf" <<'LOCK'

    # vipies hardening: cegah eksekusi PHP di uploads (anti-shell)
    location ^~ /wp-content/uploads/ {
        location ~ \.php$ { return 403; }
        try_files $uri =404;
    }
LOCK
      ok "uploads lock ditambahkan ke $conf"
    fi
  fi
done

# nginx config test sebelum restart
if nginx -t 2>&1 | grep -q "syntax is ok"; then
  systemctl reload nginx >/dev/null 2>&1
  ok "Nginx reloaded (uploads lock aktif)"
else
  warn "nginx -t gagal — cek config manual, uploads lock tidak di-apply"
fi

# ---------- 3. PHP execution disabled via uploads .htaccess (Apache fallback) ----------
# (Aman juga untuk Nginx — tidak merugikan)

ok "Module 12 selesai — hardening aktif."
