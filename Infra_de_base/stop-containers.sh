#!/bin/bash

docker stop db1 db2 db3 webserver1 webserver2 webserver3 reverse-proxy
docker rm db1 db2 db3 webserver1 webserver2 webserver3 reverse-proxy

docker network rm webserver1-network webserver2-network webserver3-network app-network

docker volume rm db1-data db2-data db3-data

echo "Tous les conteneurs, les réseaux et les volumes ont été supprimés."