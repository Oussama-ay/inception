# USER_DOC

## Services Provided by the Stack
This project runs three services:
- NGINX: HTTPS entrypoint (port 443), serves and proxies the website
- WordPress (PHP-FPM): CMS application
- MariaDB: database used by WordPress

Traffic flow:
- Client -> NGINX (443/TLS)
- NGINX -> WordPress (FastCGI, internal)
- WordPress -> MariaDB (internal)

## Start and Stop the Project
From the repository root:
- Create/update local secret files: make secretfiles
- Build and start all services: make
- Stop all services: make down

Cleanup options:
- Remove stopped resources and unused images: make clean
- Full cleanup including volumes and persistent data: make fclean

## Access the Website and Administration Panel
1. Ensure local hostname mapping exists:
   - 127.0.0.1 oayyoub.42.fr in /etc/hosts
2. Open in a browser:
   - Website: https://oayyoub.42.fr
   - Admin panel: https://oayyoub.42.fr/wp-admin

If browser warns about certificate trust, accept the local self-signed certificate for development use.

## Locate and Manage Credentials
Credential files are stored in:
- secrets/db_password.txt
- secrets/db_root_password.txt
- secrets/credentials.txt

How they are used:
- db_password.txt: WordPress DB user password and DB user creation in MariaDB
- db_root_password.txt: MariaDB root password setup
- credentials.txt: WordPress admin password during first installation

To rotate credentials:
1. Update the files in secrets/
2. Recreate the stack from scratch to reinitialize bootstrap state:
   - make fclean
   - make

## Check That Services Are Running Correctly
Container status:
- sudo docker compose -f ./srcs/docker-compose.yml ps

Service logs:
- sudo docker compose -f ./srcs/docker-compose.yml logs nginx
- sudo docker compose -f ./srcs/docker-compose.yml logs wordpress
- sudo docker compose -f ./srcs/docker-compose.yml logs mariadb

Quick health checks:
- HTTPS endpoint responds: open https://oayyoub.42.fr
- WordPress admin loads: open https://oayyoub.42.fr/wp-admin
- All containers show as Up in compose ps output

Persistent data locations:
- /home/oayyoub/data/wordpress
- /home/oayyoub/data/mariadb
