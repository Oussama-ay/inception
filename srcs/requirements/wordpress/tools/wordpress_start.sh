#!/bin/bash

if [ ! -f /var/www/html/wp-config.php ]; then
	wget -q https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -O /usr/local/bin/wp
	chmod +x /usr/local/bin/wp

	cd /var/www/html
	wp core download --allow-root

	WP_ADMIN_PASS=$(tr -d '\r\n' < /run/secrets/credentials)
	DB_PASS=$(tr -d '\r\n' < /run/secrets/db_password)

	wp config create --allow-root \
		--dbname="${MYSQL_DATABASE}" \
		--dbuser="${MYSQL_USER}" \
		--dbpass="${DB_PASS}" \
		--dbhost="mariadb:3306" \
		--dbcharset="utf8" \
		--skip-check
	wp config shuffle-salts --allow-root

	wp core install --allow-root \
		--url="${DOMAIN_NAME}" \
		--title="${WP_TITLE}" \
		--admin_user="${WP_ADMIN_LOGIN}" \
		--admin_password="${WP_ADMIN_PASS}" \
		--admin_email="${WP_ADMIN_EMAIL}"

	wp user create --allow-root "${WP_USER_LOGIN}" "${WP_USER_EMAIL}" \
		--user_pass="${DB_PASS}"

	chown -R www-data:www-data /var/www/html
fi

exec "$@"