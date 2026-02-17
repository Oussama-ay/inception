FROM debian:bullseye

RUN apt-get update && apt-get install -y mariadb-server && rm -rf /var/lib/apt/lists/*

COPY ./conf/50-server.cnf /etc/mysql/mariadb.conf.d/
COPY ./tools/mariadb_start.sh /usr/local/bin/

RUN chmod +x /usr/local/bin/mariadb_start.sh

ENTRYPOINT ["mariadb_start.sh"]

CMD ["mysqld"]