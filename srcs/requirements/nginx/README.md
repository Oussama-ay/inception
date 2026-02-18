# NGINX Service

## What is NGINX?

NGINX is a **web server** and **reverse proxy**. In this project it does two things:
1. **Terminates SSL/TLS** — handles HTTPS encryption
2. **Forwards PHP requests** to WordPress (PHP-FPM) on port 9000

NGINX is the **only container** exposed to the outside world (port 443).

---

## Architecture

```
Internet / Browser
    │
    │ HTTPS (port 443)
    ▼
┌─────────────────────────────────────────────────┐
│                NGINX Container                  │
│                                                 │
│  Listens on: 0.0.0.0:443 (SSL/TLS)             │
│  Server name: nova.42.fr                        │
│                                                 │
│  Request arrives:                               │
│  ┌────────────────────────────────────────┐     │
│  │ Is it a .php file?                     │     │
│  │                                        │     │
│  │  YES → fastcgi_pass wordpress:9000     │     │
│  │        (forward to PHP-FPM)            │     │
│  │                                        │     │
│  │  NO → Serve static file directly       │     │
│  │       (images, CSS, JS)                │     │
│  └────────────────────────────────────────┘     │
│                                                 │
│  SSL Certificate: /etc/nginx/ssl/nginx.crt      │
│  SSL Key:         /etc/nginx/ssl/nginx.key      │
│                                                 │
└─────────────────────────────────────────────────┘
    │                          │
    │ FastCGI (port 9000)      │ reads files from
    ▼                          ▼
WordPress Container        /var/www/html/ (shared volume)
```

---

## Dockerfile

```dockerfile
FROM debian:bullseye

RUN apt-get update && apt-get install -y nginx openssl && rm -rf /var/lib/apt/lists/*

COPY ./conf/default /etc/nginx/sites-available/default
COPY ./tools/nginx_start.sh /usr/local/bin/

RUN chmod +x /usr/local/bin/nginx_start.sh

ENTRYPOINT ["nginx_start.sh"]
CMD ["nginx", "-g", "daemon off;"]
```

| Line | What it does |
|------|-------------|
| `nginx` | Web server / reverse proxy |
| `openssl` | Tool to generate self-signed SSL certificates |
| `COPY default` | NGINX server configuration |
| `COPY nginx_start.sh` | Script that generates SSL cert on first run |
| `daemon off;` | Run in foreground (Docker requires this) |

### Why `daemon off;`?

```
nginx (default)          → Forks to background, PID 1 exits, container dies ❌
nginx -g "daemon off;"   → Stays in foreground as PID 1, container keeps running ✅
```

---

## NGINX Config (default)

```nginx
server {
    listen 443 ssl;
    listen [::]:443 ssl;

    server_name nova.42.fr;

    ssl_certificate     /etc/nginx/ssl/nginx.crt;
    ssl_certificate_key /etc/nginx/ssl/nginx.key;
    ssl_protocols       TLSv1.2 TLSv1.3;

    root /var/www/html;
    index index.php index.html;

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass wordpress:9000;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    }
}
```

### Line by line

| Directive | What it does |
|-----------|-------------|
| `listen 443 ssl` | Listen on port 443 with HTTPS |
| `listen [::]:443 ssl` | Same but for IPv6 |
| `server_name nova.42.fr` | Respond to requests for this domain |
| `ssl_certificate` | Path to the SSL certificate file |
| `ssl_certificate_key` | Path to the private key file |
| `ssl_protocols TLSv1.2 TLSv1.3` | Only allow modern TLS versions (42 subject requirement) |
| `root /var/www/html` | Where website files are (shared volume with WordPress) |
| `index index.php` | Default file to serve when visiting a directory |

### Location blocks

#### `location /` — handles all requests

```nginx
try_files $uri $uri/ /index.php?$args;
```

This tries three things in order:
```
Request: https://nova.42.fr/hello

1. try $uri         → Look for file: /var/www/html/hello
                       Not found? ↓

2. try $uri/        → Look for directory: /var/www/html/hello/
                       Not found? ↓

3. /index.php?$args → Pass to WordPress (index.php handles it)
                       WordPress uses "pretty permalinks" this way
```

#### `location ~ \.php$` — handles PHP files

```
Request: /wp-login.php

1. fastcgi_split_path_info → separates script path from extra path info
2. fastcgi_pass wordpress:9000 → forward to PHP-FPM in WordPress container
3. SCRIPT_FILENAME → tells PHP-FPM which file to execute

Full path sent: /var/www/html/wp-login.php
```

### How fastcgi_pass works

```
NGINX                          WordPress Container
  │                                    │
  │  fastcgi_pass wordpress:9000       │
  │ ────────────────────────────────►  │
  │  "Execute /var/www/html/index.php" │
  │                                    │
  │                              PHP-FPM reads index.php
  │                              from the SHARED VOLUME
  │                              executes PHP code
  │                              queries MariaDB
  │                              generates HTML
  │                                    │
  │  ◄──────────────────────────────── │
  │        HTML response               │
  │                                    │
  │  NGINX sends HTML to browser       │
```

