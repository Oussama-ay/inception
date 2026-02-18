# Inception — Architecture Diagram

---

## 1. Full Infrastructure Overview

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                           HOST MACHINE (Linux/WSL)                         ║
║                                                                            ║
║   /etc/hosts: 127.0.0.1 nova.42.fr                                        ║
║                                                                            ║
║   ┌──────────────────────────────────────────────────────────────────┐      ║
║   │                    DOCKER ENGINE                                 │      ║
║   │                                                                  │      ║
║   │   ┌──────────────────────────────────────────────────────────┐   │      ║
║   │   │              NETWORK: inception (bridge)                 │   │      ║
║   │   │                                                          │   │      ║
║   │   │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │   │      ║
║   │   │  │    NGINX     │  │  WORDPRESS   │  │   MARIADB    │  │   │      ║
║   │   │  │              │  │              │  │              │  │   │      ║
║   │   │  │  Port 443    │  │  Port 9000   │  │  Port 3306   │  │   │      ║
║   │   │  │  (exposed)   │  │  (internal)  │  │  (internal)  │  │   │      ║
║   │   │  └──────────────┘  └──────────────┘  └──────────────┘  │   │      ║
║   │   │                                                          │   │      ║
║   │   └──────────────────────────────────────────────────────────┘   │      ║
║   │                                                                  │      ║
║   │   VOLUMES:                                                       │      ║
║   │   ┌────────────────────────┐  ┌────────────────────────┐        │      ║
║   │   │ wp: WordPress files   │  │ db: Database files     │        │      ║
║   │   │ /home/nova/data/      │  │ /home/nova/data/       │        │      ║
║   │   │         wordpress     │  │         mariadb        │        │      ║
║   │   └────────────────────────┘  └────────────────────────┘        │      ║
║   │                                                                  │      ║
║   └──────────────────────────────────────────────────────────────────┘      ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

---

## 2. Request AND Response Flow — Complete Round Trip

```
══════════════════════════════════════════════════════════════════════
                    REQUEST (Browser → Server)
══════════════════════════════════════════════════════════════════════

Browser                NGINX               WordPress            MariaDB
   │                     │                     │                    │
   │  GET /index.php     │                     │                    │
   │  HTTPS (port 443)   │                     │                    │
   │ ──────────────────▶ │                     │                    │
   │                     │                     │                    │
   │                     │  FastCGI            │                    │
   │                     │  (port 9000)        │                    │
   │                     │ ──────────────────▶ │                    │
   │                     │                     │                    │
   │                     │                     │  SQL query         │
   │                     │                     │  (port 3306)       │
   │                     │                     │ ─────────────────▶ │
   │                     │                     │                    │


══════════════════════════════════════════════════════════════════════
                    RESPONSE (Server → Browser)
══════════════════════════════════════════════════════════════════════

Browser                NGINX               WordPress            MariaDB
   │                     │                     │                    │
   │                     │                     │                    │
   │                     │                     │  SQL results       │
   │                     │                     │  (port 3306)       │
   │                     │                     │ ◀───────────────── │
   │                     │                     │                    │
   │                     │  HTML response      │                    │
   │                     │  (port 9000)        │                    │
   │                     │ ◀────────────────── │                    │
   │                     │                     │                    │
   │  HTML page          │                     │                    │
   │  HTTPS (port 443)   │                     │                    │
   │ ◀────────────────── │                     │                    │
   │                     │                     │                    │
```

---

## 3. Detailed Step-by-Step — Request + Response

