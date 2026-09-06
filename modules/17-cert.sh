#!/bin/bash
# ============================================================
#  vipies — 17-cert.sh
#  Install & pasang SSL cert (Let's Encrypt via certbot) untuk domain.
#  Helper: vipies-cert <domain>   — cek DNS dulu, baru certbot.
#  Terpisah dari pembuatan situs: bikin situs dulu (tanpa SSL),
#  point DNS, lalu jalankan ini. Tidak perlu butuh DNS saat new-site.
# ============================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source modules/lib.sh

# Pastikan certbot ada
if ! command -v certbot >/dev/null 2>&1; then
  step "Install Certbot (snap)..."
  apt-get install -y snapd >/dev/null 2>&1
  snap install core >/dev/null 2>&1
  snap refresh core >/dev/null 2>&1 || true
  snap install --classic certbot >/dev/null 2>&1
  ln -sfn /snap/bin/certbot /usr/local/bin/certbot
fi
ok "Certbot: $(certbot --version 2>/dev/null | head -1)"

# Helper vipies-cert
cat > /usr/local/bin/vipies-cert <<'HELPER'
#!/bin/bash
# vipies-cert <domain> — pasang SSL Let's Encrypt untuk domain.
# Syarat: DNS domain sudah pointing ke server ini (A/AAAA record).
set -euo pipefail
DOMAIN="$1"
[ -z "$DOMAIN" ] && { echo "Usage: vipies-cert <domain>"; exit 1; }

# Validasi nama domain
case "$DOMAIN" in
  *[!a-zA-Z0-9.-]*|*..*) echo "Domain tidak valid: $DOMAIN"; exit 1 ;;
esac

# Cek config nginx domain ada
[ -f "/etc/nginx/sites-available/$DOMAIN" ] || { echo "Config nginx $DOMAIN tidak ada. Buat dulu: vipies-add-site $DOMAIN wp"; exit 1; }

# Cek DNS pointing ke server ini (pakai resolver publik biar akurat)
MYIP=$(hostname -I | awk '{print $1}')
echo "  → Cek DNS $DOMAIN ..."
RESOLVED=$(getent ahostsv4 "$DOMAIN" 2>/dev/null | awk '{print $1}' | head -1)
[ -z "$RESOLVED" ] && RESOLVED=$(dig +short @1.1.1.1 "$DOMAIN" A 2>/dev/null | head -1)
echo "    IP domain:  $RESOLVED"
echo "    IP server:  $MYIP"
if [ "$RESOLVED" != "$MYIP" ]; then
  echo ""
  echo "⚠ DNS BELUM pointing ke server ini."
  echo "  Set A record: $DOMAIN + www → $MYIP (di panel DNS/Cloudflare/Bunny)"
  echo "  Tunggu propagate, lalu jalankan lagi: vipies-cert $DOMAIN"
  exit 1
fi

# Jika sudah ada cert, cek validitas
if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
  echo "  → Cert sudah ada. Cek masa berlaku..."
  if openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" 2>/dev/null | grep -q "Not After"; then
    echo "    $(openssl x509 -enddate -noout -in /etc/letsencrypt/live/$DOMAIN/fullchain.pem)"
    read -rp "  Renew? [y/N]: " ans
    [ "${ans:-n}" = "y" ] || { echo "  Dilewati."; exit 0; }
  fi
fi

# Jalankan certbot (--nginx pakai blok 80; --redirect aktifkan HTTPS+redirect)
echo "  → Request cert via certbot..."
if certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" --non-interactive --agree-tos --redirect --email "admin@$DOMAIN"; then
  # Certbot --nginx otomatis ubah config: tambah blok 443 + redirect.
  systemctl reload nginx
  echo ""
  echo "✅ SSL aktif: https://$DOMAIN"
  echo "  Auto-renew aktif (certbot timer)."
else
  echo "✗ Certbot gagal. Cek: port 80 terbuka? DNS proxy (Cloudflare orange cloud) bisa blokir."
  echo "  Kalau pakai Cloudflare proxy: set DNS-only (grey cloud) dulu, lalu jalankan lagi."
  exit 1
fi
HELPER
chmod +x /usr/local/bin/vipies-cert
ok "Helper 'vipies-cert' terpasang — jalankan setelah DNS pointing: vipies-cert <domain>"

ok "Module 17 selesai."