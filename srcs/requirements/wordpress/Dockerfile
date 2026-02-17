FROM debian:bullseye

RUN apt-get update && \
    apt-get -y install php7.4 php7.4-mysql php7.4-fpm wget && \
    rm -rf /var/lib/apt/lists/*

COPY ./conf/www.conf /etc/php/7.4/fpm/pool.d/www.conf
COPY ./tools/wordpress_start.sh /usr/local/bin/
COPY ./tools/wp-config.php /tmp/wp-config.php

RUN chmod +x /usr/local/bin/wordpress_start.sh && \
    mkdir -p /run/php

ENTRYPOINT ["wordpress_start.sh"]

CMD ["/usr/sbin/php-fpm7.4", "--nodaemonize"]