```
╔══════════════════════════════════════════════════════════════════════╗
║ STEP 1: Browser → NGINX (REQUEST)                                   ║
║                                                                      ║
║   Protocol: HTTPS (TLSv1.2 or TLSv1.3)                              ║
║   Port:     443                                                      ║
║   Data:     GET / HTTP/1.1  Host: nova.42.fr                         ║
║   Flow:     Browser ═══encrypted═══▶ NGINX                          ║
║                                                                      ║
║   NGINX decrypts the TLS → reads the HTTP request                    ║
║   Sees: request is for index.php → must forward to PHP-FPM           ║
╚══════════════════════════════════════════════════════════════════════╝
                              │
                              ▼
╔══════════════════════════════════════════════════════════════════════╗
║ STEP 2: NGINX → WordPress (REQUEST)                                 ║
║                                                                      ║
║   Protocol: FastCGI                                                  ║
║   Port:     9000                                                     ║
║   Data:     SCRIPT_FILENAME=/var/www/html/index.php                  ║
║   Flow:     NGINX ───fastcgi_pass───▶ wordpress:9000                 ║
║                                                                      ║
║   PHP-FPM receives the request                                       ║
║   Executes /var/www/html/index.php                                   ║
║   WordPress code loads wp-config.php                                 ║
║   Needs data from database                                           ║
╚══════════════════════════════════════════════════════════════════════╝
                              │
                              ▼
╔══════════════════════════════════════════════════════════════════════╗
║ STEP 3: WordPress → MariaDB (REQUEST)                               ║
║                                                                      ║
║   Protocol: MySQL                                                    ║
║   Port:     3306                                                     ║
║   Data:     SELECT * FROM wp_posts WHERE post_status='publish'       ║
║   Auth:     user=nova, pass=(from /run/secrets/db_password)          ║
║   Flow:     WordPress ───MySQL protocol───▶ mariadb:3306             ║
║                                                                      ║
║   MariaDB receives the SQL query                                     ║
║   Reads data from /var/lib/mysql/wordpress/                          ║
║   Prepares the result set                                            ║
╚══════════════════════════════════════════════════════════════════════╝
                              │
                              ▼
╔══════════════════════════════════════════════════════════════════════╗
║ STEP 4: MariaDB → WordPress (RESPONSE)                              ║
║                                                                      ║
║   Protocol: MySQL                                                    ║
║   Port:     3306 (same connection, reverse direction)                ║
║   Data:     Result rows: {id:1, title:"Hello World", content:"..."}  ║
║   Flow:     mariadb:3306 ───MySQL result───▶ WordPress               ║
║                                                                      ║
║   PHP receives the data                                              ║
║   WordPress generates HTML from the data                             ║
║   Builds: <html><head><title>inception</title>...</html>             ║
╚══════════════════════════════════════════════════════════════════════╝
                              │
                              ▼
╔══════════════════════════════════════════════════════════════════════╗
║ STEP 5: WordPress → NGINX (RESPONSE)                                ║
║                                                                      ║
║   Protocol: FastCGI                                                  ║
║   Port:     9000 (same connection, reverse direction)                ║
║   Data:     HTTP/1.1 200 OK                                          ║
║             Content-Type: text/html                                  ║
║             <html><head><title>inception</title>...</html>           ║
║   Flow:     wordpress:9000 ───FastCGI response───▶ NGINX             ║
║                                                                      ║
║   NGINX receives the HTML                                            ║
║   Encrypts it with TLS                                               ║
╚══════════════════════════════════════════════════════════════════════╝
                              │
                              ▼
╔══════════════════════════════════════════════════════════════════════╗
║ STEP 6: NGINX → Browser (RESPONSE)                                  ║
║                                                                      ║
║   Protocol: HTTPS (TLSv1.2 or TLSv1.3)                              ║
║   Port:     443 (same connection, reverse direction)                 ║
║   Data:     Encrypted HTML page                                      ║
║   Flow:     NGINX ═══encrypted═══▶ Browser                          ║
║                                                                      ║
║   Browser decrypts the TLS                                           ║
║   Renders the HTML page                                              ║
║   Page displayed ✅                                                   ║
╚══════════════════════════════════════════════════════════════════════╝
```

---

## 4. Static Files — Different Flow (No PHP, No Database)

```
Browser requests: https://nova.42.fr/wp-content/themes/style.css

╔══════════════════════════════════════════════════════════════════════╗
║ REQUEST:  Browser ═══HTTPS (443)═══▶ NGINX                         ║
║                                                                      ║
║   NGINX checks: is style.css a .php file?                            ║
║   NO → serve it directly from /var/www/html/ (shared volume)         ║
║   No PHP-FPM needed, no database needed                              ║
║                                                                      ║
║ RESPONSE: NGINX ═══HTTPS (443)═══▶ Browser                          ║
║                                                                      ║
║   Only 2 steps instead of 6 → much faster                           ║
╚══════════════════════════════════════════════════════════════════════╝

  Browser ◀══port 443══▶ NGINX ──reads──▶ /var/www/html/style.css
                                           (wp volume)

  WordPress: not involved ❌
  MariaDB:   not involved ❌
```

