#!/bin/bash

# Variables (adapter à ton infra si modifiées)
C1=web1; C2=web2; C3=web3
N1=net1; N2=net2; N3=net3
PROXY_IMG=my-reverseproxy
PROXY_CTR=reverseproxy

echo "== 1. Suppression des conteneurs LXC =="
for c in $C1 $C2 $C3; do
  echo "- Arrêt et suppression de $c"
  lxc delete $c --force 2>/dev/null || echo "$c déjà supprimé"
done

echo "== 2. Suppression des réseaux LXC =="
for n in $N1 $N2 $N3; do
  echo "- Suppression de $n"
  lxc network delete $n 2>/dev/null || echo "$n déjà supprimé"
done

echo "== 3. Suppression du reverse proxy Docker =="
docker rm -f $PROXY_CTR 2>/dev/null || echo "$PROXY_CTR absent"
docker rmi $PROXY_IMG 2>/dev/null || echo "Image $PROXY_IMG absente"

echo "== 4. Nettoyage fichiers de conf NGINX/Docker =="
rm -rf nginx-reverse-proxy 2>/dev/null || true

echo "== Nettoyage terminé ! =="
