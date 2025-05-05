#!/bin/bash
set -e

# --- PARAMÈTRES À MODIFIER AU BESOIN ---
NBCLIENTS=3            # <== Changer selon besoin
BASE_NET=10.10         # Les réseaux seront 10.10.1, 10.10.2, ...
PROXY_IMG=my-reverseproxy
PROXY_CTR=reverseproxy
DB_ROOT_PWD="rootpass" # Mot de passe root mariadb (à changer pour prod)

declare -A DB_PASS
declare -A WEB_IP
declare -A DB_IP

# Vérification de l'existence du fichier index.php
SCRIPT_DIR=$(dirname "$0")
ORIGINAL_INDEX="${SCRIPT_DIR}/index.php"
if [[ ! -f "$ORIGINAL_INDEX" ]]; then
  echo "ERREUR : Le fichier index.php est introuvable dans $SCRIPT_DIR."
  echo "Veuillez créer un fichier index.php ou spécifier son chemin correct."
  exit 1
fi

# --- 1. CRÉATION DES RÉSEAUX LXC ---
for i in $(seq 1 $NBCLIENTS); do
  NETNAME="net$i"
  NETADDR="$BASE_NET.$i"
  lxc network create $NETNAME ipv4.address=${NETADDR}.1/24 ipv4.nat=true 2>/dev/null || true
done

# --- 2. CRÉATION DES CONTENEURS LXC webX et dbX ---
for i in $(seq 1 $NBCLIENTS); do
  WEBCTN="web$i"
  DBCTN="db$i"
  NET="net$i"
  IMG="ubuntu:22.04"
  echo " - $WEBCTN (Apache+PHP) sur $NET"
  lxc launch $IMG $WEBCTN -n $NET 2>/dev/null || echo "$WEBCTN existe déjà"
  echo " - $DBCTN (MariaDB) sur $NET"
  lxc launch $IMG $DBCTN -n $NET 2>/dev/null || echo "$DBCTN existe déjà"
done

# --- 2.5. CRÉATION DU DOSSIER PARTAGÉ ET MONTAGE ---
for i in $(seq 1 $NBCLIENTS); do
  SHARE_HOST="share_client$i"
  WEBCTN="web$i"
  mkdir -p "$(pwd)/$SHARE_HOST"
  chmod 777 "$(pwd)/$SHARE_HOST"
  # Retire l'ancien device si déjà existant
  lxc config device remove $WEBCTN sharedsrv 2>/dev/null || true
  lxc config device add $WEBCTN sharedsrv disk source="$(pwd)/$SHARE_HOST" path=/srv/share
done

# --- 3. RÉCUPÉRATION DES IPs ---
echo "Attente des IPs des conteneurs..."
sleep 5

