# DEV_DOC

## Environment Setup from Scratch
### Prerequisites
- Linux environment
- Docker Engine installed
- Docker Compose plugin installed
- Access to sudo for Docker and filesystem operations used by Makefile

### Required Configuration Files
Already present in the repository:
- srcs/.env: non-sensitive runtime configuration
- srcs/docker-compose.yml: services, networks, volumes, secrets
- secrets/: secret files consumed by services
- Service-specific Dockerfiles and config under srcs/requirements/

### Secrets Setup
Generate default secret values:
- make secretfiles

Or manually create:
- secrets/db_password.txt
- secrets/db_root_password.txt
- secrets/credentials.txt

## Build and Launch with Makefile and Docker Compose
Primary commands (from repository root):
- Build and run stack: make
- Stop stack: make down
- Rebuild all from scratch: make re

Equivalent compose command used by Makefile:
- sudo docker compose -f ./srcs/docker-compose.yml up -d --build

## Container and Volume Management Commands
### Containers
- List: sudo docker compose -f ./srcs/docker-compose.yml ps
- Logs (all): sudo docker compose -f ./srcs/docker-compose.yml logs
- Logs (single service): sudo docker compose -f ./srcs/docker-compose.yml logs wordpress
- Restart one service: sudo docker compose -f ./srcs/docker-compose.yml restart nginx
- Execute shell in container: sudo docker exec -it wordpress sh

### Images/Cache Cleanup
- Non-volume cleanup: make clean
- Full cleanup including volumes: make fclean

## Data Location and Persistence Model
Persistent storage is configured through named volumes with bind options:
- wp volume -> /home/oayyoub/data/wordpress
- db volume -> /home/oayyoub/data/mariadb

Service-level mounts:
- wordpress uses wp volume at /var/www/html
- nginx shares wp volume read path at /var/www/html
- mariadb uses db volume at /var/lib/mysql

Persistence behavior:
- Container recreation keeps data if volumes/data directories are preserved
- make fclean removes both Docker volumes and host data directories

## Source Layout Overview
- Makefile: project lifecycle commands
- srcs/docker-compose.yml: orchestration, networks, secrets, volumes
- srcs/requirements/mariadb:
  - Dockerfile
  - conf/50-server.cnf
  - tools/mariadb_start.sh
- srcs/requirements/wordpress:
  - Dockerfile
  - conf/www.conf
  - tools/wordpress_start.sh
- srcs/requirements/nginx:
  - Dockerfile
  - conf/default
  - tools/nginx_start.sh

## Notes for Development and Testing
- Domain in this project is set to oayyoub.42.fr (srcs/.env).
- For local testing, ensure /etc/hosts maps oayyoub.42.fr to 127.0.0.1.
- First startup initializes DB schema and WordPress; subsequent starts reuse persistent data.
