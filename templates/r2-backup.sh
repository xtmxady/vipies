#!/bin/bash
# ============================================================
#  Backup otomatis ke R2 (Cloudflare) - AUTO-SCAN + REPORT DETAIL
#  Auto-detect semua situs di /var/www/
#  - DB        : harian, retensi 5 hari
#  - WordPress : zip PENUH wp-content (uploads+plugins+themes+mu-plugins,
#                minus cache/updraft/wflogs/sampah) tiap 2 hari, retensi 4
#  - Custom    : zip full tiap 2 hari (retensi 4)
#  DB creds dibaca dari /var/www/<site>/server/.env bila ada, fallback ke r2-sites.conf
#  Notif Telegram detail via curl (0 token Hermes)
# ============================================================
set -e

# ---------- KONFIGURASI ----------
# Baca credentials dari /etc/vipies.conf (ditulis setup.sh dari .env)
[ -f /etc/vipies.conf ] && source /etc/vipies.conf
R2_REMOTE="${R2_REMOTE_NAME:-r2}:${R2_BUCKET:-hermes}"
R2="$R2_REMOTE"
DB_RETENTION_DAYS=5
CODE_RETENTION_DAYS=8
LOG="/var/log/r2-backup.log"
REPORT="${TMPDIR_REPORT:-/root/backup-report.txt}"
SITES_CONF="/root/r2-sites.conf"

TG_TOKEN="${TG_BOT_TOKEN:-}"
TG_CHAT="${TG_CHAT_ID:-}"

DATE=$(date +%F)
DAY_OF_MONTH=$(date +%-d)
TMPDIR="/tmp/r2backup"
mkdir -p "$TMPDIR"

# PENTING: bersihkan temp kalau script mati/dibatalkan di tengah jalan.
# Tanpa trap ini, zip 6 GB yatim tinggal di /tmp (pernah terjadi 2026-09-20,
# disk naik ke 88% karena file tidak terhapus setelah proses mati).
# Pola file mengandung tanggal hari ini, jadi zip dari run lain tidak ikut terhapus.
cleanup_tmp() {
  find "$TMPDIR" -maxdepth 1 -type f \( -name "*-${DATE}.zip" -o -name "*-${DATE}.sql.gz" \) -delete 2>/dev/null || true
}
trap cleanup_tmp EXIT INT TERM

notify() {
  local msg="$1"
  echo "$(date '+%F %T') | $msg" >> "$REPORT"
  curl -s -o /dev/null "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
    -d "chat_id=${TG_CHAT}" --data-urlencode "text=${msg}" 2>/dev/null || true
}

count_files() { # <subdir> <pattern>
  rclone lsf "${R2}/${SITE}/$1" --include "$2" --files-only 2>/dev/null | wc -l
}

# Upload satu file. Return 1 kalau GAGAL (jangan sampai set -e membatalkan
# seluruh backup karena satu situs gagal — situs berikutnya harus tetap dicoba).
upload() { # <local> <remote>
  if rclone copyto "$1" "$2" >> "$LOG" 2>&1; then
    return 0
  fi
  echo "===== $(date '+%F %T') UPLOAD GAGAL: $1 -> $2 =====" >> "$LOG"
  return 1
}

# Resolve DB creds: prioritas .env di /var/www/<site>/server/, lalu conf
resolve_db() {
  local site="$1"
  local ENVFILE="/var/www/${site}/server/.env"
  if [ -f "$ENVFILE" ] && grep -q '^DB_NAME=' "$ENVFILE" 2>/dev/null; then
    local dn du dp
    dn=$(grep '^DB_NAME=' "$ENVFILE" | cut -d= -f2)
    du=$(grep '^DB_USER=' "$ENVFILE" | cut -d= -f2 | tr -d '"')
    dp=$(grep -E '^DB_PASS(WORD)?=' "$ENVFILE" | head -1 | cut -d= -f2 | tr -d '"')
    echo "$dn|$du|$dp"
  else
    grep "^${site}|" "$SITES_CONF" 2>/dev/null | head -1 | cut -d'|' -f2- || true
  fi
}

# ---------- BACKUP DB ----------
backup_db() {
  local SITE="$1"; shift
  local dbinfo="$1"
  local db du dp
  if [ -z "$dbinfo" ] || [ "$dbinfo" = "|" ]; then
    echo "$(date '+%F %T') |    db: skips (no DB config)" >> "$REPORT"
    return
  fi
  db="${dbinfo%%|*}"; rest="${dbinfo#*|}"
  du="${rest%%|*}"; dp="${rest#*|}"
  if [ -z "$db" ] || [ -z "$du" ]; then
    echo "$(date '+%F %T') |    db: skipped (no DB name/user)" >> "$REPORT"
    return
  fi
  mysqldump --single-transaction -u "$du" -p"$dp" "$db" 2>/dev/null \
    | gzip > "$TMPDIR/${db}-${DATE}.sql.gz"
  if [ ! -s "$TMPDIR/${db}-${DATE}.sql.gz" ]; then
    echo "$(date '+%F %T') |    db: ⚠️ dump gagal/empty" >> "$REPORT"
    rm -f "$TMPDIR/${db}-${DATE}.sql.gz"
    return
  fi
  if upload "$TMPDIR/${db}-${DATE}.sql.gz" "${R2}/${SITE}/db/${db}-${DATE}.sql.gz"; then
    local n=$(count_files "db" "${db}-*.sql.gz")
    echo "$(date '+%F %T') |    ✅ DB \`${db}-${DATE}.sql.gz\` (ke-$n/5)" >> "$REPORT"
  else
    echo "$(date '+%F %T') |    ❌ DB \`${db}-${DATE}.sql.gz\` GAGAL upload" >> "$REPORT"
  fi
  rm -f "$TMPDIR/${db}-${DATE}.sql.gz"
  rclone delete "${R2}/${SITE}/db" --min-age "$((DB_RETENTION_DAYS+1))d" >> "$LOG" 2>&1 || true
}

