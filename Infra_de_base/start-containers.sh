#!/bin/bash

docker network create webserver1-network
docker network create webserver2-network
docker network create webserver3-network
docker network create app-network

docker build -t my-mariadb ./db

docker run -d --name db1 --network webserver1-network -e MARIADB_ROOT_PASSWORD=michel -e DB_INSTANCE=db1 -v db1-data:/var/lib/mysql my-mariadb
docker run -d --name db2 --network webserver2-network -e MARIADB_ROOT_PASSWORD=michel -e DB_INSTANCE=db2 -v db2-data:/var/lib/mysql my-mariadb
docker run -d --name db3 --network webserver3-network -e MARIADB_ROOT_PASSWORD=michel -e DB_INSTANCE=db3 -v db3-data:/var/lib/mysql my-mariadb

docker build -t my-webserver ./web

docker run -d --name webserver1 --network webserver1-network -e DB_HOST=db1 -e DB_NAME=webserver1db -p 8081:80 my-webserver
docker run -d --name webserver2 --network webserver2-network -e DB_HOST=db2 -e DB_NAME=webserver2db -p 8082:80 my-webserver
docker run -d --name webserver3 --network webserver3-network -e DB_HOST=db3 -e DB_NAME=webserver3db -p 8083:80 my-webserver

docker build -t my-reverse-proxy ./reverse_proxy

docker run -d --name reverse-proxy --network app-network \
  --network webserver1-network \
  --network webserver2-network \
  --network webserver3-network \
  -p 80:80 my-reverse-proxy

echo "Les conteneurs ont bien été déployés."