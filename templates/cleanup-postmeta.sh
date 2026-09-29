#!/bin/bash
# Bersihkan meta_key dari plugin yang sudah tidak aktif di merahbirunews.
# - sm_cloud          -> wp-stateless (tidak aktif)
# - wp-smpro-smush-data -> Smush Pro (tidak aktif)
# - snapFB/snapTW/snap_MYSURL/snap_isAutoPosted -> SNAP (tidak aktif)
# - _edit_lock        -> lock editor WP, timeout 6 jam, semua sudah kedaluwarsa
#
# TIDAK dihapus: _feedback_email / _feedback_extra_fields (dipakai Jetpack Forms).
set -euo pipefail

STAMP=$(date +%Y%m%d-%H%M)
OUT="/root/postmeta-cleanup-$STAMP"
mkdir -p "$OUT"

echo "=== 1. Dump meta_key yang akan dihapus (backup) ==="
sudo mysqldump --no-create-info --skip-add-locks --complete-insert \
  merahbiru wp_postmeta \
  --where="meta_key IN ('sm_cloud','wp-smpro-smush-data','snapFB','snapTW','snap_MYSURL','snap_isAutoPosted','_edit_lock')" \
  > "$OUT/postmeta-deadkeys.sql" 2>/dev/null

SQLSIZE=$(stat -c%s "$OUT/postmeta-deadkeys.sql")
ROWS=$(grep -c "^INSERT INTO" "$OUT/postmeta-deadkeys.sql" || echo 0)
echo "  backup: $OUT/postmeta-deadkeys.sql ($(numfmt --to=iec $SQLSIZE), $ROWS statement)"

if [ "$SQLSIZE" -lt 10000 ]; then
  echo "  ⚠️ backup terlalu kecil — batal, tidak ada perubahan"
  exit 1
fi

echo ""
echo "=== 2. Sebelum ==="
sudo mysql -N -e "SELECT CONCAT('  wp_postmeta: ', COUNT(*), ' baris / ', ROUND(SUM(data_length+index_length)/1048576),' MB') FROM information_schema.TABLES WHERE table_schema='merahbiru' AND table_name='wp_postmeta'" 2>/dev/null

echo ""
echo "=== 3. Hapus ==="
sudo mysql -e "DELETE FROM merahbiru.wp_postmeta WHERE meta_key IN ('sm_cloud','wp-smpro-smush-data','snapFB','snapTW','snap_MYSURL','snap_isAutoPosted','_edit_lock')" 2>/dev/null
DELETED=$(sudo mysql -N -e "SELECT ROW_COUNT()" 2>/dev/null || echo "?")
echo "  terhapus: $DELETED baris"

echo ""
echo "=== 4. Setelah ==="
sudo mysql -N -e "SELECT CONCAT('  wp_postmeta: ', COUNT(*), ' baris / ', ROUND(SUM(data_length+index_length)/1048576),' MB') FROM information_schema.TABLES WHERE table_schema='merahbiru' AND table_name='wp_postmeta'" 2>/dev/null

echo ""
echo "=== 5. Verifikasi: meta_key penting masih utuh ==="
sudo mysql -e "SELECT meta_key, COUNT(*) n FROM merahbiru.wp_postmeta WHERE meta_key IN ('_wp_attached_file','_wp_attachment_metadata','_feedback_email','RBA_rating','post_views_count') GROUP BY meta_key ORDER BY n DESC" 2>&1 | grep -v Warning

echo ""
echo "Backup tersimpan di: $OUT"
