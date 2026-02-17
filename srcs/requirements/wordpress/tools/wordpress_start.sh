#!/bin/bash

sed -i "s|listen = /run/php/php7.4-fpm.sock|listen = 9000|" /etc/php/7.4/fpm/pool.d/www.conf
mkdir -p /run/php

if [ ! -f /var/www/html/wp-config.php ]; then
	wget -q https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -O /usr/local/bin/wp
	chmod +x /usr/local/bin/wp

	cd /var/www/html
	wp core download --allow-root
	cp /tmp/wp-config.php /var/www/html/wp-config.php

	WP_ADMIN_PASS=$(cat /run/secrets/credentials)
	DB_PASS=$(cat /run/secrets/db_password)

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