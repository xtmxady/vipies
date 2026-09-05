#!/bin/bash
# ============================================================
#  vipies — 14-swap.sh
#  Pastikan swap 2GB tersedia (default) — buat kalau belum ada.
#  Idempotent: kalau swap sudah >= 2GB, lewati.
# ============================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source modules/lib.sh

SWAP_SIZE=${SWAP_SIZE:-2G}
SWAPFILE=/swap.img

# Prompt interaktif: ukuran swap (default 2G, isi angka = GB)
if [ -z "$SWAP_SIZE_ENV" ]; then
  read -rp "  Ukuran swap default [2] (GB, contoh: 2, 4, 8): " ans
  ans=${ans:-2}
  case "$ans" in
    ''|*[!0-9]*) ans=2 ;;
  esac
  SWAP_SIZE="${ans}G"
fi

current_swap() {
  swapon --show=size --noheadings -b 2>/dev/null | awk '{s+=$1} END{print s+0}'
}

step "Memeriksa swap..."
CUR=$(current_swap)
# konversi ukuran target ke byte (2G = 2*1024^3)
case "$SWAP_SIZE" in
  *G) TARGET_BYTES=$(( ${SWAP_SIZE%G} * 1024 * 1024 * 1024 )) ;;
  *M) TARGET_BYTES=$(( ${SWAP_SIZE%M} * 1024 * 1024 )) ;;
  *)  TARGET_BYTES=$SWAP_SIZE ;;
esac

if [ "$CUR" -ge "$TARGET_BYTES" ]; then
  ok "Swap sudah ada ($(swapon --show --noheadings 2>/dev/null | awk '{print $2}' | tr -d '\n')), lewati."
  exit 0
fi

warn "Swap saat ini ${CUR}B / target ${SWAP_SIZE} — membuat/memperbesar..."

# Pastikan file swapfile ada (atau buat baru)
if [ -f "$SWAPFILE" ]; then
  swapoff "$SWAPFILE" 2>/dev/null || true
else
  step "Membuat swapfile ${SWAP_SIZE}..."
  fallocate -l "$SWAP_SIZE" "$SWAPFILE" 2>/dev/null || dd if=/dev/zero of="$SWAPFILE" bs=1M count=$(( ${SWAP_SIZE%G} * 1024 )) status=none
  chmod 600 "$SWAPFILE"
  ok "Swapfile dibuat"
fi

step "Mengaktifkan swapfile..."
mkswap "$SWAPFILE" >/dev/null 2>&1
swapon "$SWAPFILE" >/dev/null 2>&1

# Pastikan masuk fstab biar survive reboot
grep -q "^${SWAPFILE}" /etc/fstab || echo "${SWAPFILE} none swap sw 0 0" >> /etc/fstab

# Tuning swapiness (buat server, agak rendah biar RAM dipakai dulu)
sysctl -w vm.swappiness=10 >/dev/null 2>&1 || true
grep -q "vm.swappiness" /etc/sysctl.conf || echo "vm.swappiness=10" >> /etc/sysctl.conf

ok "Swap ${SWAP_SIZE} aktif. swappiness=10."
ok "Module 14 (swap) selesai."
