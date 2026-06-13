all:
	@sudo mkdir -p /home/$(USER)/data/wordpress /home/$(USER)/data/mariadb
	@sudo docker compose -f ./srcs/docker-compose.yml up -d --build

testfiles:
	@echo db_pass123 > secrets/db_password.txt
	@echo root_pass123 > secrets/db_root_password.txt
	@echo boss12345 > secrets/credentials.txt
	@echo DOMAIN_NAME=oayyoub.42.fr > srcs/.env
	@echo >> srcs/.env
	@echo MYSQL_DATABASE=wordpress >> srcs/.env
	@echo MYSQL_USER=oayyoub >> srcs/.env
	@echo >> srcs/.env
	@echo WP_TITLE=inception >> srcs/.env
	@echo WP_ADMIN_LOGIN=boss >> srcs/.env
	@echo WP_ADMIN_EMAIL=boss@42.fr >> srcs/.env
	@echo WP_USER_LOGIN=oayyoub >> srcs/.env
	@echo WP_USER_EMAIL=oayyoub@42.fr >> srcs/.env

down:
	@sudo docker compose -f ./srcs/docker-compose.yml down 2>/dev/null || true

re: fclean all

clean: down
	@sudo docker system prune -af

fclean: down
	@sudo docker system prune -af --volumes
	@sudo rm -rf /home/$(USER)/data/wordpress /home/$(USER)/data/mariadb

.PHONY: all re down clean fclean