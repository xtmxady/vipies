# vipies — Ubuntu Server Setup

> **vipies** = "VPS + IES" — one-shot provisioning script for automated, modular Ubuntu server setup (Nginx, Node, PHP, MySQL, WordPress, backup, monitoring). Open-source — contributions welcome!

Built primarily for **Ubuntu 24.04**. Also works on **22.04 / 20.04** — PHP, Node, and PHP-FPM socket versions are auto-detected. Modular — install everything at once or one module at a time.

## ✨ Features

- **Nginx** — reverse proxy with ready-to-use templates for **WordPress** and **Custom sites** (Node/Express/PHP)
- **Node.js + PM2** — choose your version (default LTS 22), PM2 auto-starts on boot
- **PHP-FPM + OPcache** — all common extensions, OPcache 128MB / 10k files
- **MySQL** — root password setup, create DB + users, change passwords (`vipies-db` helper)
- **WP-CLI + Certbot** — global wp-cli, SSL via snap certbot (no pyOpenSSL conflicts)
- **Backup to R2** — automated DB + file backups to Cloudflare R2, configurable retention
- **Monitoring** — cron every 30 min, Telegram alerts when services go down / high RAM / disk / load
- **Auto-restart** — systemd `Restart=always` for nginx, mysql, php-fpm
- **Auto-fix permissions** — inotify daemon, real-time chown/chmod on WordPress uploads folders
- **Security hardening** — fail2ban (brute-force SSH & wp-login), PHP execution locked in uploads (anti-shell)

## 🚀 Quick Start

```bash
# 1. Clone & enter
git clone https://github.com/xtmxady/vipies
cd vipies

# 2. Configure credentials
cp .env.example .env
nano .env

# 3. Run (interactive menu)
sudo bash setup.sh
```

## 🧪 Fresh Install on a New VPS

Complete flow from a bare Ubuntu install to a production-ready server:

```bash
# ---- 1. SSH into the new VPS as root ----
ssh root@<NEW-VPS-IP>

# ---- 2. Update & install git (minimum requirement) ----
apt update && apt install -y git

# ---- 3. Clone the repo ----
git clone https://github.com/xtmxady/vipies
cd vipies

# ---- 4. Fill in your credentials ----
cp .env.example .env
nano .env
#   → MYSQL_ROOT_PASSWORD=YourStrongPassword123
#   → TG_BOT_TOKEN=123456:ABC...        (from @BotFather)
#   → TG_CHAT_ID=123456789              (target chat/group)
#   → R2_ENABLED=1                       (enable R2 backup)
#   → R2_ACCOUNT_ID / R2_ACCESS_KEY_ID / R2_SECRET_ACCESS_KEY
#   → NODE_VERSION=22, PHP_VERSION=8.3  (optional)

# ---- 5. Run setup ----
sudo bash setup.sh
# Select [1] Full install — all modules run automatically in order
```

### What happens per module:

| Module | What it does |
|--------|-------------|
| 01-system | System update + core packages + UFW (22/80/443) |
| 02-nginx | Nginx install + WP/Custom templates + `vipies-add-site` helper |
| 03-node | Node.js (selectable version) + PM2 + auto-start |
| 04-php | PHP-FPM + OPcache + extensions |
| 05-mysql | MySQL install + root password + `/root/.my.cnf` |
| 06-wpcli | WP-CLI + Certbot (snap) — *slowest module (snap download)* |
| 07-backup | rclone + R2 remote (auto-configured from .env) + backup cron |
| 08-monitoring | Monitor script + cron every 30 min + `/etc/vipies.conf` |
| 09-autorestart | systemd Restart=always (nginx/mysql/php) |
| 10-permission | inotify daemon auto chown/chmod on uploads |

### Verify after setup

```bash
systemctl status nginx mysql php*-fpm    # all active
pm2 status                                # PM2 running
vipies-db create testdb testuser testpass # test MySQL helper
vipies-add-site example.com wp            # test site helper
vipies-monitor                            # test Telegram notification
# Check Telegram: you should see "MONITOR VIPIES — all healthy"
```

