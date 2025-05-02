#!/bin/bash

docker ps -a --filter "name=db" --filter "name=webserver" --filter "name=reverse-proxy" --format "{{.Names}}" | xargs -r docker stop
docker ps -a --filter "name=db" --filter "name=webserver" --filter "name=reverse-proxy" --format "{{.Names}}" | xargs -r docker rm

docker network ls --filter "name=webserver" --filter "name=app-network" --format "{{.Name}}" | xargs -r docker network rm

docker volume ls --filter "name=db" --format "{{.Name}}" | xargs -r docker volume rm

echo "Tous les conteneurs, réseaux et volumes correspondants ont été supprimés."