---

## 5. Port Communication Map

```
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│    OUTSIDE (Browser/Host)                                               │
│         │                                                               │
│         │ port 443 (ONLY open port)                                     │
│         │                                                               │
│    ═════╪═══════════════════════════════════════════════════════════     │
│         │         DOCKER NETWORK: inception                             │
│         │                                                               │
│         ▼                                                               │
│    ┌─────────┐         ┌───────────┐          ┌──────────┐             │
│    │  NGINX  │         │ WORDPRESS │          │ MARIADB  │             │
│    │         │         │           │          │          │             │
│    │ :443 ◄──┼── TLS ──┼── :443   │          │          │             │
│    │         │         │           │          │          │             │
│    │    ─────┼─────────┼▶ :9000   │          │          │             │
│    │    REQ  │ FastCGI │  PHP-FPM  │          │          │             │
│    │    ◀────┼─────────┼─ :9000   │          │          │             │
│    │    RESP │ FastCGI │           │          │          │             │
│    │         │         │     ──────┼──────────┼▶ :3306  │             │
│    │         │         │     REQ   │  MySQL   │  mysqld  │             │
│    │         │         │     ◀─────┼──────────┼─ :3306  │             │
│    │         │         │     RESP  │  MySQL   │          │             │
│    │         │         │           │          │          │             │
│    └─────────┘         └───────────┘          └──────────┘             │
│                                                                         │
│    ═════════════════════════════════════════════════════════════════     │
│                                                                         │
│    CLOSED PORTS:                                                        │
│      9000 → NOT accessible from outside (expose only)                   │
│      3306 → NOT accessible from outside (expose only)                   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 6. Protocol on Each Port — Request AND Response

```
╔═══════════╦══════╦════════════════╦═══════════════════════════════════════╗
║ Port      ║ Type ║ Protocol       ║ What travels on it                    ║
╠═══════════╬══════╬════════════════╬═══════════════════════════════════════╣
║           ║      ║                ║                                       ║
║ 443       ║ports ║ HTTPS          ║ REQUEST:  encrypted HTTP request      ║
║           ║      ║ (TLS 1.2/1.3) ║ RESPONSE: encrypted HTML/CSS/JS/IMG   ║
║           ║      ║                ║                                       ║
╠═══════════╬══════╬════════════════╬═══════════════════════════════════════╣
║           ║      ║                ║                                       ║
║ 9000      ║expose║ FastCGI        ║ REQUEST:  PHP filename + parameters   ║
║           ║      ║                ║ RESPONSE: generated HTML              ║
║           ║      ║                ║                                       ║
╠═══════════╬══════╬════════════════╬═══════════════════════════════════════╣
║           ║      ║                ║                                       ║
║ 3306      ║expose║ MySQL          ║ REQUEST:  SQL queries                 ║
║           ║      ║                ║ RESPONSE: query results (rows/data)   ║
║           ║      ║                ║                                       ║
╚═══════════╩══════╩════════════════╩═══════════════════════════════════════╝
```

---

## 7. Volume Sharing

```
/home/nova/data/wordpress (HOST)
         │
         │  bind mount
         │
         ├──────────────────────────────────────────┐
         │                                          │
         ▼                                          ▼
┌─────────────────────┐                ┌─────────────────────┐
│       NGINX         │                │     WORDPRESS       │
│                     │                │                     │
│  /var/www/html/     │                │  /var/www/html/     │
│  ├── index.php      │                │  ├── index.php      │
│  ├── style.css  ◄───── serves       │  ├── style.css      │
│  ├── image.png  ◄───── static       │  ├── image.png      │
│  ├── wp-admin/      │   files        │  ├── wp-admin/      │
│  └── wp-content/    │                │  └── wp-content/    │
│       READS ONLY    │                │    READS + WRITES   │
└─────────────────────┘                └─────────────────────┘

SAME FILES — both containers see the same directory


/home/nova/data/mariadb (HOST)
         │
         │  bind mount
         │
         ▼
