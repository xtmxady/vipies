# vipies — Setup Server Ubuntu

> **vipies** = "VPS + IES" — skrip provisioning satu-perintah untuk setup server Ubuntu yang otomatis & modular (Nginx, Node, PHP, MySQL, WordPress, backup, monitoring). Open-source — kontribusi dipersilakan!

> **Bahasa:** [English](README.md) | [Bahasa Indonesia](README.id.md)

Dibuat khusus untuk **Ubuntu 24.04**. Juga jalan di **22.04 / 20.04** — versi PHP, Node, dan socket PHP-FPM terdeteksi otomatis. Modular — install semua sekaligus atau modul per modul.

## ✨ Fitur

- **Nginx** — reverse proxy dengan template siap pakai untuk **WordPress** dan **Custom site** (Node/Express/PHP)
- **Node.js + PM2** — pilih versi (default LTS 22), PM2 auto-start saat boot
- **PHP-FPM + OPcache** — ekstensi lengkap, OPcache 128MB / 10k file
- **MySQL** — setup password root, buat DB + user, ganti password (`vipies-db` helper)
- **WP-CLI + Certbot** — wp-cli global, SSL via snap certbot (tanpa konflik pyOpenSSL)
- **Backup ke R2** — backup DB + file otomatis ke Cloudflare R2, retensi bisa diatur
- **Monitoring** — cron tiap 30 menit, notifikasi Telegram saat service down / RAM / disk / load tinggi
- **Auto-restart** — systemd `Restart=always` untuk nginx, mysql, php-fpm
- **Auto-fix permission** — daemon inotify, chown/chmod real-time di folder uploads WordPress
- **Security hardening** — fail2ban (brute-force SSH & wp-login), eksekusi PHP dikunci di uploads (anti-shell)
- **Migrasi VPS** — modul 13: install Hermes Agent + 9router + rclone + restore seluruh config server dari R2 (lihat [Migrasi VPS](#-migrasi-vps))

## 🚀 Quick Start

```bash
# 1. Clone & masuk
git clone https://github.com/xtmxady/vipies
cd vipies

# 2. Konfigurasi kredensial
cp .env.example .env
nano .env

# 3. Jalankan (menu interaktif)
sudo bash setup.sh
```

## 🧪 Fresh Install di VPS Baru

Alur lengkap dari Ubuntu polos sampai server production-ready:

```bash
# ---- 1. SSH ke VPS baru sebagai root ----
ssh root@<IP-VPS-BARU>

# ---- 2. Update & install git (syarat minimum) ----
apt update && apt install -y git

# ---- 3. Clone repo ----
git clone https://github.com/xtmxady/vipies
cd vipies

# ---- 4. Isi kredensial ----
cp .env.example .env
nano .env
#   → MYSQL_ROOT_PASSWORD=PasswordKuat123
#   → TG_BOT_TOKEN=123456:ABC...        (dari @BotFather)
#   → TG_CHAT_ID=123456789              (chat/group tujuan)
#   → R2_ENABLED=1                       (aktifkan backup R2)
#   → R2_ACCOUNT_ID / R2_ACCESS_KEY_ID / R2_SECRET_ACCESS_KEY
#   → NODE_VERSION=22, PHP_VERSION=8.3  (opsional)

# ---- 5. Jalankan setup ----
sudo bash setup.sh
# Pilih [1] Full install — semua modul jalan otomatis berurutan
```

### Yang dilakukan tiap modul:

| Modul | Fungsi |
|-------|--------|
| 01-system | Update sistem + paket inti + UFW (22/80/443) |
| 02-nginx | Install Nginx + template WP/Custom + helper `vipies-add-site` |
| 03-node | Node.js (versi bisa dipilih) + PM2 + auto-start |
| 04-php | PHP-FPM + OPcache + ekstensi |
| 05-mysql | Install MySQL + password root + `/root/.my.cnf` |
| 06-wpcli | WP-CLI + Certbot (snap) — *modul paling lambat (download snap)* |
| 07-backup | rclone + remote R2 (auto-konfigurasi dari .env) + cron backup |
| 08-monitoring | Skrip monitor + cron tiap 30 menit + `/etc/vipies.conf` |
| 09-autorestart | systemd Restart=always (nginx/mysql/php) |
| 10-permission | Daemon inotify auto chown/chmod di uploads |
| 11-newsite | Helper pembuat situs WordPress sekali jalan |
| 12-hardening | fail2ban + kunci eksekusi PHP di uploads (anti-shell) |
| 13-migrate | Install Hermes + 9router + restore config server dari R2 |

### Verifikasi setelah setup

```bash
systemctl status nginx mysql php*-fpm    # semua aktif
pm2 status                                # PM2 berjalan
vipies-db create testdb testuser testpass # tes helper MySQL
vipies-add-site example.com wp            # tes helper situs
vipies-monitor                            # tes notifikasi Telegram
# Cek Telegram: harus muncul "MONITOR VIPIES — all healthy"
```

## 📦 Pilihan Install

Menu interaktif `setup.sh`:

| Opsi | Modul | Deskripsi |
|------|-------|-----------|
| 1 | Semua | Full install — semua modul |
| 2 | 01-system | Update sistem + dependensi + firewall |
| 3 | 02-nginx | Nginx + template WP/Custom |
| 4 | 03-node | Node.js + PM2 |
| 5 | 04-php | PHP-FPM + OPcache |
| 6 | 05-mysql | MySQL + manajemen DB |
| 7 | 06-wpcli | WP-CLI + Certbot |
| 8 | 07-backup | Backup R2 + cron |
| 9 | 08-monitoring | Monitoring + alert Telegram |
| 10 | 09-autorestart | Auto-restart service |
| 11 | 10-permission | Auto-fix permission |
| 12 | 11-newsite | Helper pembuat situs WordPress |
| 13 | 12-hardening | Security hardening (fail2ban + lock uploads) |
| 14 | 13-migrate | Migrasi VPS (Hermes + 9router + restore config) |

## 🔁 Migrasi VPS

Pindah seluruh server (situs, config, Hermes, 9router, backup) ke VPS baru dengan sekali jalan:

```bash
# Di VPS LAMA (sudah jalan vipies) — backup config otomatis tiap hari (cron 03:00)
# → zip config terupload ke rclone:R2 → bucket hermes/server-config/

# Di VPS BARU — setelah modul 1-12 selesai:
sudo bash setup.sh        # pilih [14] Migrasi VPS
# atau manual:
bash /root/migrate-restore.sh   # download zip config terbaru dari R2, extract ke path asli otomatis
```

Yang di-restore otomatis: **Hermes** (`~/.hermes/` — config, memories, skills, riwayat chat, state.db), **9router** (`~/.9router/`), **Nginx**, **LetsEncrypt SSL**, **PM2 dump**, **crontab**, **fail2ban**, **.env situs**, **rclone.conf**, **MySQL root** (`~/.my.cnf`).

> ⚠️ Hermes diinstall via installer resmi (`curl ... install.sh | bash`) — **bukan** npm package. 9router & PM2 via `npm i -g`.

## 🛠️ CLI Helpers (tersedia setelah install)

```bash
# Tambah situs baru (WordPress atau custom)
vipies-add-site example.com wp              # WordPress
vipies-add-site api.example.com custom 4000 # Custom/Node di port 4000

# Kelola database MySQL
vipies-db create mydb myuser mypass         # buat DB + user
vipies-db drop mydb                          # hapus database
vipies-db pass myuser newpass                # ganti password user
vipies-db rootpass newrootpass               # ganti password root

# Cek monitoring manual
vipies-monitor

# Buat situs WordPress lengkap satu perintah (Nginx + DB + WP + permission)
vipies-new-site example.com
# Opsional: tentukan DB/user/pass sendiri
vipies-new-site example.com wpmydb myuser mypass
```

## 📄 Konfigurasi (.env)

| Variabel | Deskripsi |
|----------|-----------|
| `MYSQL_ROOT_PASSWORD` | Password root MySQL |
| `TG_BOT_TOKEN` | Token bot Telegram (dari @BotFather) |
| `TG_CHAT_ID` | Chat/group tujuan notifikasi |
| `NODE_VERSION` | (opsional) Versi Node.js, default 22 |
| `PHP_VERSION` | (opsional) Versi PHP, default 8.3 |
| `R2_ENABLED` | Set `1` untuk mengaktifkan backup R2 |
| `R2_REMOTE_NAME` | Nama remote rclone (default `r2`) |
| `R2_BUCKET` | Nama bucket R2 (default `hermes`) |
| `R2_ACCOUNT_ID` | Cloudflare R2 Account ID (auto-buat remote rclone) |
| `R2_ACCESS_KEY_ID` | R2 API Token Access Key ID |
| `R2_SECRET_ACCESS_KEY` | R2 API Token Secret Access Key |

> ⚠️ **JANGAN commit `.env`** — sudah ada di `.gitignore`. Kredensial aman di server.
> Kredensial lain (untuk script cron) otomatis disalin ke `/etc/vipies.conf` (chmod 600) saat setup.

## 🔐 Keamanan

- Tanpa kredensial hardcoded — semua lewat `.env` (gitignored) → `/etc/vipies.conf` (chmod 600)
- Root MySQL di `/root/.my.cnf` (chmod 600)
- Certbot via snap (hindari konflik pyOpenSSL)
- UFW aktif otomatis (22/80/443)
- fail2ban melindungi SSH & wp-login dari brute-force
- Eksekusi PHP dikunci di folder uploads WordPress

## 🤝 Kontribusi

Repo ini open-source dan dibangun untuk komunitas. Silakan:
- Laporkan bug lewat [Issues](https://github.com/xtmxady/vipies/issues)
- Kirim perbaikan lewat Pull Request
- Tambah modul sesuai kebutuhan

### Struktur Repo
```
vipies/
├── setup.sh              ← entry point (menu interaktif)
├── .env.example          ← contoh konfigurasi
├── modules/              ← modul (01-system .. 13-migrate, lib.sh)
├── templates/
│   └── r2-backup.sh      ← template backup R2 generik (untuk VPS baru)
└── README.md
```

## 📝 Lisensi

MIT — bebas dipakai dan dimodifikasi.