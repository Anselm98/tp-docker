#!/bin/bash
set -e

# --- PARAMÈTRES ---
BASE_NET=10.10         # Base des réseaux
PROXY_CTR=reverseproxy # Nom du conteneur reverse proxy Docker
IMG="ubuntu:22.04"     # Image LXC à utiliser
DB_ROOT_PWD="rootpass" # Mot de passe root MariaDB

# --- TROUVER LE NUMÉRO DU PROCHAIN SERVEUR ---
LAST_SERVER=$(lxc list | grep -oP 'web\K[0-9]+' | sort -n | tail -1)
NEXT_SERVER=$((LAST_SERVER + 1))

WEBCTN="web$NEXT_SERVER"
DBCTN="db$NEXT_SERVER"
NETNAME="net$NEXT_SERVER"
NETADDR="$BASE_NET.$NEXT_SERVER"
SHARE_HOST="share_client$NEXT_SERVER"

echo "Création du serveur $WEBCTN et de la base de données $DBCTN sur le réseau $NETNAME ($NETADDR.0/24)..."

# --- CRÉATION DU RÉSEAU LXC ---
lxc network create $NETNAME ipv4.address=${NETADDR}.1/24 ipv4.nat=true 2>/dev/null || true

# --- CRÉATION DES CONTENEURS LXC ---
lxc launch $IMG $WEBCTN -n $NETNAME 2>/dev/null || echo "$WEBCTN existe déjà"
lxc launch $IMG $DBCTN -n $NETNAME 2>/dev/null || echo "$DBCTN existe déjà"

# --- CONFIGURATION DE LA BASE DE DONNÉES ---
echo "Configuration de la base de données sur $DBCTN..."
lxc exec $DBCTN -- apt update
lxc exec $DBCTN -- apt install -y mariadb-server
lxc exec $DBCTN -- bash -c "mysql -u root -e \"ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_ROOT_PWD'; FLUSH PRIVILEGES;\""
lxc exec $DBCTN -- bash -c "mysql -u root -p$DB_ROOT_PWD -e \"CREATE DATABASE webserver${NEXT_SERVER}db;\""

# --- CONFIGURATION DU SERVEUR WEB ---
echo "Configuration du serveur web sur $WEBCTN..."
lxc exec $WEBCTN -- apt update
lxc exec $WEBCTN -- apt install -y apache2 php libapache2-mod-php php-mysql
lxc exec $WEBCTN -- bash -c "echo '<?php phpinfo(); ?>' > /var/www/html/index.php"
WEB_IP=$(lxc list $WEBCTN -c 4 | awk '!/IPV4/{ if ( $2 ~ /^[0-9]/ ) print $2 }')

# --- CRÉATION DU DOSSIER PARTAGÉ ET MONTAGE ---
echo "Création du dossier partagé entre l'hôte et $WEBCTN..."
mkdir -p "$(pwd)/$SHARE_HOST"
lxc config device remove $WEBCTN sharedsrv 2>/dev/null || true
lxc config device add $WEBCTN sharedsrv disk source="$(pwd)/$SHARE_HOST" path=/srv/share

# --- MISE À JOUR DU REVERSE PROXY ---
echo "Mise à jour du reverse proxy pour inclure $WEBCTN ($WEB_IP)..."

# Copier le fichier nginx.conf depuis le conteneur vers le système local
docker cp $PROXY_CTR:/etc/nginx/nginx.conf nginx.conf

# Supprimer les deux dernières lignes (les accolades fermantes)
sed -i '$d' nginx.conf
sed -i '$d' nginx.conf

# Ajouter le nouveau bloc location et les accolades fermantes à la fin du fichier
cat <<EOF >> nginx.conf
        location /server$NEXT_SERVER/ {
            proxy_pass http://$WEB_IP/;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }
    }
}
EOF

# Copier le fichier nginx.conf mis à jour dans le conteneur
docker cp nginx.conf $PROXY_CTR:/etc/nginx/nginx.conf

# Recharger la configuration Nginx dans le conteneur
docker exec $PROXY_CTR nginx -s reload

# Supprimer le fichier temporaire local
rm nginx.conf

echo "Le reverse proxy a été mis à jour pour inclure $WEBCTN."
echo "Le serveur $WEBCTN et la base de données $DBCTN ont été créés et configurés."
echo "Le dossier partagé $(pwd)/$SHARE_HOST a été monté sur $WEBCTN à /srv/share."