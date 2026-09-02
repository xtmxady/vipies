# vipies — Ubuntu Server Setup

> **vipies** = "VPS + IES" — one-shot provisioning script untuk setup server Ubuntu (Nginx, Node, PHP, MySQL, WP, backup, monitoring) otomatis & modular. Open-source, silakan kontribusi!

Dirancang untuk **Ubuntu 24.04** (target utama). Juga bekerja di **22.04 / 20.04** — versi PHP, Node, dan socket PHP-FPM terdeteksi otomatis. Modular — bisa install semua sekaligus atau per modul.

## ✨ Fitur

- **Nginx** — reverse proxy + template siap pakai untuk **WordPress** & **Custom site** (Node/Express/PHP)
- **Node.js + PM2** — versi bisa dipilih (default LTS 22), PM2 auto-start saat boot
- **PHP-FPM + OPcache** — extensions lengkap, OPcache 128MB/10k files
- **MySQL** — root password, buat DB + user, ubah password (via `vipies-db`)
- **WP-CLI + Certbot** — wp-cli global, SSL via snap certbot (aman, tanpa konflik pyOpenSSL)
- **Backup R2** — otomatis DB + file ke Cloudflare R2, retensi otomatis
- **Monitoring** — cron tiap 30 menit, notif Telegram bila ada layanan down / RAM / disk / load
- **Auto-restart** — systemd Restart=always untuk nginx, mysql, php-fpm
- **Auto-fix permission** — daemon inotify, real-time chown/chmod folder WordPress uploads

## 🚀 Quick Start

```bash
# 1. Clone & masuk
git clone https://github.com/xtmxady/vipies
cd vipies

# 2. Siapkan konfigurasi (isi credentials)
cp .env.example .env
nano .env

# 3. Jalankan (menu interaktif)
sudo bash setup.sh
```

## 🧪 Fresh Install / Test di VPS Baru

Flow lengkap dari Ubuntu polos sampai server siap:

```bash
# ---- 1. Login VPS baru sebagai root ----
ssh root@<IP-VPS-BARU>

# ---- 2. Update & install git (minimal, untuk clone) ----
apt update && apt install -y git

# ---- 3. Clone repo (WAJIB public, atau pakai PAT) ----
git clone https://github.com/xtmxady/vipies
cd vipies

# ---- 4. Isi credentials ----
cp .env.example .env
nano .env
#   → MYSQL_ROOT_PASSWORD=IsiPasswordKuat123
#   → TG_BOT_TOKEN=123456:ABC...       (dari @BotFather)
#   → TG_CHAT_ID=123456789            (chat/group tujuan)
#   → R2_ENABLED=1                     (kalau mau backup R2)
#   → R2_ACCOUNT_ID / R2_ACCESS_KEY_ID / R2_SECRET_ACCESS_KEY
#   → NODE_VERSION=22, PHP_VERSION=8.3 (opsional)

# ---- 5. Jalankan setup ----
sudo bash setup.sh
# Pilih [1] Full install — semua modul otomatis berurutan
```

### Yang terjadi otomatis per modul:
| Modul | Output di layar |
|-------|-----------------|
| 01-system | update + deps + UFW (22/80/443) |
| 02-nginx | Nginx + template + helper `vipies-add-site` |
| 03-node | Node 22 + PM2 + auto-start |
| 04-php | PHP 8.3-FPM + OPcache + extensions |
| 05-mysql | MySQL + set root pass + buat `/root/.my.cnf` |
| 06-wpcli | WP-CLI + Certbot (snap) — *paling lama (download snap)* |
| 07-backup | rclone + remote R2 (auto dari .env) + cron backup |
| 08-monitoring | monitor script + cron 30 mnt + `/etc/vipies.conf` |
| 09-autorestart | systemd Restart=always (nginx/mysql/php) |
| 10-permission | daemon inotify auto chown/chmod uploads |

### Verifikasi setelah selesai
```bash
systemctl status nginx mysql php*-fpm   # semua active
pm2 status                              # PM2 jalan
vipies-db create testdb testuser testpass # test helper MySQL
vipies-add-site example.com wp            # test helper site
vipies-monitor                            # test notif Telegram (cek HP)
# Cek Telegram: harus ada notif "MONITOR VIPIES — semua normal"
```

