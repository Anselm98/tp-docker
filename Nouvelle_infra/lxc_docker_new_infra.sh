#!/bin/bash

# Arrête le script en cas d'erreur
set -e

### Vars
LXC_IMG="ubuntu"
LXC_REL="22.04"
LXC_ARCH="amd64"
BASE_DIR="$(pwd)"

# Nom des containers
declare -a SERVERS=("webserver1" "webserver2" "webserver3")
declare -a DB_HOSTS=("db1" "db2" "db3")

# Fichier & dossiers nécessaires
PHP_SCRIPT="$BASE_DIR/db-test.php"
APACHE_CONF_DIR="$BASE_DIR/apache_conf"
REVERSE_PROXY_DIR="$BASE_DIR/reverse_proxy"

if ! [[ -f "$PHP_SCRIPT" ]]; then
  echo "ERREUR: Fichier db-test.php manquant à la racine."
  exit 1
fi
for f in apache2.conf server-name.conf security.conf; do
  if ! [[ -f "$APACHE_CONF_DIR/$f" ]]; then
    echo "ERREUR: Fichier $f manquant dans apache_conf/"
    exit 1
  fi
done
for f in Dockerfile nginx.conf; do
  if ! [[ -f "$REVERSE_PROXY_DIR/$f" ]]; then
    echo "ERREUR: Fichier $f manquant dans reverse_proxy/"
    exit 1
  fi
done

### Création des 3 containers LXC
for i in {0..2}; do
  echo
  echo "=== Création et configuration : ${SERVERS[$i]} ==="
  lxc-create -n "${SERVERS[$i]}" -t download -- --dist $LXC_IMG --release $LXC_REL --arch $LXC_ARCH

  lxc-start -n "${SERVERS[$i]}"
  # Patiente le temps du boot
  sleep 7

  lxc-attach -n "${SERVERS[$i]}" -- bash -c "apt update && apt install -y apache2 mariadb-server php php-mysqli"

  # Copie script PHP
  lxc-file push "$PHP_SCRIPT" "${SERVERS[$i]}/var/www/html/db-test.php"

  # Copie les configs Apache
  lxc-file push "$APACHE_CONF_DIR/apache2.conf"     "${SERVERS[$i]}/etc/apache2/apache2.conf"
  lxc-file push "$APACHE_CONF_DIR/security.conf"    "${SERVERS[$i]}/etc/apache2/conf-available/security.conf"
  lxc-file push "$APACHE_CONF_DIR/server-name.conf" "${SERVERS[$i]}/etc/apache2/conf-available/server-name.conf"

  lxc-attach -n "${SERVERS[$i]}" -- a2enconf security
  lxc-attach -n "${SERVERS[$i]}" -- a2enconf server-name

  # Ajout DB_HOST pour identification
  lxc-attach -n "${SERVERS[$i]}" -- bash -c "echo 'export DB_HOST=${DB_HOSTS[$i]}' >> /etc/apache2/envvars"

  # Démarrage Apache & MariaDB
  lxc-attach -n "${SERVERS[$i]}" -- systemctl restart apache2
  lxc-attach -n "${SERVERS[$i]}" -- systemctl enable apache2 mariadb

  echo "Container ${SERVERS[$i]} configuré"
done

# Récupère IP LXC
declare -a IPS=()
for i in {0..2}; do
  IPS[$i]=$(lxc-info -n "${SERVERS[$i]}" -iH | head -n1)
done

echo
echo "=== Résumé IP Containers ==="
for i in {0..2}; do
  echo "${SERVERS[$i]} => ${IPS[$i]}"
done

# Astuce /etc/hosts pour Docker-Compose (ou bridge direct Docker-LXC)
for i in {0..2}; do
  echo "${IPS[$i]}   ${SERVERS[$i]}"
done > $REVERSE_PROXY_DIR/hosts.lxc

### Préparation du reverse proxy Docker
echo
echo "=== Construction et lancement Reverse Proxy (Docker) ==="
cd "$REVERSE_PROXY_DIR"

# Mets à jour nginx.conf pour matcher les HN
sed -i '/upstream backend {/,/}/{/server /d}' nginx.conf
for i in {0..2}; do
  echo "    server ${SERVERS[$i]}:80;" >> nginx.conf
done

# Build Docker image
docker build -t my-nginx-reverse .

# Enlève ancien container
docker rm -f reverseproxy 2>/dev/null || true

# On utilise le network hôte Linux (facile) et le /etc/hosts mis à jour
docker run -d --name reverseproxy --restart unless-stopped \
  --add-host "${SERVERS[0]}:${IPS[0]}" \
  --add-host "${SERVERS[1]}:${IPS[1]}" \
  --add-host "${SERVERS[2]}:${IPS[2]}" \
  -p 80:80 my-nginx-reverse

cd "$BASE_DIR"

echo
echo "=== Installation terminée ===
    - Accès à http://IP_DE_VOTRE_HOTE/server1/ (ou /server2/ /server3/)
    - Pour les tests, MariaDB écoute en local sur chaque webserver.
    - docker ps   → pour voir reverse proxy (my-nginx-reverse)
    - Pour arrêter tout, lxc-stop -n ... et docker rm -f reverseproxy
"