┌─────────────────────┐
│      MARIADB        │
│                     │
│  /var/lib/mysql/    │
│  ├── wordpress/     │  ← WordPress database tables
│  ├── mysql/         │  ← System database
│  ├── ibdata1        │  ← InnoDB data
│  └── ib_logfile0    │  ← InnoDB logs
│    READS + WRITES   │
└─────────────────────┘
```

---

## 8. Secrets Flow

```
HOST: /home/nova/inception/secrets/
├── credentials.txt        "boss12345"
├── db_password.txt        "db_pass123"
└── db_root_password.txt   "root_pass123"
         │
         │  docker secrets (read-only, in RAM)
         │
         ├──────────────────────────────┐
         │                              │
         ▼                              ▼
┌─────────────────────┐    ┌─────────────────────┐
│     WORDPRESS       │    │      MARIADB        │
│                     │    │                     │
│ /run/secrets/       │    │ /run/secrets/       │
│ ├── credentials     │    │ ├── db_password     │
│ │   (admin pass)    │    │ │   (user pass)     │
│ └── db_password     │    │ └── db_root_password│
│     (user pass)     │    │     (root pass)     │
└─────────────────────┘    └─────────────────────┘

NGINX has NO secrets (doesn't need passwords)
```

---

## 9. Container Startup Order

```
docker compose up
         │
         ▼
    ┌──────────┐
    │ MARIADB  │  starts FIRST (no dependencies)
    │          │
    │ 1. Run mariadb_start.sh
    │ 2. mysql_install_db (first run)
    │ 3. Create database + users
    │ 4. exec mysqld (PID 1)
    │ 5. Listening on :3306 ✅
    └────┬─────┘
         │
         │  depends_on: mariadb
         ▼
    ┌──────────┐
    │WORDPRESS │  starts SECOND
    │          │
    │ 1. Run wordpress_start.sh
    │ 2. Download WordPress (first run)
    │ 3. wp core install (create tables in MariaDB)
    │ 4. wp user create (2 users)
    │ 5. exec php-fpm7.4 -F (PID 1)
    │ 6. Listening on :9000 ✅
    └────┬─────┘
         │
         │  depends_on: wordpress
         ▼
    ┌──────────┐
    │  NGINX   │  starts LAST
    │          │
    │ 1. Run nginx_start.sh
    │ 2. Generate SSL cert (first run)
    │ 3. exec nginx -g "daemon off;" (PID 1)
    │ 4. Listening on :443 ✅
    └──────────┘

    ALL RUNNING → Infrastructure ready
```

---

## 10. What Happens on Crash

```
Container crashes (exit code ≠ 0)
         │
         ▼
    restart: on-failure
         │
         ▼
    Docker restarts the container
         │
         ▼
    Volume data still exists
    (no re-initialization needed)
         │
         ▼
    Container runs normally ✅


Container stopped manually (docker stop / make down)
         │
         ▼
    restart: on-failure
         │
         ▼
    Docker does NOT restart
    (exit code = 0, not a failure)
```

---

## 11. Summary Table

```
╔═══════════╦════════════════════╦════════╦════════════════════╦═════════════════╗
║ Container ║ Process (PID 1)    ║ Port   ║ Connects to        ║ Volume          ║
╠═══════════╬════════════════════╬════════╬════════════════════╬═════════════════╣
║ nginx     ║ nginx              ║ 443    ║ wordpress:9000     ║ wp:/var/www/html║
║ wordpress ║ php-fpm7.4         ║ 9000   ║ mariadb:3306       ║ wp:/var/www/html║
║ mariadb   ║ mysqld             ║ 3306   ║ (none)             ║ db:/var/lib/mysql║
╚═══════════╩════════════════════╩════════╩════════════════════╩═════════════════╝

╔═══════════╦══════════════════════════╦════════════════════════════════════════╗
║ Container ║ Secrets                  ║ Env Vars                             ║
╠═══════════╬══════════════════════════╬════════════════════════════════════════╣
║ nginx     ║ (none)                   ║ (none)                               ║
║ wordpress ║ credentials, db_password ║ DOMAIN_NAME, MYSQL_*, WP_*           ║
║ mariadb   ║ db_password,             ║ MYSQL_DATABASE, MYSQL_USER           ║
║           ║ db_root_password         ║                                      ║
╚═══════════╩══════════════════════════╩════════════════════════════════════════╝
```
