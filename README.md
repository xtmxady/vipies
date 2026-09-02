# vipies — Ubuntu Server Setup

> **vipies** = "VPS + IES" — one-shot provisioning script untuk setup server Ubuntu (Nginx, Node, PHP, MySQL, WP, backup, monitoring) otomatis & modular. Open-source, silakan kontribusi!

Dirancang untuk **Ubuntu 24.04**. Modular — bisa install semua sekaligus atau per modul.

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
```

## 📄 Konfigurasi (.env)

| Variabel | Deskripsi |
|----------|-----------|
| `MYSQL_ROOT_PASSWORD` | Password root MySQL |
| `TG_BOT_TOKEN` | Bot token Telegram (dari @BotFather) |
| `TG_CHAT_ID` | Chat/group ID tujuan notif |
| `R2_ENABLED` | `1` untuk aktifkan backup R2 |
| `R2_REMOTE_NAME` | Nama remote rclone (default `r2`) |
| `R2_BUCKET` | Nama bucket R2 |
| `NODE_VERSION` | (optional) versi Node |
| `PHP_VERSION` | (optional) versi PHP |

> ⚠️ **JANGAN commit .env** — sudah di-gitignore. Credentials tetap aman di server.

## 🔐 Keamanan

- Tidak ada credentials hardcode di script — semua via `.env` (gitignored)
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
└── templates/            ← template (opsional, untuk VPS baru)
```

## 📝 Lisensi

MIT — bebas pakai & modifikasi.
