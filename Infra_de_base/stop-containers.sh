#!/bin/bash

# Stop and remove the containers
docker stop db1 db2 db3 webserver1 webserver2 webserver3 reverse-proxy
docker rm db1 db2 db3 webserver1 webserver2 webserver3 reverse-proxy

# Remove the Docker networks
docker network rm webserver1-network webserver2-network webserver3-network app-network

# Optionally, remove the volumes (uncomment if needed)
# docker volume rm db1-data db2-data db3-data

echo "All containers and networks have been removed."