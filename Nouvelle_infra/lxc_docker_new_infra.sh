#!/bin/bash
set -e

# --- PARAMETRES A MODIFIER AU BESOIN ---
NBCLIENTS=3            # <== Change selon besoin
BASE_NET=10.10         # Les réseaux seront 10.10.1, 10.10.2, ...
PROXY_IMG=my-reverseproxy
PROXY_CTR=reverseproxy
DB_ROOT_PWD="rootpass" # mot de passe root mariadb (simple ! à changer en prod)

# --- 1. CREATION DES RESEAUX LXC ---
for i in $(seq 1 $NBCLIENTS); do
  NETNAME="net$i"
  NETADDR="$BASE_NET.$i"
  lxc network create $NETNAME ipv4.address=${NETADDR}.1/24 ipv4.nat=true 2>/dev/null || true
done

# --- 2. CREATION DES CONTENEURS LXC webX et dbX ---
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

# --- 3. RECUPERATION DES IPs ---
# Attendre que les conteneurs obtiennent une IP
echo "Attente des IPs des conteneurs..."
sleep 5 # Simple pause, une boucle de vérification serait plus robuste

declare -A WEB_IP
declare -A DB_IP
for i in $(seq 1 $NBCLIENTS); do
  WEBCTN="web$i"
  DBCTN="db$i"
  # Tentative robuste pour obtenir l'IP v4 sur l'interface eth0
  WEB_IP[$i]=$(lxc list $WEBCTN -c 4 --format csv | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' || echo "IP_NON_TROUVEE")
  DB_IP[$i]=$(lxc list $DBCTN -c 4 --format csv | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' || echo "IP_NON_TROUVEE")

  # Vérifier si l'IP a été trouvée
  if [[ "${WEB_IP[$i]}" == "IP_NON_TROUVEE" || "${DB_IP[$i]}" == "IP_NON_TROUVEE" ]]; then
    echo "ERREUR: Impossible d'obtenir l'IP pour $WEBCTN ou $DBCTN. Vérifiez l'état des conteneurs et des réseaux."
    exit 1
  fi
  echo " - Web$i: ${WEB_IP[$i]}"
  echo " - Db$i : ${DB_IP[$i]}"
done


# --- 4. INSTALLATION Apache2+PHP sur webX, MariaDB server sur dbX ---
for i in $(seq 1 $NBCLIENTS); do
  WEBCTN="web$i"
  DBCTN="db$i"
  DBPASS="pass${i}web"
  DBNAME="client${i}"
  DBUSER="user${i}"
  WEBCTN_IP="${WEB_IP[$i]}" # Récupérer l'IP spécifique pour le GRANT

  echo " [${WEBCTN}] Installation Apache2/PHP"
  lxc exec $WEBCTN -- bash -c 'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y apache2 php php-mysql'
  # Configurer bind-address pour Apache si nécessaire (généralement écoute sur 0.0.0.0 par défaut)
  lxc exec $WEBCTN -- systemctl enable apache2
  lxc exec $WEBCTN -- systemctl start apache2

  echo " [${DBCTN}] Installation MariaDB"
  lxc exec $DBCTN -- bash -c 'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y mariadb-server'

  # --- Configurer MariaDB pour écouter sur son IP réseau ---
  CONF_FILE="/etc/mysql/mariadb.conf.d/50-server.cnf"
  # S'assurer que le fichier de conf existe avant de le modifier
  lxc exec $DBCTN -- test -f $CONF_FILE || (echo "Fichier $CONF_FILE non trouvé sur $DBCTN" && exit 1)
  # Commenter l'ancien bind-address s'il existe et ajouter le nouveau
  lxc exec $DBCTN -- sed -i "s/^\(bind-address\s*=\s*\).*$/# \1/" $CONF_FILE
  lxc exec $DBCTN -- bash -c "echo -e \"\n[mysqld]\nbind-address = ${DB_IP[$i]}\" >> $CONF_FILE"
  # Alternative: écouter sur toutes les interfaces (moins spécifique mais fonctionne si l'IP change)
  # lxc exec $DBCTN -- sed -i "s/^\(bind-address\s*=\s*\).*$/bind-address = 0.0.0.0/" $CONF_FILE


  lxc exec $DBCTN -- systemctl enable mariadb
  lxc exec $DBCTN -- systemctl restart mariadb # Restart pour prendre en compte bind-address

  # Sécuriser MariaDB et créer BDD & user (GRANT spécifique à l'IP de WEBCTN)
  echo " [${DBCTN}] Configuration MariaDB pour ${DBUSER}@${WEBCTN_IP}"
  lxc exec $DBCTN -- bash -c "
# Attendre que MariaDB soit prêt après le redémarrage
sleep 5
mysql -u root <<EOS
ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_ROOT_PWD';
FLUSH PRIVILEGES;
CREATE DATABASE IF NOT EXISTS $DBNAME;
CREATE USER IF NOT EXISTS '$DBUSER'@'${WEBCTN_IP}' IDENTIFIED BY '$DBPASS';
GRANT ALL PRIVILEGES ON $DBNAME.* TO '$DBUSER'@'${WEBCTN_IP}';
FLUSH PRIVILEGES;
EOS
" || echo "Echec configuration MariaDB pour $DBCTN (peut être normal si déjà fait)"


done

# --- 5. DEPLOIEMENT index.php sur webX (utilise l'IP de dbX pour la connexion) ---
for i in $(seq 1 $NBCLIENTS); do
  WEBCTN="web$i"
  # Note: Le script index.php devra utiliser l'IP de DB_IP[$i] pour se connecter
  DBHOST_IP="${DB_IP[$i]}" # IP que le PHP doit utiliser pour joindre la BDD

  # Le script index.php actuel demande les infos dans un formulaire.
  # Si on voulait pré-configurer la connexion DANS index.php, il faudrait le modifier ici.
  # Pour l'instant, on pousse le même index.php générique.
  SCRIPT_DIR=$(dirname "$0")
  lxc file push "${SCRIPT_DIR}/index.php" ${WEBCTN}/var/www/html/index.php --mode 0644
  lxc exec $WEBCTN -- rm -f /var/www/html/index.html || true

  # Facultatif: Modifier index.php pour pré-remplir le champ host ?
  # lxc exec $WEBCTN -- sed -i "s/\$host = isset(\$_POST\['host'\]) ? \$_POST\['host'\] : '';/\$host = isset(\$_POST\['host'\]) ? \$_POST\['host'\] : '${DBHOST_IP}';/" /var/www/html/index.php
done

# --- 6. GENERATION CONFIG NGINX et Dockerfile ---
mkdir -p nginx-reverse-proxy

# Start base nginx.conf
cat > nginx-reverse-proxy/nginx.conf <<EOF
events {}

http {
    server {
        listen 80;

EOF

# Add location block for each web server dynamically
for i in $(seq 1 $NBCLIENTS); do
# Utiliser WEB_IP ici car Nginx tourne sur l'hôte et doit joindre les webX via leur IP
cat >> nginx-reverse-proxy/nginx.conf <<EOF
        location /server${i}/ {
            proxy_pass http://${WEB_IP[$i]}/; # Utilise l'IP de webX
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }

EOF
done

# Close server and http blocks
cat >> nginx-reverse-proxy/nginx.conf <<EOF
    }
}
EOF

cat > nginx-reverse-proxy/Dockerfile <<EOF
FROM nginx:alpine
COPY nginx.conf /etc/nginx/nginx.conf
RUN rm /etc/nginx/conf.d/default.conf || true
EOF

# --- 7. BUILD ET RUN NGINX ---
cd nginx-reverse-proxy
docker build -t $PROXY_IMG .
docker rm -f $PROXY_CTR 2>/dev/null || true
# Lancer Nginx en mode host pour qu'il puisse atteindre les IPs des conteneurs LXC
docker run -d -p 80:80 --name $PROXY_CTR --network host $PROXY_IMG
cd ..

echo
echo "== DONE ! =="
# Commenter ou supprimer la partie /etc/hosts car on utilise Nginx comme point d'entrée
# echo "Ajoute ceci à /etc/hosts pour tester (sur ta machine/dans une VM cliente) :"
# IP_HOST=$(hostname -I | awk '{print $1}')
# HOSTS=""
# for i in $(seq 1 $NBCLIENTS); do
#  HOSTS="$HOSTS web${i}.local"
# done
# echo "$IP_HOST $HOSTS"
echo
echo "Accédez aux serveurs via le Nginx Reverse Proxy:"
IP_HOST=$(hostname -I | awk '{print $1}') # IP de la machine hôte
for i in $(seq 1 $NBCLIENTS); do
  echo "    http://${IP_HOST}/server${i}/"
done
echo
echo "*** Utilisez le formulaire pour tester la connexion à la BDD correspondante ***"
echo "    (Ex: pour server1/, utiliser l'IP de db1: ${DB_IP[1]}, user1, pass1web, client1)"