#!/usr/bin/env bash
# ============================================================
# vipies — Modul 13: Install Core (9router + Hermes + system deps)
# Dipakai di VPS BARU. Urutan sesuai permintaan Mas Ady:
#   1) apt update/upgrade + curl/ufw
#   2) Node.js via NodeSource (>= 20)
#   3) 9router (npm global) — DULUAN dari Hermes
#   4) UFW buka 20128 (port 9router dashboard)
#   5) Hermes (installer resmi curl) — SETELAH 9router
#   6) hermes doctor + hermes setup
# Restore config = modul TERPISAH (14-config-backup.sh),
# jalan SETELAH paket inti terinstall.
# ============================================================
set -u
cd "$(dirname "$0")/.."
source modules/lib.sh

NC='\033[0m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
log() { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
err() { echo -e "${RED}✗${NC} $*"; }

# ---------- 1. apt update + upgrade + dasar ----------
step "apt update & upgrade..."
export DEBIAN_FRONTEND=noninteractive
apt-get update >/dev/null 2>&1
apt-get upgrade -y >/dev/null 2>&1
apt-get install -y curl ufw unzip zip >/dev/null 2>&1
log "apt siap"

# ---------- 2. Node.js >= 20 via NodeSource ----------
if ! command -v node >/dev/null 2>&1; then
  step "Install Node.js 20 via NodeSource..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
  apt-get install -y nodejs >/dev/null 2>&1
else
  log "Node.js sudah ada ($(node -v))"
fi
node -v | grep -qE "v(2[0-9]|1[0-9])" || warn "Node < 20 — upgrade manual disarankan (node -v: $(node -v))"

# ---------- 3. 9router (npm global) — DULUAN ----------
if ! command -v 9router >/dev/null 2>&1; then
  step "Install 9router (npm global)..."
  npm install -g 9router >/dev/null 2>&1 || { err "Gagal install 9router."; exit 1; }
else
  log "9router sudah ada ($(9router --version 2>&1 | head -1))"
fi
9router --version 2>&1 | head -1 | xargs -I{} log "9router {}"

# ---------- 4. UFW buka port 20128 ----------
step "UFW buka 20128..."
ufw allow 20128/tcp >/dev/null 2>&1
ufw enable >/dev/null 2>&1
ufw status | grep -E "20128|Status" | head -3
log "UFW aktif, port 20128 dibuka"

# ---------- 5. Hermes (installer resmi) — SETELAH 9router ----------
if ! command -v hermes >/dev/null 2>&1; then
  step "Install Hermes Agent (installer resmi)..."
  curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash >/dev/null 2>&1 || { err "Gagal install Hermes."; exit 1; }
else
  log "Hermes sudah ada ($(hermes --version 2>&1 | head -1))"
fi

# ---------- 6. hermes doctor + setup ----------
step "hermes doctor..."
source ~/.bashrc 2>/dev/null || true
hermes doctor 2>&1 | tail -8 || warn "hermes doctor error — lanjut setup"
step "hermes setup..."
hermes setup >/dev/null 2>&1 || warn "hermes setup belum selesai — jalankan manual: hermes setup"

log "Modul 13 selesai. 9router + Hermes terinstall."
log "SELANJUTNYA jalankan modul 14 (Backup/Restore config) untuk pulihkan config server."