# MariaDB Service

## What is MariaDB?

MariaDB is a relational database that stores data in tables (rows and columns). It's a fork of MySQL. In this project, MariaDB stores all WordPress data: posts, pages, users, settings, comments.

---

## How MariaDB Works

```
┌──────────────────────────────────────────┐
│              MariaDB Server              │
│                                          │
│  ┌──────────┐  ┌──────────┐             │
│  │ Database: │  │ Database: │             │
│  │ wordpress │  │  mysql   │  (system)   │
│  │           │  │          │             │
│  │ wp_users  │  │ user     │             │
│  │ wp_posts  │  │ db       │             │
│  │ wp_options│  │ ...      │             │
│  │ ...       │  │          │             │
│  └──────────┘  └──────────┘             │
│                                          │
│  Listens on port 3306                    │
│  Data stored in /var/lib/mysql           │
└──────────────────────────────────────────┘
```

| Concept | What it is | Example |
|---------|-----------|---------|
| **Server** | The MariaDB process (`mysqld`) | Runs as PID 1 in container |
| **Database** | A collection of tables | `wordpress` |
| **Table** | Rows and columns | `wp_users` |
| **User** | An account that can connect | `nova@%` |
| **Root** | Super admin account | `root@localhost` |
| **Port** | Network port it listens on | `3306` |

---

## Dockerfile

```dockerfile
FROM debian:bullseye

RUN apt-get update && apt-get install -y mariadb-server && rm -rf /var/lib/apt/lists/*

COPY ./conf/50-server.cnf /etc/mysql/mariadb.conf.d/
COPY ./tools/mariadb_start.sh /usr/local/bin/

RUN chmod +x /usr/local/bin/mariadb_start.sh

ENTRYPOINT ["mariadb_start.sh"]
CMD ["mysqld"]
```

| Line | What it does |
|------|-------------|
| `FROM debian:bullseye` | Base image — Debian 11 |
| `apt-get install mariadb-server` | Installs MariaDB |
| `rm -rf /var/lib/apt/lists/*` | Removes apt cache to reduce image size |
| `COPY 50-server.cnf` | Custom config: bind to all interfaces |
| `COPY mariadb_start.sh` | Startup script that initializes DB |
| `ENTRYPOINT` | Script that runs first when container starts |
| `CMD ["mysqld"]` | The argument passed to the entrypoint (`exec "$@"`) |

### How ENTRYPOINT + CMD work together

```
Container starts → runs: mariadb_start.sh mysqld
                          ▲ ENTRYPOINT      ▲ CMD

Inside the script, "exec $@" replaces the script with "mysqld"
So the final process running is: mysqld (PID 1)
```

---

## Config File (50-server.cnf)

```ini
[mysqld]
user                    = mysql
pid-file                = /run/mysqld/mysqld.pid
socket                  = /run/mysqld/mysqld.sock
port                    = 3306
datadir                 = /var/lib/mysql
bind-address            = 0.0.0.0
character-set-server    = utf8mb4
collation-server        = utf8mb4_general_ci
```

| Setting | What it does | Why |
|---------|-------------|-----|
| `datadir` | Where database files are stored | Mapped to volume `/home/nova/data/mariadb` |
| `socket` | Unix socket file for local connections | Used by `mysql` CLI tool |
| `bind-address = 0.0.0.0` | Accept connections from any IP | Without this, WordPress can't connect |
| `port = 3306` | Listen on port 3306 | Standard MySQL/MariaDB port |

### Why `bind-address = 0.0.0.0`?

```
bind-address = 127.0.0.1 (default)
  → Only accepts connections from inside the same container
  → WordPress container CANNOT connect ❌

bind-address = 0.0.0.0
  → Accepts connections from any container on the network
  → WordPress container CAN connect ✅
```

---

## Startup Script (mariadb_start.sh)

```bash
#!/bin/bash

DB_PASS=$(cat /run/secrets/db_password)
DB_ROOT_PASS=$(cat /run/secrets/db_root_password)

mkdir -p /run/mysqld
chown mysql:mysql /run/mysqld

if [ ! -d "/var/lib/mysql/${MYSQL_DATABASE}" ]; then
    mysql_install_db --user=mysql --datadir=/var/lib/mysql > /dev/null 2>&1
    mysqld --user=mysql --bootstrap << EOF
FLUSH PRIVILEGES;
CREATE DATABASE IF NOT EXISTS ${MYSQL_DATABASE};
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${MYSQL_DATABASE}.* TO '${MYSQL_USER}'@'%';
FLUSH PRIVILEGES;
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASS}';
FLUSH PRIVILEGES;
EOF
fi

exec "$@"
```

### Step by step

```
Container starts
    │
    ▼
1. Read passwords from secret files
    │
    ▼
2. Create /run/mysqld directory (needed for socket file)
    │
    ▼
3. Check: is this the FIRST run?
    │
    ├── YES (no database folder exists)
    │     │
    │     ├── mysql_install_db → creates system tables
    │     │
    │     └── mysqld --bootstrap → runs SQL:
    │           - Set root password
    │           - Create "wordpress" database
    │           - Create "nova" user with password
    │           - Grant all permissions
    │
    ├── NO (database already exists from volume)
    │     └── Skip initialization
    │
    ▼
4. exec "$@" → replaces script with "mysqld" (PID 1)
```

---

## SQL Commands Explained

```sql
-- Set root password (root can only connect locally)
ALTER USER 'root'@'localhost' IDENTIFIED BY 'root_pass123';

-- Create the wordpress database
CREATE DATABASE IF NOT EXISTS wordpress;

-- Create user "nova" that can connect from ANY host (%)
-- '%' is needed because WordPress connects from a different container
CREATE USER IF NOT EXISTS 'nova'@'%' IDENTIFIED BY 'db_pass123';

-- Give "nova" full access to wordpress database only
GRANT ALL PRIVILEGES ON wordpress.* TO 'nova'@'%';

-- Apply permission changes
FLUSH PRIVILEGES;
```

### User permissions

| User | Host | Can access | Password source |
|------|------|-----------|-----------------|
| `root` | `localhost` | Everything | `secrets/db_root_password.txt` |
| `nova` | `%` (anywhere) | Only `wordpress` database | `secrets/db_password.txt` |

---

## Key Concepts

### mysql_install_db
Creates the initial system database (`mysql` database) with user/permission tables. Runs only once on first start.

### mysqld --bootstrap
Runs SQL commands without starting a full server. No network, no connections — safer than `service mysql start && mysql < file.sql`.

### exec "$@"
Replaces the bash script with `mysqld`. Makes `mysqld` PID 1 so Docker signals (stop/restart) reach it directly for clean shutdowns.

---

## Where is the Data?

```
Container: /var/lib/mysql
    │ (docker volume bind mount)
    ▼
Host: /home/nova/data/mariadb
    ├── wordpress/          ← WordPress database files
    ├── mysql/              ← System database
    ├── ibdata1             ← InnoDB data
    └── ib_logfile0         ← InnoDB log
```

| Action | Data survives? |
|--------|---------------|
| `docker compose down` | ✅ Yes |
| `docker compose up` again | ✅ Yes |
| `make fclean` | ❌ No |

---

## Testing Commands

```bash
# Enter the container
docker exec -it mariadb bash

# Connect as nova
mysql -u nova -p wordpress

# Connect as root
mysql -u root -p

# Show databases
SHOW DATABASES;

# See WordPress users
USE wordpress;
SELECT ID, user_login, user_email FROM wp_users;

# Check who can connect
SELECT user, host FROM mysql.user;

# View logs
docker logs mariadb
```
