# WordPress + PHP-FPM Service

## What is WordPress?

WordPress is a web application written in PHP that creates websites. It needs two things:
1. **A database** (MariaDB) to store content
2. **A PHP processor** (PHP-FPM) to execute its code

## What is PHP-FPM?

PHP-FPM (FastCGI Process Manager) is the engine that **runs PHP code**. NGINX cannot execute PHP on its own — it forwards `.php` requests to PHP-FPM.

```
User → NGINX → "This is a .php file, I can't handle it"
                    │
                    ▼
              PHP-FPM (port 9000) → executes PHP → returns HTML
                    │
                    ▼
              NGINX ← sends HTML back to user
```

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│              WordPress Container                │
│                                                 │
│  ┌──────────────────────────────┐               │
│  │  PHP-FPM 7.4                │               │
│  │  Listening on port 9000     │               │
│  │                              │               │
│  │  Processes:                  │               │
│  │  ┌──────────┐ ┌──────────┐  │               │
│  │  │ Worker 1 │ │ Worker 2 │  │               │
│  │  └──────────┘ └──────────┘  │               │
│  │  ┌──────────┐               │               │
│  │  │ Worker 3 │               │               │
│  │  └──────────┘               │               │
│  └──────────────────────────────┘               │
│                                                 │
│  /var/www/html/                                 │
│  ├── wp-config.php                              │
│  ├── wp-login.php                               │
│  ├── wp-admin/                                  │
│  ├── wp-content/                                │
│  └── wp-includes/                               │
│                                                 │
│  Network: connects to mariadb:3306              │
└─────────────────────────────────────────────────┘
```

---

## Dockerfile

```dockerfile
FROM debian:bullseye

