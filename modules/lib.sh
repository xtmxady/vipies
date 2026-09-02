#!/bin/bash
# ============================================================
#  vipies — lib.sh (fungsi bersama untuk semua modul)
#  Di-source oleh setiap modul. TIDAK dieksekusi langsung.
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

# --- Notif Telegram (di-load dari .env di setup.sh) ---
tg_send() {
  local msg="$1"
  if [ -n "${TG_BOT_TOKEN:-}" ] && [ -n "${TG_CHAT_ID:-}" ]; then
    curl -s -o /dev/null "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
      -d "chat_id=${TG_CHAT_ID}" --data-urlencode "text=${msg}" 2>/dev/null || true
  fi
}

# --- Install if not present ---
ensure() { # ensure <package>
  if ! dpkg -s "$1" >/dev/null 2>&1; then
    echo -e "${YELLOW}  Installing $1...${NC}"
    DEBIAN_FRONTEND=noninteractive apt-get install -y "$1" >/dev/null 2>&1
  fi
}

step() { echo -e "\n${GREEN}▶ $1${NC}"; }
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠ $1${NC}"; }

# --- Node.js via NodeSource (versi pilihan) ---
install_node() { # install_node <major_version, default 20>
  local ver="${1:-20}"
  if command -v node >/dev/null 2>&1; then
    ok "Node.js sudah ada: $(node -v)"
    return
  fi
  step "Menginstall Node.js $ver via NodeSource..."
  curl -fsSL "https://deb.nodesource.com/setup_${ver}.x" | bash - >/dev/null 2>&1
  apt-get install -y nodejs >/dev/null 2>&1
  ok "Node.js $(node -v) terinstall"
}
