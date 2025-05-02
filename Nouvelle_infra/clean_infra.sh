#!/bin/bash

# --------- PARAMÈTRES -----------
NBCLIENTS=3     # --> adapter si plus de clients !
PROXY_IMG=my-reverseproxy
PROXY_CTR=reverseproxy

# --------- 1. Suppression des conteneurs LXC ----------
echo "== 1. Suppression des conteneurs LXC (webX et dbX) =="
for i in $(seq 1 $NBCLIENTS); do
  for ctn in "web$i" "db$i"; do
    echo "- Arrêt et suppression de $ctn"
    lxc delete $ctn --force 2>/dev/null || echo "$ctn déjà supprimé"
  done
done

# --------- 2. Suppression des réseaux LXC ----------
echo "== 2. Suppression des réseaux LXC =="
for i in $(seq 1 $NBCLIENTS); do
  NET="net$i"
  echo "- Suppression de $NET"
  lxc network delete $NET 2>/dev/null || echo "$NET déjà supprimé"
done

# --------- 3. Suppression du reverse proxy Docker ----------
echo "== 3. Suppression du reverse proxy Docker =="
docker rm -f $PROXY_CTR 2>/dev/null || echo "$PROXY_CTR absent"
docker rmi $PROXY_IMG 2>/dev/null || echo "Image $PROXY_IMG absente"

# --------- 4. Nettoyage fichiers de conf NGINX/Docker ----------
echo "== 4. Nettoyage fichiers de conf NGINX/Docker =="
rm -rf nginx-reverse-proxy 2>/dev/null || true

echo "== Nettoyage terminé ! =="