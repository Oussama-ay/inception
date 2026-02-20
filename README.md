*This project has been created as part of the 42 curriculum by oayyoub.*

# Inception

## Description

This project sets up a small infrastructure composed of three services (NGINX, WordPress, MariaDB) running in separate Docker containers, orchestrated with Docker Compose. All containers are built from Debian Bullseye using custom Dockerfiles — no pre-made images are used.

---

## Project Structure

```
inception/
├── Makefile
├── secrets/
│   ├── credentials.txt          # WP admin password
│   ├── db_password.txt          # MariaDB user password
│   └── db_root_password.txt     # MariaDB root password
└── srcs/
    ├── .env                     # Environment variables (no passwords)
    ├── docker-compose.yml       # Orchestrates all 3 services
    └── requirements/
        ├── mariadb/
        │   ├── Dockerfile
        │   ├── .dockerignore
        │   ├── conf/50-server.cnf
        │   └── tools/mariadb_start.sh
        ├── nginx/
        │   ├── Dockerfile
        │   ├── .dockerignore
        │   ├── conf/default
        │   └── tools/nginx_start.sh
        └── wordpress/
            ├── Dockerfile
            ├── .dockerignore
            ├── conf/www.conf
            └── tools/
                ├── wordpress_start.sh
                └── wp-config.php
```

---

## How the 3 Containers Work Together

```
Client (browser)
    │
    │ HTTPS (port 443, TLSv1.2/1.3)
    ▼
┌─────────┐
│  NGINX  │  ← Only entry point, serves static files
└────┬────┘
     │ Passes .php requests to port 9000
     ▼
┌───────────┐
│ WordPress │  ← PHP-FPM processes PHP, generates pages
│ + php-fpm │
└────┬──────┘
     │ Reads/writes data on port 3306
     ▼
┌──────────┐
│ MariaDB  │  ← Stores all WordPress data
└──────────┘
```

| Container | Role | Listens on | Talks to |
|-----------|------|-----------|----------|
| **nginx** | Reverse proxy + TLS | Port 443 (exposed to host) | wordpress:9000 |
| **wordpress** | PHP-FPM (processes PHP) | Port 9000 (internal) | mariadb:3306 |
| **mariadb** | Database | Port 3306 (internal) | Nothing |

---

## Docker Network

All 3 containers are on the same **bridge network** called `app-network`. They find each other by **service name** (e.g., WordPress connects to MariaDB using hostname `mariadb`). No ports are exposed except **443 on nginx**.

---

## Volumes

| Volume | Mounted at | Purpose |
|--------|-----------|---------|
| `wp` | `/var/www/html` (nginx + wordpress) | WordPress files (themes, plugins, uploads) |
| `db` | `/var/lib/mysql` (mariadb) | Database files |

Both are stored on the host at `/home/oayyoub/data/`:
- `/home/oayyoub/data/wordpress` → wp volume
- `/home/oayyoub/data/mariadb` → db volume

Data **persists** even if containers are destroyed. Only `make fclean` deletes it.

---

## Secrets vs Environment Variables

| Type | Used for | Example |
|------|----------|---------|
| **Secrets** (files in `secrets/`) | Passwords, sensitive data | `db_password.txt` |
| **Env variables** (`.env` file) | Non-sensitive config | `DOMAIN_NAME=oayyoub.42.fr` |

Secrets are mounted at `/run/secrets/<name>` inside containers. Scripts read them with `cat /run/secrets/db_password`.

Environment variables can leak (logs, `docker inspect`). Secret files are only readable inside the container.

---

## What Each File Does

### Makefile
```
make        → Creates data dirs + builds & starts containers
make down   → Stops containers
make clean  → Stops + removes all docker images
make fclean → Stops + removes everything + deletes data
make re     → fclean + all (full rebuild)
```

### docker-compose.yml
- Defines 3 services: `nginx`, `wordpress`, `mariadb`
- Creates the `app-network` network
- Creates 2 volumes (`wp`, `db`)
- Passes `.env` variables and secrets to containers
- Sets `restart: unless-stopped` for crash recovery