## 📦 Pilihan Install

Menu interaktif `setup.sh`:

| Pilihan | Modul | Fungsi |
|---------|-------|--------|
| 1 | Semua | Full install semua modul |
| 2 | 01-system | Update + dependensi + firewall |
| 3 | 02-nginx | Nginx + template WP/Custom |
| 4 | 03-node | Node.js + PM2 |
| 5 | 04-php | PHP-FPM + OPcache |
| 6 | 05-mysql | MySQL + DB + ganti pass |
| 7 | 06-wpcli | WP-CLI + Certbot |
| 8 | 07-backup | Backup R2 + cron |
| 9 | 08-monitoring | Monitoring + Telegram |
| 10 | 09-autorestart | Auto-restart service |
| 11 | 10-permission | Auto-fix permission |
| 12 | 11-newsite | Helper new-site (bikin WP cepat) |

## 🛠️ Helper CLI setelah install

```bash
# Tambah website baru (WordPress atau custom)
vipies-add-site example.com wp          # WordPress
vipies-add-site api.example.com custom 4000   # Custom/Node port 4000

# Kelola database MySQL
vipies-db create mydb myuser mypass     # buat DB + user
vipies-db drop mydb                      # hapus DB
vipies-db pass myuser newpass            # ganti pass user
vipies-db rootpass newrootpass           # ganti pass root

# Monitoring manual
vipies-monitor

# Buat situs WordPress baru lengkap (Nginx + DB + WP install + permission)
vipies-new-site example.com
# Optional: tentukan DB/user/pass sendiri
vipies-new-site example.com wpmydb myuser mypass
```

## 📄 Konfigurasi (.env)

| Variabel | Deskripsi |
|----------|-----------|
| `MYSQL_ROOT_PASSWORD` | Password root MySQL |
| `TG_BOT_TOKEN` | Bot token Telegram (dari @BotFather) |
| `TG_CHAT_ID` | Chat/group ID tujuan notif |
| `NODE_VERSION` | (optional) versi Node, default 22 |
| `PHP_VERSION` | (optional) versi PHP, default 8.3 |
| `R2_ENABLED` | `1` untuk aktifkan backup R2 |
| `R2_REMOTE_NAME` | Nama remote rclone (default `r2`) |
| `R2_BUCKET` | Nama bucket R2 (default `hermes`) |
| `R2_ACCOUNT_ID` | Account ID Cloudflare R2 (untuk auto-create remote) |
| `R2_ACCESS_KEY_ID` | Access Key ID dari R2 API Token |
| `R2_SECRET_ACCESS_KEY` | Secret Access Key dari R2 API Token |

> ⚠️ **JANGAN commit .env** — sudah di-gitignore. Credentials tetap aman di server.
> Credentials lain (untuk script yang jalan via cron) otomatis disalin ke `/etc/vipies.conf` (chmod 600) saat setup.

## 🔐 Keamanan

- Tidak ada credentials hardcode di script — semua via `.env` (gitignored) → `/etc/vipies.conf` (chmod 600)
- MySQL root disimpan di `/root/.my.cnf` (chmod 600)
- Certbot via snap (fixed pyOpenSSL conflict)
- UFW aktif otomatis (22/80/443)

## 🤝 Kontribusi

Repo ini open-source & dibuat untuk komunitas. Silakan:
- Report bug via [Issues](https://github.com/xtmxady/vipies/issues)
- Kirim perbaikan via Pull Request
- Tambah modul sesuai kebutuhan

### Struktur repo
```
vipies/
├── setup.sh              ← entry point (menu)
├── .env.example          ← contoh konfigurasi
├── modules/              ← modul-modul (01-system .. 10-permission, lib.sh)
├── templates/
│   └── r2-backup.sh      ← template backup R2 (generic, untuk VPS baru)
└── README.md             ← panduan ini
```

## 📝 Lisensi

MIT — bebas pakai & modifikasi.