**Important**: Both NGINX and WordPress share the same `/var/www/html` volume. NGINX needs access to serve static files (CSS, JS, images), while PHP-FPM needs access to execute PHP files.

---

## Startup Script (nginx_start.sh)

```bash
#!/bin/bash

if [ ! -f /etc/nginx/ssl/nginx.crt ]; then
    mkdir -p /etc/nginx/ssl
    openssl req -x509 -nodes \
        -days 365 \
        -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/nginx.key \
        -out /etc/nginx/ssl/nginx.crt \
        -subj "/C=FR/ST=IDF/L=Paris/O=42/CN=nova.42.fr"
fi

exec "$@"
```

### Step by step

```
Container starts
    │
    ▼
1. Does SSL certificate already exist?
    │
    ├── NO → Generate self-signed certificate:
    │         openssl req -x509 -nodes ...
    │         Creates:
    │         ├── /etc/nginx/ssl/nginx.crt (public certificate)
    │         └── /etc/nginx/ssl/nginx.key (private key)
    │
    ├── YES → Skip (already generated)
    │
    ▼
2. exec "$@" → runs "nginx -g daemon off;" (PID 1)
```

### OpenSSL options explained

| Flag | What it does |
|------|-------------|
| `-x509` | Generate a self-signed certificate (not a CSR) |
| `-nodes` | No passphrase on the private key |
| `-days 365` | Certificate expires in 1 year |
| `-newkey rsa:2048` | Generate a 2048-bit RSA key |
| `-keyout` | Where to save the private key |
| `-out` | Where to save the certificate |
| `-subj` | Certificate info (Country, State, City, Org, Common Name) |

### What is a self-signed certificate?

```
Normal HTTPS (production):
  You → Certificate Authority (e.g., Let's Encrypt)
  CA verifies you own the domain
  CA signs your certificate
  Browsers trust it ✅ (green padlock)

Self-signed (our project):
  You sign your own certificate
  No CA verification
  Browser shows warning ⚠️ "Your connection is not private"
  Still encrypted — valid for development/school projects
```

---

## SSL/TLS Explained

```
Without SSL (HTTP - port 80):
  Browser → "GET /login password=hello123" → Server
  Anyone on the network can read this ❌

With SSL (HTTPS - port 443):
  Browser → [encrypted gibberish] → Server
  Server decrypts using private key
  Nobody can read the traffic ✅
```

### TLS versions

| Version | Status |
|---------|--------|
| TLS 1.0 | Deprecated, insecure ❌ |
| TLS 1.1 | Deprecated, insecure ❌ |
| TLS 1.2 | Secure, widely used ✅ |
| TLS 1.3 | Most secure, fastest ✅ |

The 42 subject requires **TLSv1.2 or TLSv1.3 only**.

---

## Why Only Port 443?

The 42 subject says NGINX is the only entry point, and only port 443 is exposed.

```
docker-compose.yml:
  nginx:
    ports:
      - "443:443"    ← Only port exposed to host

  wordpress:
    (no ports)        ← Not accessible from outside

  mariadb:
    (no ports)        ← Not accessible from outside
```

```
Outside world can reach:
  ✅ https://nova.42.fr:443 → NGINX

Outside world CANNOT reach:
  ❌ wordpress:9000 (internal only)
  ❌ mariadb:3306 (internal only)
```

---

## Request Flow (Complete)

```
1. User types: https://nova.42.fr

2. DNS: nova.42.fr → 127.0.0.1 (from /etc/hosts)

3. Browser connects to 127.0.0.1:443

4. TLS Handshake:
   Browser ←→ NGINX exchange encryption keys
   (browser shows certificate warning because self-signed)

5. Browser sends: GET / HTTP/1.1

6. NGINX processes:
   location / → try_files → no static file found
   → rewrite to /index.php

7. NGINX matches: location ~ \.php$
   → fastcgi_pass wordpress:9000

8. Docker DNS: wordpress → 172.18.0.3

9. PHP-FPM receives request, runs index.php:
   - WordPress loads wp-config.php
   - Connects to MariaDB (mariadb:3306)
   - Queries database
   - Generates HTML

10. PHP-FPM sends HTML back to NGINX

11. NGINX encrypts HTML with TLS

12. Browser decrypts and displays the page
```

---

## Testing Commands

```bash
# Enter the container
docker exec -it nginx bash

# Test NGINX config syntax
nginx -t

# View NGINX config
cat /etc/nginx/sites-available/default

# Check SSL certificate
openssl x509 -in /etc/nginx/ssl/nginx.crt -text -noout

# Test from host
curl -k https://nova.42.fr

# Check what port is listening
ss -tlnp | grep 443

# View logs
docker logs nginx

# View access/error logs inside container
cat /var/log/nginx/access.log
cat /var/log/nginx/error.log
```