### NGINX
- **Dockerfile**: Installs `nginx` + `openssl` on Debian Bullseye
- **default** (conf): Listens on 443 with SSL, proxies `.php` to `wordpress:9000`
- **nginx_start.sh**: Generates a self-signed SSL certificate, then runs `nginx -g 'daemon off;'`

### WordPress
- **Dockerfile**: Installs PHP 7.4 + php-fpm + php-mysql + wget
- **wp-config.php**: Connects to MariaDB using env vars + secrets (no hardcoded passwords)
- **wordpress_start.sh**:
  1. Fixes php-fpm to listen on port 9000
  2. Downloads WordPress via WP-CLI (first run only)
  3. Creates admin user (`boss`) and regular user (`oayyoub`)
  4. Runs `php-fpm7.4 --nodaemonize` (foreground — PID 1)

### MariaDB
- **Dockerfile**: Installs `mariadb-server`
- **50-server.cnf**: Binds to `0.0.0.0` so other containers can connect
- **mariadb_start.sh**:
  1. Initializes the database (first run only)
  2. Creates the database and user using passwords from secrets
  3. Runs `mysqld` (foreground — PID 1)

---

## Instructions

### Prerequisites
- Docker and Docker Compose (v2) installed
- Add your user to the docker group: `sudo usermod -aG docker $USER`
- Add domain to hosts file: `echo "127.0.0.1 oayyoub.42.fr" | sudo tee -a /etc/hosts`

### Build and Run
```bash
make
```

### Access
- Website: https://oayyoub.42.fr
- Admin panel: https://oayyoub.42.fr/wp-admin
- Admin credentials: `boss` / (password in `secrets/credentials.txt`)

### Stop
```bash
make down
```

### Full Rebuild
```bash
make re
```

---

## Key Rules

| Rule | How it's done |
|------|--------------|
| No `latest` tag | `FROM debian:bullseye` (specific version) |
| No ready-made images | All Dockerfiles build from Debian, install manually |
| No passwords in Dockerfiles | All passwords in `secrets/` files |
| No `tail -f`, `sleep infinity`, `while true` | Services run in foreground |
| No `network: host` or `--link` | Uses a named docker network |
| Only port 443 exposed | Only nginx exposes a port |
| TLSv1.2 or TLSv1.3 only | Set in nginx config `ssl_protocols TLSv1.3` |
| Admin username can't contain "admin" | Admin is `boss` |
| Two WordPress users | `boss` (admin) + `oayyoub` (subscriber) |
| Restart on crash | `restart: unless-stopped` in docker-compose |
| Domain name = login.42.fr | `oayyoub.42.fr` → `127.0.0.1` in `/etc/hosts` |

---

## Testing

```bash
# Check containers are running
docker ps

# Test HTTPS
curl -k https://oayyoub.42.fr

# Check database has 2 users
docker exec mariadb mysql -u oayyoub -p'<password>' wordpress -e "SELECT * FROM wp_users;"

# Check TLS version
echo | openssl s_client -connect oayyoub.42.fr:443 2>/dev/null | grep Protocol
```

---

## Resources

- [Docker documentation](https://docs.docker.com/)
- [Docker Compose documentation](https://docs.docker.com/compose/)
- [NGINX documentation](https://nginx.org/en/docs/)
- [WordPress CLI documentation](https://developer.wordpress.org/cli/commands/)
- [MariaDB documentation](https://mariadb.com/kb/en/documentation/)

### Virtual Machines vs Docker
- **VMs** virtualize hardware, each VM runs a full OS — heavy, slow to start.
- **Docker** virtualizes at the OS level using containers that share the host kernel — lightweight, fast.

### Secrets vs Environment Variables
- **Environment variables** are visible in `docker inspect`, process lists, and logs.
- **Docker secrets** are mounted as files, only accessible inside the container, and never stored in images.

### Docker Network vs Host Network
- **Host network** exposes all container ports directly on the host — no isolation.
- **Docker bridge network** isolates containers, they communicate by service name, only explicitly exposed ports are reachable.

### Docker Volumes vs Bind Mounts
- **Volumes** are managed by Docker, portable, and recommended for persistent data.
- **Bind mounts** map a specific host path to a container path — used here for `/home/oayyoub/data/` to meet the subject requirements.
