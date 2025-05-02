#!/bin/bash

# --------- PARAMÈTRES -----------
# NBCLIENTS removed
PROXY_IMG=my-reverseproxy
PROXY_CTR=reverseproxy

# --------- 1. Suppression des conteneurs LXC ----------
echo "== 1. Suppression de TOUS les conteneurs LXC =="
# Get all container names (running or stopped)
CONTAINERS=$(lxc list --format=csv -c n)
if [ -z "$CONTAINERS" ]; then
  echo "- Aucun conteneur LXC à supprimer."
else
  # Iterate and delete each container
  echo "$CONTAINERS" | while IFS= read -r ctn; do
    if [ -n "$ctn" ]; then # Ensure the line is not empty
        echo "- Arrêt et suppression de $ctn"
        lxc delete "$ctn" --force
    fi
  done
fi


# --------- 2. Suppression des réseaux LXC ----------
echo "== 2. Suppression de TOUS les réseaux LXC =="
# Get all network names
NETWORKS=$(lxc network list --format=csv -c n)
if [ -z "$NETWORKS" ]; then
  echo "- Aucun réseau LXC à supprimer."
else
  # Iterate and delete each network
  echo "$NETWORKS" | while IFS= read -r net; do
    if [ -n "$net" ]; then # Ensure the line is not empty
        # Avoid deleting managed networks like lxdbr0 or docker0 if necessary
        # Add specific checks here if needed, e.g.:
        # if [[ "$net" == "lxdbr0" || "$net" == "docker0" ]]; then
        #   echo "- Conservation du réseau managé $net"
        #   continue
        # fi
        echo "- Suppression de $net"
        lxc network delete "$net" || echo "Échec de la suppression de $net (peut être utilisé ou managé?)"
    fi
  done
fi

# --------- 3. Suppression du reverse proxy Docker ----------
echo "== 3. Suppression du reverse proxy Docker =="
# Check if docker is installed/running before attempting commands
if command -v docker &> /dev/null; then
    docker rm -f $PROXY_CTR 2>/dev/null || echo "Conteneur Docker $PROXY_CTR absent ou déjà supprimé."
    docker rmi $PROXY_IMG 2>/dev/null || echo "Image Docker $PROXY_IMG absente ou déjà supprimée."
else
    echo "Docker non trouvé. Saut de la suppression du reverse proxy."
fi

echo "== Nettoyage terminé ! =="