for i in $(seq 1 $NBCLIENTS); do
  WEBCTN="web$i"
  DBCTN="db$i"
  WEB_IP[$i]=$(lxc list $WEBCTN -c 4 --format csv | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' || echo "IP_NON_TROUVEE")
  DB_IP[$i]=$(lxc list $DBCTN -c 4 --format csv | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' || echo "IP_NON_TROUVEE")
  
  if [[ "${WEB_IP[$i]}" == "IP_NON_TROUVEE" || "${DB_IP[$i]}" == "IP_NON_TROUVEE" ]]; then
    echo "ERREUR: Impossible d'obtenir l'IP pour $WEBCTN ou $DBCTN. Vérifiez l'état des conteneurs et des réseaux."
    exit 1
  fi
  
  echo " - Web$i: ${WEB_IP[$i]}"
  echo " - Db$i : ${DB_IP[$i]}"
done

# --- 4. INSTALLATION Apache2+PHP sur webX, MariaDB sur dbX ---
for i in $(seq 1 $NBCLIENTS); do
  WEBCTN="web$i"
  DBCTN="db$i"
  DBPASS=$(openssl rand -base64 32 | tr -d '=/+' | cut -c1-32)
  DB_PASS[$i]=$DBPASS
  DBNAME="client${i}"
  DBUSER="user${i}"
  WEBCTN_IP="${WEB_IP[$i]}"

  echo " [${WEBCTN}] Installation Apache2/PHP"
  lxc exec $WEBCTN -- bash -c 'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y apache2 php php-mysql'
  lxc exec $WEBCTN -- systemctl enable apache2
  lxc exec $WEBCTN -- systemctl start apache2

  echo " [${DBCTN}] Installation MariaDB"
  lxc exec $DBCTN -- bash -c 'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y mariadb-server'
  
  CONF_FILE="/etc/mysql/mariadb.conf.d/50-server.cnf"
  lxc exec $DBCTN -- test -f $CONF_FILE || (echo "Fichier $CONF_FILE non trouvé sur $DBCTN" && exit 1)
  lxc exec $DBCTN -- sed -i "s/^\(bind-address\s*=\s*\).*$/# \1/" $CONF_FILE
  lxc exec $DBCTN -- bash -c "echo -e \"\n[mysqld]\nbind-address = ${DB_IP[$i]}\" >> $CONF_FILE"
  
  lxc exec $DBCTN -- systemctl enable mariadb
  lxc exec $DBCTN -- systemctl restart mariadb
  echo " [${DBCTN}] Configuration MariaDB pour ${DBUSER}@${WEBCTN_IP}"
  lxc exec $DBCTN -- bash -c "
sleep 5
mysql -u root <<EOS
ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_ROOT_PWD';
FLUSH PRIVILEGES;
CREATE DATABASE IF NOT EXISTS $DBNAME;
CREATE USER IF NOT EXISTS '$DBUSER'@'${WEBCTN_IP}' IDENTIFIED BY '$DBPASS';
GRANT ALL PRIVILEGES ON $DBNAME.* TO '$DBUSER'@'${WEBCTN_IP}';
FLUSH PRIVILEGES;
EOS
" || echo "Echec configuration MariaDB pour $DBCTN"
done

# --- 5. DEPLOIEMENT index.php sur webX ---
for i in $(seq 1 $NBCLIENTS); do
  WEBCTN="web$i"
  TEMP_INDEX="${SCRIPT_DIR}/index_temp.php"

  echo "<?php \$num_clients = ${NBCLIENTS}; ?>" > "$TEMP_INDEX"
  cat "$ORIGINAL_INDEX" >> "$TEMP_INDEX"

  lxc file push "$TEMP_INDEX" ${WEBCTN}/var/www/html/index.php --mode 0644
  rm "$TEMP_INDEX"
  lxc exec $WEBCTN -- rm -f /var/www/html/index.html || true
done

# --- 6. GENERATION CONFIG NGINX et Dockerfile ---
mkdir -p nginx-reverse-proxy

cat > nginx-reverse-proxy/nginx.conf <<EOF
events {}

http {
    server {
        listen 80;
EOF

for i in $(seq 1 $NBCLIENTS); do
cat >> nginx-reverse-proxy/nginx.conf <<EOF
        location /server${i}/ {
            proxy_pass http://${WEB_IP[$i]}/;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }

EOF
done

cat >> nginx-reverse-proxy/nginx.conf <<EOF
    }
}
EOF

cat > nginx-reverse-proxy/Dockerfile <<EOF
FROM nginx:alpine
COPY nginx.conf /etc/nginx/nginx.conf
RUN rm /etc/nginx/conf.d/default.conf || true
EOF

# --- 7. CONSTRUCTION ET DÉPLOIEMENT DU REVERSE PROXY ---
cd nginx-reverse-proxy
docker build -t $PROXY_IMG .
docker rm -f $PROXY_CTR 2>/dev/null || true
docker run -d -p 80:80 --name $PROXY_CTR --network host $PROXY_IMG
cd ..

# --- 8. AFFICHAGE DES IDENTIFIANTS ET URLS ---
echo
echo "== DONE ! =="

echo
echo "== IDENTIFIANTS SECURISES MARIA-DB CLIENTS =="
printf "%-15s | %-10s | %-32s | %s\n" "Host" "Username" "Password" "Database"
printf "%s\n" "------------------------------------------------------------------------------------------------"
for i in $(seq 1 $NBCLIENTS); do
    printf "%-15s | %-10s | %-32s | %s\n" "${DB_IP[$i]}" "user$i" "${DB_PASS[$i]}" "client${i}"
done
echo "------------------------------------------------------------------------------------------------"
echo

echo "Accédez aux serveurs via le Nginx Reverse Proxy :"
IP_HOST=$(hostname -I | awk '{print $1}')
for i in $(seq 1 $NBCLIENTS); do
  echo "    http://${IP_HOST}/server${i}/"
done
echo