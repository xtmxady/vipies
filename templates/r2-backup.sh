#!/bin/bash
# ============================================================
#  Backup otomatis ke R2 (Cloudflare) - AUTO-SCAN + REPORT DETAIL
#  Auto-detect semua situs di /var/www/
#  - DB      : harian, retensi 5 hari
#  - WordPress: code zip tiap 2 hari (retensi 4), uploads mingguan (retensi 2)
#  - Custom   : zip full tiap 2 hari (retensi 4)
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
UPLOAD_RETENTION_COUNT=2
LOG="/var/log/r2-backup.log"
REPORT="${TMPDIR_REPORT:-/root/backup-report.txt}"
SITES_CONF="/root/r2-sites.conf"

TG_TOKEN="${TG_BOT_TOKEN:-}"
TG_CHAT="${TG_CHAT_ID:-}"

DATE=$(date +%F)
DAY_OF_MONTH=$(date +%d)
TMPDIR="/tmp/r2backup"
mkdir -p "$TMPDIR"

notify() {
  local msg="$1"
  echo "$(date '+%F %T') | $msg" >> "$REPORT"
  curl -s -o /dev/null "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
    -d "chat_id=${TG_CHAT}" --data-urlencode "text=${msg}" 2>/dev/null || true
}

count_files() { # <subdir> <pattern>
  rclone lsf "${R2}/${SITE}/$1" --include "$2" --files-only 2>/dev/null | wc -l
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
  rclone copyto "$TMPDIR/${db}-${DATE}.sql.gz" "${R2}/${SITE}/db/${db}-${DATE}.sql.gz" >> "$LOG" 2>&1
  local n=$(count_files "db" "${db}-*.sql.gz")
  echo "$(date '+%F %T') |    ✅ DB \`${db}-${DATE}.sql.gz\` (ke-$n/5)" >> "$REPORT"
  rm -f "$TMPDIR/${db}-${DATE}.sql.gz"
  rclone delete "${R2}/${SITE}/db" --min-age "$((DB_RETENTION_DAYS+1))d" >> "$LOG" 2>&1 || true
}

# WordPress CODE (tiap 2 hari)
backup_code() {
  local SITE="$1" WEBROOT="$2"
  ( cd "$WEBROOT/wp-content" && zip -rq "$TMPDIR/${SITE}-code-${DATE}.zip" plugins themes mu-plugins -x "*/cache/*" 2>/dev/null || true )
  rclone copyto "$TMPDIR/${SITE}-code-${DATE}.zip" "${R2}/${SITE}/files/${SITE}-code-${DATE}.zip" >> "$LOG" 2>&1
  local n=$(count_files "files" "${SITE}-code-*.zip")
  echo "$(date '+%F %T') |    ✅ Code \`${SITE}-code-${DATE}.zip\` (ke-$n/4)" >> "$REPORT"
  rm -f "$TMPDIR/${SITE}-code-${DATE}.zip"
  rclone delete "${R2}/${SITE}/files" --include "${SITE}-code-*.zip" --min-age "${CODE_RETENTION_DAYS}d" >> "$LOG" 2>&1 || true
}

# WordPress UPLOADS (mingguan)
backup_uploads() {
  local SITE="$1" WEBROOT="$2"
  local ZIP="$TMPDIR/${SITE}-uploads-${DATE}.zip"
  ( cd "$WEBROOT/wp-content" && zip -rq "$ZIP" uploads -x "*/cache/*" 2>/dev/null || true )
  rclone copyto "$ZIP" "${R2}/${SITE}/files/${SITE}-uploads-${DATE}.zip" >> "$LOG" 2>&1
  local n=$(count_files "files" "${SITE}-uploads-*.zip")
  echo "$(date '+%F %T') |    ✅ Uploads \`${SITE}-uploads-${DATE}.zip\` (ke-$n/2)" >> "$REPORT"
  rm -f "$ZIP"
  rclone lsf "${R2}/${SITE}/files" --include "${SITE}-uploads-*.zip" --files-only 2>/dev/null | \
    sort -r | tail -n +$((UPLOAD_RETENTION_COUNT+1)) | while read -r old; do
      rclone deletefile "${R2}/${SITE}/files/$old" >> "$LOG" 2>&1
    done
}

# CUSTOM full zip (tiap 2 hari)
backup_custom() {
  local SITE="$1" WEBROOT="$2"
  local ZIP="$TMPDIR/${SITE}-${DATE}.zip"
  ( cd "$WEBROOT" && zip -rq "$ZIP" . -x "*/node_modules/*" "*/cache/*" 2>/dev/null || true )
  if [ -s "$ZIP" ]; then
    rclone copyto "$ZIP" "${R2}/${SITE}/files/${SITE}-${DATE}.zip" >> "$LOG" 2>&1
    local n=$(count_files "files" "${SITE}-*.zip")
    echo "$(date '+%F %T') |    ✅ Folder \`${SITE}-${DATE}.zip\` (ke-$n/4)" >> "$REPORT"
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
    if (( DAY_OF_MONTH % 2 == 0 )); then
      backup_code "$site" "$webdir"
    else
      echo "$(date '+%F %T') |    code: skip (hari ganjil)" >> "$REPORT"
    fi
    if (( DAY_OF_MONTH % 7 == 0 )); then
      backup_uploads "$site" "$webdir"
    else
      echo "$(date '+%F %T') |    uploads: skip (bukan hari mingguan)" >> "$REPORT"
    fi
  else
    echo "   _(Custom site)_" >> "$REPORT"
    backup_db "$site" "$dbinfo"
    if (( DAY_OF_MONTH % 2 == 0 )); then
      backup_custom "$site" "$webdir"
    else
      echo "$(date '+%F %T') |    folder: skip (hari ganjil)" >> "$REPORT"
    fi
  fi
done

echo "" >> "$REPORT"
echo "✅ **Backup ${DATE} selesai**" >> "$REPORT"

# Kirim report ke Telegram (Kirim dalam beberapa pesan bila panjang)
# Kirim utuh via text file
curl -s -o /dev/null "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
  -d "chat_id=${TG_CHAT}" --data-urlencode "text@${REPORT}" 2>/dev/null || true

echo "===== Done $(date +%T) =====" >> "$LOG"
