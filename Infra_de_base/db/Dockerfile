FROM mariadb:latest

ENV MARIADB_ROOT_PASSWORD=michel
ENV MARIADB_DATABASE=webserverdb

COPY init-db.sh /docker-entrypoint-initdb.d/ 

EXPOSE 3306