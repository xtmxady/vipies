#!/bin/bash
# ============================================================
#  vipies — 05-mysql.sh
#  Install MySQL, set root password, buat database+user
# ============================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source modules/lib.sh

step "Menginstall MySQL Server..."
apt-get install -y mysql-server >/dev/null 2>&1
systemctl enable mysql >/dev/null 2>&1
systemctl start mysql >/dev/null 2>&1
ok "MySQL terinstall: $(mysql --version | grep -oE '[0-9.]+' | head -1)"

# --- Set root password ---
step "Mengatur password root MySQL..."
if [ -n "${MYSQL_ROOT_PASSWORD:-}" ]; then
  # Pakai socket auth untuk set password
  mysql -u root <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '${MYSQL_ROOT_PASSWORD}';
FLUSH PRIVILEGES;
SQL
  ok "Password root di-set (dari .env)"
else
  echo -n "  Masukkan password root MySQL: "; read -rs rootpass; echo ""
  mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '${rootpass}'; FLUSH PRIVILEGES;"
  MYSQL_ROOT_PASSWORD="$rootpass"
  ok "Password root di-set"
fi

# --- Helper CLI: vipies-db ---
cat > /usr/local/bin/vipies-db <<'HELPER'
#!/bin/bash
# vipies — kelola database MySQL
# Usage:
#   vipies-db create <db> <user> <pass>   # buat db + user
#   vipies-db drop <db>                   # hapus db
#   vipies-db pass <user> <newpass>       # ganti pass user
#   vipies-db rootpass <newpass>          # ganti pass root
set -euo pipefail
MYSQL="mysql -u root"
case "$1" in
  create)
    MYSQL -e "CREATE DATABASE IF NOT EXISTS \`$2\`; CREATE USER IF NOT EXISTS '$3'@'localhost' IDENTIFIED BY '$4'; GRANT ALL PRIVILEGES ON \`$2\`.* TO '$3'@'localhost'; FLUSH PRIVILEGES;"
    echo "✓ DB $2 + user $3 dibuat";;
  drop)
    MYSQL -e "DROP DATABASE IF EXISTS \`$2\`;"
    echo "✓ DB $2 dihapus";;
  pass)
    MYSQL -e "ALTER USER '$2'@'localhost' IDENTIFIED WITH caching_sha2_password BY '$3'; FLUSH PRIVILEGES;"
    echo "✓ Password user $2 diubah";;
  rootpass)
    MYSQL -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '$2'; FLUSH PRIVILEGES;"
    echo "✓ Password root diubah";;
  *) echo "Usage: vipies-db {create|drop|pass|rootpass} ..."; exit 1;;
esac
HELPER
chmod +x /usr/local/bin/vipies-db
ok "Helper 'vipies-db' tersedia (create/drop/pass/rootpass)"

ok "Module 05 selesai."
