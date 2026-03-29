*This project has been created as part of the 42 curriculum by oayyoub.*

# Inception

## Description
Inception is a containerized web stack built with Docker Compose. The project deploys three isolated services:
- NGINX (TLS termination and reverse proxy on port 443)
- WordPress with PHP-FPM (application layer)
- MariaDB (database layer)

The goal is to build and operate a production-like multi-service architecture with strict separation of concerns, persistent data, custom images, and secret management.

### Project Description: Docker, Sources, and Design Choices
This repository includes all required build sources to create the stack from scratch:
- Compose orchestration: srcs/docker-compose.yml
- Service images:
  - srcs/requirements/nginx
  - srcs/requirements/wordpress
  - srcs/requirements/mariadb
- Runtime secrets: secrets/
- Build and lifecycle commands: Makefile

Main design choices:
- Custom Dockerfiles based on debian:bullseye for each service
- Two bridge networks:
  - frontend-network: NGINX <-> WordPress
  - backend-network: WordPress <-> MariaDB
- Persistent storage with bind-backed named volumes:
  - /home/oayyoub/data/wordpress
  - /home/oayyoub/data/mariadb
- Docker secrets for sensitive values instead of plain environment variables
- Bootstrap scripts for first-run initialization:
  - TLS certificate generation
  - Database and user creation
  - WordPress installation and admin/user provisioning

### Comparison Notes
#### Virtual Machines vs Docker
- Virtual Machines virtualize full operating systems with a hypervisor; they are heavier in memory and startup time.
- Docker containers share the host kernel and package only app/runtime dependencies; they are lighter and faster to start.
- VMs are useful for stronger OS-level isolation; Docker is better for reproducible app deployments and fast iteration.

#### Secrets vs Environment Variables
- Environment variables are convenient, but often exposed in process metadata and compose files.
- Docker secrets are mounted as files at runtime (/run/secrets/...) and reduce accidental exposure in configuration.
- This project uses Docker secrets for DB and admin passwords, while non-sensitive settings remain in .env.

#### Docker Network vs Host Network
- Host network mode removes network namespace isolation and directly shares host networking.
- Bridge networks isolate traffic and provide service discovery by container name.
- This project uses bridge networks to segment traffic and keep services private except for HTTPS published by NGINX.

#### Docker Volumes vs Bind Mounts
- Docker-managed volumes are portable and abstract storage location.
- Bind mounts map explicit host paths and are easy to inspect/backup manually.
- This project uses named volumes backed by bind options to keep explicit persistence in /home/oayyoub/data while still using Compose volume semantics.

## Instructions
### Prerequisites
- Linux host with Docker Engine and Docker Compose plugin installed
- User with permission to run Docker commands
- Ability to edit /etc/hosts

### Configure Hostname Resolution
Add the project domain to your host file:
- 127.0.0.1 oayyoub.42.fr

### Build and Start
From repository root:
- make secretfiles
- make

What this does:
- Creates secret files in secrets/
- Creates persistent directories in /home/$USER/data
- Builds and starts the full stack in detached mode

### Stop, Clean, Rebuild
- Stop containers: make down
- Stop + prune images/cache: make clean
- Full cleanup (including volumes + data dirs): make fclean
- Rebuild from scratch: make re

### Access
- Website: https://oayyoub.42.fr
- WordPress admin: https://oayyoub.42.fr/wp-admin

## Resources
### Classic References
- Docker documentation: https://docs.docker.com/
- Docker Compose specification: https://docs.docker.com/compose/
- NGINX documentation: https://nginx.org/en/docs/
- MariaDB documentation: https://mariadb.com/kb/en/documentation/
- WordPress + WP-CLI:
  - https://wordpress.org/documentation/
  - https://developer.wordpress.org/cli/commands/

### AI Usage Disclosure
AI assistance was used as a documentation helper for:
- Structuring README sections to match validation requirements
- Rewording operational instructions for clarity
- Drafting comparison explanations (VM vs Docker, secrets vs env vars, etc.)

AI was not used to run containers, generate runtime outputs, or replace manual verification of the stack behavior.
