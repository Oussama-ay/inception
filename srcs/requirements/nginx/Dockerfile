FROM debian:bullseye

RUN apt-get update && apt-get install -y nginx openssl && rm -rf /var/lib/apt/lists/*

COPY ./conf/default /etc/nginx/sites-enabled/default
COPY ./tools/nginx_start.sh /usr/local/bin/

RUN chmod +x /usr/local/bin/nginx_start.sh

ENTRYPOINT ["nginx_start.sh"]

CMD ["nginx", "-g", "daemon off;"]