## 📦 Install Options

Interactive `setup.sh` menu:

| Option | Module | Description |
|--------|--------|-------------|
| 1 | All | Full install — every module |
| 2 | 01-system | System update + dependencies + firewall |
| 3 | 02-nginx | Nginx + WP/Custom templates |
| 4 | 03-node | Node.js + PM2 |
| 5 | 04-php | PHP-FPM + OPcache |
| 6 | 05-mysql | MySQL + DB management |
| 7 | 06-wpcli | WP-CLI + Certbot |
| 8 | 07-backup | R2 Backup + cron |
| 9 | 08-monitoring | Monitoring + Telegram alerts |
| 10 | 09-autorestart | Auto-restart services |
| 11 | 10-permission | Auto-fix permissions |
| 12 | 11-newsite | WordPress site creator helper |
| 13 | 12-hardening | Security hardening (fail2ban + upload lock) |

## 🛠️ CLI Helpers (available after install)

```bash
# Add a new website (WordPress or custom)
vipies-add-site example.com wp              # WordPress
vipies-add-site api.example.com custom 4000 # Custom/Node on port 4000

# Manage MySQL databases
vipies-db create mydb myuser mypass         # create DB + user
vipies-db drop mydb                          # drop database
vipies-db pass myuser newpass                # change user password
vipies-db rootpass newrootpass               # change root password

# Manual monitoring check
vipies-monitor

# Create a full WordPress site in one command (Nginx + DB + WP + permissions)
vipies-new-site example.com
# Optional: specify your own DB/user/pass
vipies-new-site example.com wpmydb myuser mypass
```

## 📄 Configuration (.env)

| Variable | Description |
|----------|-------------|
| `MYSQL_ROOT_PASSWORD` | MySQL root password |
| `TG_BOT_TOKEN` | Telegram bot token (from @BotFather) |
| `TG_CHAT_ID` | Target chat/group ID for notifications |
| `NODE_VERSION` | (optional) Node.js version, default 22 |
| `PHP_VERSION` | (optional) PHP version, default 8.3 |
| `R2_ENABLED` | Set to `1` to enable R2 backup |
| `R2_REMOTE_NAME` | Rclone remote name (default `r2`) |
| `R2_BUCKET` | R2 bucket name (default `hermes`) |
| `R2_ACCOUNT_ID` | Cloudflare R2 Account ID (auto-creates rclone remote) |
| `R2_ACCESS_KEY_ID` | R2 API Token Access Key ID |
| `R2_SECRET_ACCESS_KEY` | R2 API Token Secret Access Key |

> ⚠️ **Do NOT commit `.env`** — it's already in `.gitignore`. Credentials stay safe on your server.
> Other credentials (for cron-based scripts) are automatically copied to `/etc/vipies.conf` (chmod 600) during setup.

## 🔐 Security

- No hardcoded credentials — everything goes through `.env` (gitignored) → `/etc/vipies.conf` (chmod 600)
- MySQL root stored in `/root/.my.cnf` (chmod 600)
- Certbot via snap (avoids pyOpenSSL conflict)
- UFW enabled automatically (22/80/443)
- fail2ban protects SSH & wp-login from brute-force
- PHP execution locked in WordPress uploads directories

## 🤝 Contributing

This repo is open-source and built for the community. Feel free to:
- Report bugs via [Issues](https://github.com/xtmxady/vipies/issues)
- Submit fixes via Pull Request
- Add modules as needed

### Repo Structure
```
vipies/
├── setup.sh              ← entry point (interactive menu)
├── .env.example          ← example configuration
├── modules/              ← modules (01-system .. 12-hardening, lib.sh)
├── templates/
│   └── r2-backup.sh      ← generic R2 backup template (for new VPS)
└── README.md
```

## 📝 License

MIT — free to use and modify.
