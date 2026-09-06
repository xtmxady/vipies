#!/bin/bash
# ============================================================
#  vipies — 18-delete-site.sh
#  Helper 'vipies-delete-site' — hapus situs lengkap:
#  direktori /var/www, database + user MySQL, config nginx,
#  SSL cert (certbot delete), dan entry r2-sites.conf.
#  DESTRUCTIVE — konfirmasi ganda wajib.
# ============================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source modules/lib.sh

cat > /usr/local/bin/vipies-delete-site <<'HELPER'
#!/bin/bash
# vipies-delete-site <domain> — hapus situs lengkap (irreversible!).
# Hapus: direktori /var/www/<domain>, DB + user MySQL, config nginx,
#        SSL cert (kalau ada), entry /root/r2-sites.conf.
set -euo pipefail

DOMAIN="${1:-}"
[ -z "$DOMAIN" ] && { echo "Usage: vipies-delete-site <domain>"; exit 1; }

# ---------- Denylist (jangan pernah hapus ini) ----------
DENY="^(html|adminer|global-assets|hermes-backup|teststatis.com|hrms)$"
if echo "$DOMAIN" | grep -qE "$DENY"; then
  echo "✗ '$DOMAIN' ada di denylist — tidak boleh dihapus!"
  exit 1
fi
# Juga blokir domain yang masih dipakai layanan inti
case "$DOMAIN" in
  seribukafetrk.com|www.seribukafetrk.com|merahbirunews.com|www.merahbirunews.com|jadwal.seribukafetrk.com|hannafatimatuzzahro.com)
    echo "✗ '$DOMAIN' adalah situs inti/live — tidak diizinkan dihapus lewat helper ini."
    exit 1 ;;
esac

WEBROOT="/var/www/$DOMAIN"
[ -d "$WEBROOT" ] || { echo "⚠ Direktori $WEBROOT tidak ada."; }

# ---------- Konfirmasi ganda ----------
echo "⚠️  AKSI DESTRUKTIF — akan menghapus SEMUA data situs:"
echo "    - Direktori : $WEBROOT"
echo "    - Nginx     : /etc/nginx/sites-available|enabled/$DOMAIN"
echo "    - SSL cert  : $DOMAIN (certbot, kalau ada)"
echo "    - DB + user : dari wp-config / r2-sites.conf"
echo ""
read -rp "Ketik nama domain PERSIS untuk lanjut: " CONFIRM
[ "$CONFIRM" = "$DOMAIN" ] || { echo "✗ Konfirmasi gagal. Batal."; exit 1; }
read -rp "Yakin? Ketik 'HAPUS' untuk konfirmasi kedua: " CONFIRM2
[ "$CONFIRM2" = "HAPUS" ] || { echo "✗ Konfirmasi kedua gagal. Batal."; exit 1; }

echo ""

# ---------- Baca DB creds SEBELUM hapus direktori ----------
DBNAME=""; DBUSER=""
if [ -f "$WEBROOT/wp-config.php" ]; then
  DBNAME=$(grep "DB_NAME" "$WEBROOT/wp-config.php" | head -1 | cut -d"'" -f4)
  DBUSER=$(grep "DB_USER" "$WEBROOT/wp-config.php" | head -1 | cut -d"'" -f4)
fi
if [ -z "$DBNAME" ] && [ -f /root/r2-sites.conf ]; then
  CONF=$(grep "^${DOMAIN}|" /root/r2-sites.conf | head -1 | cut -d'|' -f2- || true)
  [ -n "$CONF" ] && DBNAME="${CONF%%|*}"
  [ -n "$CONF" ] && DBUSER="$(echo "$CONF" | cut -d'|' -f2)"
fi

echo "=== [1/5] Hapus direktori $WEBROOT ==="
rm -rf "$WEBROOT" && echo "  ✓ Direktori dihapus" || echo "  ⚠ Gagal hapus direktori"

echo "=== [2/5] Hapus DB + user MySQL ==="
if [ -n "$DBNAME" ]; then
  mysql -e "DROP DATABASE IF EXISTS \`$DBNAME\`;"
  echo "  ✓ DB '$DBNAME' dihapus"
else
  echo "  - DB tidak ditemukan, skip"
fi
if [ -n "$DBUSER" ]; then
  mysql -e "DROP USER IF EXISTS '$DBUSER'@'localhost'; FLUSH PRIVILEGES;"
  echo "  ✓ User '$DBUSER' dihapus"
else
  echo "  - User tidak ditemukan, skip"
fi

echo "=== [3/5] Hapus config nginx ==="
NGINX_CONF=""
if [ -f "/etc/nginx/sites-available/$DOMAIN" ]; then
  NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"
elif [ -f "/etc/nginx/sites-available/${DOMAIN%.*}" ]; then  # domain.com -> domain
  NGINX_CONF="/etc/nginx/sites-available/${DOMAIN%.*}"
else
  # Cari config yang server_name-nya = domain ini
  NGINX_CONF=$(grep -rl "server_name[[:space:]]\+$DOMAIN" /etc/nginx/sites-available/ 2>/dev/null | head -1 || true)
fi
if [ -n "$NGINX_CONF" ]; then
  BASE=$(basename "$NGINX_CONF")
  rm -f "/etc/nginx/sites-enabled/$BASE"
  rm -f "$NGINX_CONF"
  nginx -t && systemctl reload nginx
  echo "  ✓ Nginx config '$BASE' dihapus + reload"
else
  echo "  - Config nginx tidak ditemukan, skip"
fi

echo "=== [4/5] Hapus SSL cert (certbot) ==="
if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
  certbot delete --cert-name "$DOMAIN" --non-interactive >/dev/null 2>&1 && echo "  ✓ Cert '$DOMAIN' dihapus" || echo "  ⚠ Gagal hapus cert (cek manual: certbot delete --cert-name $DOMAIN)"
else
  echo "  - Cert tidak ada, skip"
fi

echo "=== [5/5] Hapus dari r2-sites.conf ==="
if [ -f /root/r2-sites.conf ]; then
  sed -i "/^${DOMAIN}|/d" /root/r2-sites.conf
  echo "  ✓ Entry r2-sites.conf dihapus"
fi

echo ""
echo "✅ Situs '$DOMAIN' telah dihapus."
echo "   Backup R2 lama di bucket tetap ada (retensi handle)."
echo "   Ingin hapus backup R2 juga? Hapus manual: rclone delete r2:hermes/$DOMAIN --recursive"
HELPER
chmod +x /usr/local/bin/vipies-delete-site
ok "Helper 'vipies-delete-site' terpasang — DESTRUCTIVE, konfirmasi ganda."
ok "Module 18 selesai."