RUN apt-get update && apt-get install -y \
    php7.4 php7.4-fpm php7.4-mysql wget && \
    rm -rf /var/lib/apt/lists/*

COPY ./conf/www.conf /tmp/www.conf
COPY ./tools/wp-config.php /tmp/wp-config.php
COPY ./tools/wordpress_start.sh /usr/local/bin/

RUN chmod +x /usr/local/bin/wordpress_start.sh

ENTRYPOINT ["wordpress_start.sh"]
CMD ["/usr/sbin/php-fpm7.4", "--nodaemonize"]
```

| Line | What it does |
|------|-------------|
| `php7.4` | PHP language runtime |
| `php7.4-fpm` | FastCGI Process Manager |
| `php7.4-mysql` | PHP extension to connect to MariaDB |
| `wget` | Tool to download WP-CLI and WordPress |
| `COPY www.conf /tmp/` | PHP-FPM pool config (copied to final location by startup script) |
| `COPY wp-config.php /tmp/` | WordPress database config |
| `--nodaemonize` | Run in foreground (required for Docker) |

### Why /tmp/?

Files are copied to `/tmp/` during build, then the startup script moves them to their final locations. This is because `/var/www/html/` is a volume mount — anything written there during build gets **overwritten** when the volume is mounted at runtime.

```
Build time:    /var/www/html/ ← files written here are LOST
Runtime:       /var/www/html/ ← volume mounted from host (empty first time)

Solution: Copy to /tmp/ during build → Move to /var/www/html/ at runtime
```

---

## PHP-FPM Config (www.conf)

```ini
[www]
user = www-data
group = www-data
listen = 9000
listen.owner = www-data
listen.group = www-data
pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
clear_env = no
```

| Setting | What it does |
|---------|-------------|
| `user = www-data` | Worker processes run as www-data (not root) |
| `listen = 9000` | Listen on TCP port 9000 (NGINX connects here) |
| `pm = dynamic` | Workers are created/destroyed based on load |
| `pm.max_children = 5` | Maximum 5 PHP workers at once |
| `pm.start_servers = 2` | Start with 2 workers ready |
| `clear_env = no` | **Critical**: pass environment variables to PHP |

### Why `clear_env = no`?

```
clear_env = yes (default)
  → PHP-FPM wipes all environment variables
  → WordPress cannot read MYSQL_DATABASE, MYSQL_USER, etc.
  → wp-config.php getenv() calls return empty ❌

clear_env = no
  → Environment variables from docker-compose.yml are visible
  → WordPress can connect to database ✅
```

### Process Manager Modes

```
pm = static     → Always keep a fixed number of workers
pm = dynamic    → Scale workers up/down based on load ← we use this
pm = ondemand   → Create workers only when requests arrive
```

---

## Startup Script (wordpress_start.sh)

```bash
#!/bin/bash

# Fix PHP-FPM config
cp /tmp/www.conf /etc/php/7.4/fpm/pool.d/www.conf
mkdir -p /run/php

# Create web directory
mkdir -p /var/www/html

# Download WP-CLI
if [ ! -f /usr/local/bin/wp ]; then
    wget -q https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
        -O /usr/local/bin/wp
    chmod +x /usr/local/bin/wp
fi

cd /var/www/html

# Download WordPress
if [ ! -f wp-load.php ]; then
    wp core download --allow-root
fi

# Copy config
cp /tmp/wp-config.php /var/www/html/wp-config.php

# Read secrets
WP_ADMIN_PASS=$(cat /run/secrets/credentials)
WP_USER_PASS=$(cat /run/secrets/credentials)

# Install WordPress
if ! wp core is-installed --allow-root 2>/dev/null; then
    wp core install \
        --url="https://${DOMAIN_NAME}" \
        --title="${WP_TITLE}" \
        --admin_user="${WP_ADMIN_LOGIN}" \
        --admin_password="${WP_ADMIN_PASS}" \
        --admin_email="${WP_ADMIN_EMAIL}" \
        --skip-email \
        --allow-root

    wp user create \
        "${WP_USER_LOGIN}" \
        "${WP_USER_EMAIL}" \
        --role=author \
        --user_pass="${WP_USER_PASS}" \
        --allow-root
fi

chown -R www-data:www-data /var/www/html
exec "$@"
```

### Step by step

```
Container starts
    │
    ▼
1. Copy www.conf to PHP-FPM config directory
   Create /run/php/ for the PID file
    │
    ▼
2. Download WP-CLI (if not already downloaded)
   WP-CLI = command-line tool to manage WordPress
    │
    ▼
3. Download WordPress core files (if not already downloaded)
   Puts ~1500 files in /var/www/html/
    │
    ▼
4. Copy wp-config.php (database connection settings)
    │
    ▼
5. Read admin password from /run/secrets/credentials
    │
    ▼
6. Is WordPress already installed?
    │
    ├── NO → Install WordPress:
    │         - Create database tables
    │         - Set site title and URL
    │         - Create admin user "boss"
    │         - Create regular user "oayyoub" (author role)
    │
    ├── YES → Skip installation
    │
    ▼
7. Set file ownership to www-data
    │
    ▼
8. exec "$@" → run php-fpm7.4 --nodaemonize (PID 1)
```

---

## WP-CLI Commands Explained

### wp core download
Downloads WordPress core files from wordpress.org into the current directory.

### wp core install
Creates database tables and sets up the site:
```bash
wp core install \
    --url="https://oayyoub.42.fr" \      # Site URL
    --title="inception" \              # Site name
    --admin_user="boss" \              # Admin username
    --admin_password="boss12345" \     # From secrets file
    --admin_email="boss@42.fr" \       # Admin email
    --skip-email \                     # Don't send welcome email
    --allow-root                       # Required because running as root
```

### wp user create
Creates additional users:
```bash
wp user create \
    "oayyoub" \                           # Username
    "oayyoub@42.fr" \                     # Email
    --role=author \                    # Permission level
    --user_pass="boss12345" \          # Password
    --allow-root
```

### WordPress User Roles

| Role | Can do |
|------|--------|
| **Administrator** | Everything (themes, plugins, users, settings) |
| **Editor** | Manage all posts, including others' posts |
| **Author** | Write and publish their own posts |
| **Contributor** | Write posts but cannot publish |
| **Subscriber** | Can only read and manage their profile |

---

## wp-config.php

```php
<?php
define('DB_NAME',     getenv('MYSQL_DATABASE'));
define('DB_USER',     getenv('MYSQL_USER'));
define('DB_PASSWORD', trim(file_get_contents('/run/secrets/db_password')));
define('DB_HOST',     'mariadb');
define('DB_CHARSET',  'utf8');
define('DB_COLLATE',  '');

$table_prefix = 'wp_';

define('WP_DEBUG', false);

if (!defined('ABSPATH')) {
    define('ABSPATH', '/var/www/html/');
}

require_once ABSPATH . 'wp-settings.php';
```

| Setting | Value | Source |
|---------|-------|--------|
| `DB_NAME` | `wordpress` | Environment variable (docker-compose) |
| `DB_USER` | `oayyoub` | Environment variable (docker-compose) |
| `DB_PASSWORD` | `db_pass123` | Secret file (Docker secrets) |
| `DB_HOST` | `mariadb` | Docker service name (resolved via DNS) |
| `ABSPATH` | `/var/www/html/` | Where WordPress files live |

### How WordPress finds MariaDB

```
wp-config.php says: DB_HOST = 'mariadb'
    │
    ▼
Docker DNS resolves 'mariadb' → 172.18.0.2 (container IP)
    │
    ▼
PHP connects to 172.18.0.2:3306
    │
    ▼
MariaDB authenticates user 'oayyoub' with password 'db_pass123'
    │
    ▼
WordPress reads/writes the 'wordpress' database
```

---

## Where is the Data?

```
Container: /var/www/html/
    │ (docker volume bind mount)
    ▼
Host: /home/oayyoub/data/wordpress
    ├── wp-config.php
    ├── wp-admin/
    ├── wp-content/
    │   ├── themes/
    │   ├── plugins/
    │   └── uploads/          ← user-uploaded media
    ├── wp-includes/
    └── wp-load.php
```

---

## Testing Commands

```bash
# Enter the container
docker exec -it wordpress bash

# Check PHP-FPM is running
ps aux | grep php-fpm

# Test database connection
wp db check --allow-root

# List WordPress users
wp user list --allow-root

# Check installed plugins
wp plugin list --allow-root

# View logs
docker logs wordpress

# Test from NGINX container
docker exec -it nginx bash
# Then: apt-get install -y curl && curl http://wordpress:9000
```
