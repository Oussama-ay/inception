all:
	@mkdir -p /home/$(USER)/data/wordpress /home/$(USER)/data/mariadb
	@docker compose -f ./srcs/docker-compose.yml up -d --build

down:
	@docker compose -f ./srcs/docker-compose.yml down 2>/dev/null || true

re: fclean all

clean: down
	@docker system prune -af

fclean: down
	@docker system prune -af --volumes
	@sudo rm -rf /home/$(USER)/data/wordpress /home/$(USER)/data/mariadb

.PHONY: all re down clean fclean