# WordPress WP-CONTENT penuh (uploads+plugins+themes+mu-plugins, minus sampah) — tiap 2 hari
backup_wpcontent() {
  local SITE="$1" WEBROOT="$2"
  local ZIP="$TMPDIR/${SITE}-wpcontent-${DATE}.zip"
  ( cd "$WEBROOT/wp-content" && zip -rq "$ZIP" . \
      -x "cache/*" "w3tc-config/*" "upgrade/*" "upgrade-temp-backup/*" \
         "maintenance/*" "wflogs/*" "jetpack-waf/*" "imunify-security/*" \
         "updraft/*" "speedycache-config/*" "advanced-cache.php" "maintenance.php" "mysqlmon.sh" 2>/dev/null || true )
  if [ -s "$ZIP" ]; then
    if upload "$ZIP" "${R2}/${SITE}/files/${SITE}-wpcontent-${DATE}.zip"; then
      local n=$(count_files "files" "${SITE}-wpcontent-*.zip")
      echo "$(date '+%F %T') |    ✅ WPContent \`${SITE}-wpcontent-${DATE}.zip\` (ke-$n/4)" >> "$REPORT"
    else
      echo "$(date '+%F %T') |    ❌ WPContent \`${SITE}-wpcontent-${DATE}.zip\` GAGAL upload" >> "$REPORT"
    fi
    rm -f "$ZIP"
    rclone delete "${R2}/${SITE}/files" --include "${SITE}-wpcontent-*.zip" --min-age "${CODE_RETENTION_DAYS}d" >> "$LOG" 2>&1 || true
  else
    echo "$(date '+%F %T') |    ⚠️ wp-content zip kosong/gagal" >> "$REPORT"
    rm -f "$ZIP"
  fi
}

# CUSTOM full zip (tiap 2 hari)
backup_custom() {
  local SITE="$1" WEBROOT="$2"
  local ZIP="$TMPDIR/${SITE}-${DATE}.zip"
  ( cd "$WEBROOT" && zip -rq "$ZIP" . -x "*/node_modules/*" "*/cache/*" 2>/dev/null || true )
  if [ -s "$ZIP" ]; then
    if upload "$ZIP" "${R2}/${SITE}/files/${SITE}-${DATE}.zip"; then
      local n=$(count_files "files" "${SITE}-*.zip")
      echo "$(date '+%F %T') |    ✅ Folder \`${SITE}-${DATE}.zip\` (ke-$n/4)" >> "$REPORT"
    else
      echo "$(date '+%F %T') |    ❌ Folder \`${SITE}-${DATE}.zip\` GAGAL upload" >> "$REPORT"
    fi
    rclone delete "${R2}/${SITE}/files" --include "${SITE}-*.zip" --min-age "${CODE_RETENTION_DAYS}d" >> "$LOG" 2>&1 || true
  else
    echo "$(date '+%F %T') |    ⚠️ folder zip kosong/gagal" >> "$REPORT"
  fi
  rm -f "$ZIP"
}

# ============ MAIN ============
echo "===== Backup $DATE $(date +%T) =====" >> "$LOG"
: > "$REPORT"
echo "🛡️ **BACKUP ${DATE}**" >> "$REPORT"

for webdir in /var/www/*/; do
  site=$(basename "$webdir"); site=${site%/}
  [ "$site" = "adminer" ] && continue
  [ "$site" = "html" ] && continue
  echo "" >> "$REPORT"
  echo "**📁 ${site}**" >> "$REPORT"

  dbinfo=$(resolve_db "$site")

  if [ -f "$webdir/wp-config.php" ] || [ -d "$webdir/wp-content" ]; then
    echo "   _(WordPress)_" >> "$REPORT"
    backup_db "$site" "$dbinfo"
    if (( 10#$DAY_OF_MONTH % 2 == 0 )); then
      backup_wpcontent "$site" "$webdir"
    else
      echo "$(date '+%F %T') |    wp-content: skip (hari ganjil)" >> "$REPORT"
    fi
  else
    echo "   _(Custom site)_" >> "$REPORT"
    backup_db "$site" "$dbinfo"
    if (( 10#$DAY_OF_MONTH % 2 == 0 )); then
      backup_custom "$site" "$webdir"
    else
      echo "$(date '+%F %T') |    folder: skip (hari ganjil)" >> "$REPORT"
    fi
  fi
done

echo "" >> "$REPORT"
if grep -q '❌' "$REPORT"; then
  echo "⚠️ **Backup ${DATE} selesai DENGAN GAGAL**" >> "$REPORT"
else
  echo "✅ **Backup ${DATE} selesai**" >> "$REPORT"
fi

# Kirim report ke Telegram. Telegram limit 4096 karakter per pesan — potong kalau perlu
# (report 16 situs sudah ~2900 char, akan lewat kalau site bertambah).
send_report() { # <file> <offset> <len>
  curl -s -o /dev/null -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
    -d "chat_id=${TG_CHAT}" --data-urlencode "text=$(head -c "$3" "$1" | tail -c +"$2")" 2>/dev/null || true
}
if [ "$(wc -m < "$REPORT")" -gt 4000 ]; then
  send_report "$REPORT" 1 3900
  send_report "$REPORT" 3901 2000
else
  send_report "$REPORT" 1 4096
fi

echo "===== Done $(date +%T) =====" >> "$LOG"
