#!/bin/bash
# ============================================================
#  vipies — Ubuntu Server Setup (one-shot provisioning)
#  https://github.com/xtmxady/vipies
#
#  Modular installer untuk Ubuntu 24.04:
#  Nginx, Node.js, PHP-FPM+OPcache, MySQL, WP-CLI, Certbot,
#  Backup R2, Monitoring Telegram, Auto-restart, Auto-permission.
#
#  Cara pakai:
#    git clone https://github.com/xtmxady/vipies
#    cd vipies && cp .env.example .env && nano .env
#    sudo bash setup.sh
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
banner() { echo -e "\n${GREEN}╔══════════════════════════════════════╗${NC}"; echo -e "${GREEN}║   ${NC}vipies — Ubuntu Server Setup${GREEN}      ║${NC}"; echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"; }

# ---------- Load .env ----------
load_env() {
  if [ -f ".env" ]; then
    set -a; source .env; set +a
  fi
}

# ---------- Validasi OS ----------
check_os() {
  if ! grep -qi ubuntu /etc/os-release; then
    echo -e "${RED}✗ vipies hanya mendukung Ubuntu.${NC}"; exit 1
  fi
  echo -e "${GREEN}✓ Ubuntu terdeteksi: $(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY | cut -d= -f2)${NC}"
}

# ---------- Root check ----------
check_root() {
  if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}✗ Jalankan sebagai root: sudo bash setup.sh${NC}"; exit 1
  fi
}

# ---------- Run module ----------
run_module() {
  local file="$1" name="$2"
  if [ ! -f "modules/$file" ]; then
    echo -e "${RED}✗ Module $file tidak ditemukan.${NC}"; return 1
  fi
  echo -e "\n${YELLOW}▶ Menjalankan module: $name${NC}"
  bash "modules/$file"
  echo -e "${GREEN}✓ $name selesai.${NC}"
}

# ---------- Menu ----------
menu() {
  echo ""
  echo "  1) Full install (semua modul)"
  echo "  2) Sistem dasar (update, deps)"
  echo "  3) Nginx + template WP/Custom"
  echo "  4) Node.js + PM2"
  echo "  5) PHP-FPM + OPcache"
  echo "  6) MySQL + buat DB + ganti pass"
  echo "  7) WP-CLI + Certbot SSL"
  echo "  8) Backup R2 + cron"
  echo "  9) Monitoring + notif Telegram"
  echo " 10) Auto-restart service"
  echo " 11) Auto-fix permission"
  echo "  0) Keluar"
  echo -n "Pilih [0-11]: "; read -r choice
  echo ""
}

# ================= MAIN =================
banner
load_env
check_root
check_os

while true; do
  menu
  case "$choice" in
    1)
      run_module 01-system.sh "Sistem dasar" || exit 1
      run_module 02-nginx.sh "Nginx" || exit 1
      run_module 03-node.sh "Node.js" || exit 1
      run_module 04-php.sh "PHP-FPM" || exit 1
      run_module 05-mysql.sh "MySQL" || exit 1
      run_module 06-wpcli.sh "WP-CLI + Certbot" || exit 1
      run_module 07-backup.sh "Backup R2" || exit 1
      run_module 08-monitoring.sh "Monitoring" || exit 1
      run_module 09-autorestart.sh "Auto-restart" || exit 1
      run_module 10-permission.sh "Auto-fix permission" || exit 1
      echo -e "\n${GREEN}✓✓ SEMUA MODUL SELESAI! Server siap.${NC}"
      ;;
    2) run_module 01-system.sh "Sistem dasar" ;;
    3) run_module 02-nginx.sh "Nginx" ;;
    4) run_module 03-node.sh "Node.js" ;;
    5) run_module 04-php.sh "PHP-FPM" ;;
    6) run_module 05-mysql.sh "MySQL" ;;
    7) run_module 06-wpcli.sh "WP-CLI + Certbot" ;;
    8) run_module 07-backup.sh "Backup R2" ;;
    9) run_module 08-monitoring.sh "Monitoring" ;;
   10) run_module 09-autorestart.sh "Auto-restart" ;;
   11) run_module 10-permission.sh "Auto-fix permission" ;;
    0) echo -e "${GREEN}Selesai. Bye!${NC}"; exit 0 ;;
    *) echo -e "${RED}Pilihan tidak valid.${NC}" ;;
  esac
done
