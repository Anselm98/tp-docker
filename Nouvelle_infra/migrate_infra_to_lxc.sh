#!/bin/bash
set -e

# --- PARAMETRES ---
# NBCLIENTS=3              # Nombre de clients/serveurs à migrer (doit correspondre à l'infra Docker)
BASE_NET=10.10           # Les réseaux LXC seront 10.10.1, 10.10.2, ...
PROXY_IMG=my-reverseproxy-migrated
PROXY_CTR=reverseproxy-migrated
OLD_DB_ROOT_PWD="michel" # Mot de passe root des BDD MariaDB Docker existantes
NEW_DB_ROOT_PWD="michel" # Mot de passe root pour les nouvelles BDD MariaDB LXC (peut être changé)
DUMP_DIR="/tmp/db_dumps_migration" # Répertoire temporaire pour les dumps SQL

declare -A WEB_IP
declare -A DB_IP
declare -A DBNAME # Stocker les noms des BDD Docker

# --- 0. PREPARATION & DUMP DES BASES DOCKER ---
echo "--- Préparation de la migration ---"
mkdir -p "$DUMP_DIR"
echo "Nettoyage du répertoire de dump: $DUMP_DIR"
rm -f ${DUMP_DIR}/*.sql

echo "Dump des bases de données depuis les conteneurs Docker..."
for i in $(seq 1 3); do
  DOCKER_DB_CTR="db$i"
  DOCKER_DB_NAME="webserver${i}db" # Nom de la BDD dans l'infra Docker
  DBNAME[$i]=$DOCKER_DB_NAME
  DUMP_FILE="${DUMP_DIR}/dump_${DOCKER_DB_CTR}.sql"
  echo " - Dump de la base '$DOCKER_DB_NAME' depuis '$DOCKER_DB_CTR' vers '$DUMP_FILE'"
  # Note: Suppose que toutes les BDD sont accessibles avec le même mot de passe root
  docker exec $DOCKER_DB_CTR sh -c "mysqldump -u root -p'$OLD_DB_ROOT_PWD' --databases $DOCKER_DB_NAME" > "$DUMP_FILE"
  if [ $? -ne 0 ]; then
    echo "ERREUR: Le dump de la base $DOCKER_DB_NAME depuis $DOCKER_DB_CTR a échoué."
    exit 1
  fi
done
echo "Dump terminé."

# --- 1. ARRET ET SUPPRESSION DE L'ANCIENNE INFRA DOCKER ---
echo "--- Arrêt et suppression de l'ancienne infrastructure Docker ---"
# Assurez-vous que le chemin vers le script est correct
STOP_SCRIPT_PATH="../Infra_de_base/stop-containers.sh"
if [ -f "$STOP_SCRIPT_PATH" ]; then
  echo "Exécution de $STOP_SCRIPT_PATH..."
  bash "$STOP_SCRIPT_PATH"
else
  echo "ATTENTION: Script $STOP_SCRIPT_PATH non trouvé. Veuillez arrêter/supprimer manuellement l'ancienne infra Docker."
  # Optionnellement, ajouter ici les commandes docker stop/rm/network rm/volume rm directes si nécessaire
  # exit 1 # Décommenter pour forcer l'arrêt si le script manque
fi

# --- 2. CREATION DES RESEAUX LXC ---
echo "--- Création des réseaux LXC ---"
for i in $(seq 1 3); do
  NETNAME="net$i"
  NETADDR="$BASE_NET.$i"
  echo " - Création réseau $NETNAME (${NETADDR}.1/24)"
  lxc network create $NETNAME ipv4.address=${NETADDR}.1/24 ipv4.nat=true 2>/dev/null || echo "Réseau $NETNAME existe déjà ou erreur."
done

# --- 3. CREATION DES CONTENEURS LXC webX et dbX ---
echo "--- Création des conteneurs LXC ---"
for i in $(seq 1 3); do
  WEBCTN="web$i"
  DBCTN="db$i"
  NET="net$i"
  IMG="ubuntu:22.04"
  echo " - $WEBCTN (Apache+PHP) sur $NET"
  lxc launch $IMG $WEBCTN -n $NET 2>/dev/null || echo "$WEBCTN existe déjà"
  echo " - $DBCTN (MariaDB) sur $NET"
  lxc launch $IMG $DBCTN -n $NET 2>/dev/null || echo "$DBCTN existe déjà"
done

# --- 4. RECUPERATION DES IPs ---
echo "--- Récupération des IPs des conteneurs LXC ---"
echo "Attente des IPs..."
sleep 10 # Augmenté pour plus de fiabilité

for i in $(seq 1 3); do
  WEBCTN="web$i"
  DBCTN="db$i"
  WEB_IP_RAW=$(lxc list $WEBCTN -c 4 --format csv)
  DB_IP_RAW=$(lxc list $DBCTN -c 4 --format csv)
  
  # Amélioration de l'extraction d'IP pour gérer les cas multi-IP/IPv6
  WEB_IP[$i]=$(echo "$WEB_IP_RAW" | grep -oE "$BASE_NET\.$i\.[0-9]+" | head -n 1)
  DB_IP[$i]=$(echo "$DB_IP_RAW" | grep -oE "$BASE_NET\.$i\.[0-9]+" | head -n 1)
  
  if [[ -z "${WEB_IP[$i]}" || -z "${DB_IP[$i]}" ]]; then
    echo "ERREUR: Impossible d'obtenir l'IP pour $WEBCTN (raw: $WEB_IP_RAW) ou $DBCTN (raw: $DB_IP_RAW) sur le réseau attendu."
    echo "Vérifiez l'état des conteneurs et des réseaux LXC ($BASE_NET.$i.x)."
    exit 1
  fi
  
  echo " - Web$i: ${WEB_IP[$i]}"
  echo " - Db$i : ${DB_IP[$i]}"
done

# --- 5. INSTALLATION Apache2+PHP sur webX, MariaDB server sur dbX ---
echo "--- Installation des services ---"
for i in $(seq 1 3); do
  WEBCTN="web$i"
  DBCTN="db$i"
  WEBCTN_IP="${WEB_IP[$i]}"
  DBCTN_IP="${DB_IP[$i]}"
  DB_TO_IMPORT="${DBNAME[$i]}" # Nom de la BDD à importer (issue du dump)

  echo " [${WEBCTN}] Installation Apache2/PHP"
  lxc exec $WEBCTN -- bash -c 'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y apache2 php php-mysql'
  lxc exec $WEBCTN -- systemctl enable apache2
  lxc exec $WEBCTN -- systemctl start apache2

  echo " [${DBCTN}] Installation MariaDB"
  lxc exec $DBCTN -- bash -c 'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y mariadb-server pv' # Ajout de pv pour la progression

  CONF_FILE="/etc/mysql/mariadb.conf.d/50-server.cnf"
  echo " [${DBCTN}] Configuration bind-address MariaDB sur $DBCTN_IP"
  lxc exec $DBCTN -- test -f $CONF_FILE || (echo "Fichier $CONF_FILE non trouvé sur $DBCTN" && exit 1)
  # Commente la ligne bind-address existante (plus robuste que remplacer par #)
  lxc exec $DBCTN -- sed -i -E 's/^(bind-address\s*=.*)/#\1/' $CONF_FILE
  # Ajoute la nouvelle directive bind-address dans la section [mysqld]
  lxc exec $DBCTN -- bash -c "sed -i '/\\[mysqld\\]/a bind-address = ${DBCTN_IP}' $CONF_FILE"

  lxc exec $DBCTN -- systemctl enable mariadb
  lxc exec $DBCTN -- systemctl restart mariadb
  echo " [${DBCTN}] Attente démarrage MariaDB..."
  sleep 5
  
  echo " [${DBCTN}] Configuration initiale et sécurisation MariaDB (root password)"
  lxc exec $DBCTN -- mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$NEW_DB_ROOT_PWD'; FLUSH PRIVILEGES;" || echo "Echec configuration mot de passe root pour $DBCTN (peut-être déjà défini)"

  # --- 6. IMPORT DES DONNEES DANS LES NOUVELLES BDD LXC ---
  echo " [${DBCTN}] Import du dump ${DUMP_DIR}/dump_${DBCTN}.sql (Base: $DB_TO_IMPORT)"
  DUMP_FILE_PATH_IN_HOST="${DUMP_DIR}/dump_${DBCTN}.sql"
  DUMP_FILE_PATH_IN_GUEST="/tmp/dump_to_import.sql"
  
  lxc file push "$DUMP_FILE_PATH_IN_HOST" "${DBCTN}${DUMP_FILE_PATH_IN_GUEST}"
  if [ $? -ne 0 ]; then
      echo "ERREUR: Echec du transfert du dump vers $DBCTN."
      exit 1
  fi
  
  # Utilisation de pv pour voir la progression de l'import
  lxc exec $DBCTN -- bash -c "pv $DUMP_FILE_PATH_IN_GUEST | mysql -u root -p'$NEW_DB_ROOT_PWD'"
  if [ $? -ne 0 ]; then
      echo "ERREUR: Echec de l'import du dump dans $DBCTN pour la base $DB_TO_IMPORT."
      # Ne pas quitter, essayer les autres imports
  else
      echo " [${DBCTN}] Import terminé avec succès."
  fi
  lxc exec $DBCTN -- rm -f "$DUMP_FILE_PATH_IN_GUEST"

  # Note: On suppose que le dump contient les CREATE DATABASE et les CREATE USER/GRANT nécessaires.
  # Si ce n'est pas le cas, ou si les IPs des webservers ont changé, il faudra recréer/adapter les utilisateurs et les grants.
  # Exemple pour adapter le grant si l'IP du webserver a changé (à faire après import):
  # OLD_WEB_IP_MASK="%" # ou l'ancienne IP/subnet si connue
  # DOCKER_USER="user${i}" # Nom d'utilisateur de l'ancienne infra s'il est différent de root
  # DOCKER_PASS="..." # Ancien mot de passe utilisateur
  # echo " [${DBCTN}] Adaptation des grants pour ${DOCKER_USER}@${WEBCTN_IP} sur base $DB_TO_IMPORT"
  # lxc exec $DBCTN -- mysql -u root -p'$NEW_DB_ROOT_PWD' -e "CREATE USER IF NOT EXISTS '$DOCKER_USER'@'$WEBCTN_IP' IDENTIFIED BY '$DOCKER_PASS'; GRANT ALL PRIVILEGES ON $DB_TO_IMPORT.* TO '$DOCKER_USER'@'$WEBCTN_IP'; FLUSH PRIVILEGES;" || echo "WARN: Echec adaptation grants pour $DBCTN"

done

# --- 7. DEPLOIEMENT index.php sur webX ---
echo "--- Déploiement application web (index.php) ---"
for i in $(seq 1 3); do
  WEBCTN="web$i"
  # Assurez-vous que index.php existe dans le même répertoire que ce script
  SCRIPT_DIR=$(dirname "$(readlink -f "$0")") # Chemin absolu du script
  ORIGINAL_INDEX="${SCRIPT_DIR}/index.php"
  TEMP_INDEX="${SCRIPT_DIR}/index_temp.php"

  if [ ! -f "$ORIGINAL_INDEX" ]; then
      echo "ERREUR: Fichier index.php non trouvé dans $SCRIPT_DIR. Impossible de déployer l'application web."
      exit 1
  fi
  
  # Préfixer le fichier index.php avec le nombre de clients
  echo "<?php \$num_clients = 3; ?>" > "$TEMP_INDEX"
  cat "$ORIGINAL_INDEX" >> "$TEMP_INDEX"
  
  echo " [${WEBCTN}] Push index.php"
  lxc file push "$TEMP_INDEX" ${WEBCTN}/var/www/html/index.php --mode 0644
  rm "$TEMP_INDEX"
  lxc exec $WEBCTN -- rm -f /var/www/html/index.html 2>/dev/null || true # Supprime l'index Apache par défaut
  
  # IMPORTANT: Assurez-vous que index.php utilise les bons identifiants BDD.
  # Il devrait se connecter à DB_IP[$i] avec le root/$NEW_DB_ROOT_PWD ou les utilisateurs/mots de passe migrés via le dump.
done

# --- 8. GENERATION CONFIG NGINX et Dockerfile pour le Reverse Proxy ---
echo "--- Configuration et lancement du Reverse Proxy Nginx (Docker) ---"
NGINX_DIR="nginx-reverse-proxy-migrated"
mkdir -p $NGINX_DIR

echo "Génération de $NGINX_DIR/nginx.conf..."
cat > ${NGINX_DIR}/nginx.conf <<EOF
events {}

http {
    server {
        listen 80;
        server_name _; # Écoute sur toutes les IPs/hostnames

EOF

for i in $(seq 1 3); do
cat >> ${NGINX_DIR}/nginx.conf <<EOF
        location /server${i}/ {
            proxy_pass http://${WEB_IP[$i]}/; # Utilise l'IP du conteneur LXC web
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            # Augmentation des timeouts pour les requêtes potentiellement longues
            proxy_connect_timeout 60s;
            proxy_send_timeout   60s;
            proxy_read_timeout   60s;
        }

EOF
done

cat >> ${NGINX_DIR}/nginx.conf <<EOF
        # Optionnel: Une page d'accueil simple pour la racine /
        location = / {
            return 200 'Reverse Proxy OK. Accédez via /serverX/';
            add_header Content-Type text/plain;
        }
    }
}
EOF

echo "Génération de $NGINX_DIR/Dockerfile..."
cat > ${NGINX_DIR}/Dockerfile <<EOF
FROM nginx:alpine
COPY nginx.conf /etc/nginx/nginx.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
EOF

echo "Build de l'image Docker $PROXY_IMG..."
cd $NGINX_DIR
docker build -t $PROXY_IMG .
cd ..

echo "Arrêt/Suppression de l'ancien conteneur proxy (si existant)..."
docker rm -f $PROXY_CTR 2>/dev/null || true

echo "Lancement du nouveau conteneur proxy $PROXY_CTR..."
# Utilisation de --network host pour simplifier l'accès aux IPs LXC depuis le conteneur Docker
# C'est plus simple que de créer des ponts réseaux complexes.
docker run -d --name $PROXY_CTR --network host -p 80:80 $PROXY_IMG
# Note: --network host donne accès à toutes les interfaces réseau de l'hôte.
# Si les IPs LXC ne sont pas directement routables depuis l'hôte, cela ne fonctionnera pas.
# L'alternative serait de mapper les ports LXC 80 vers des ports hôtes uniques et de pointer le proxy vers localhost:port_mappé.

# --- 9. FINALISATION ---
echo
echo "== MIGRATION TERMINEE ! =="
echo

# Nettoyage des dumps
echo "Nettoyage du répertoire de dump: $DUMP_DIR"
rm -rf "$DUMP_DIR"

echo "== ACCES VIA LE REVERSE PROXY =="
# Tente de trouver l'IP principale de l'hôte pour l'affichage
IP_HOST=$(hostname -I | awk '{print $1}')
if [ -z "$IP_HOST" ]; then
    IP_HOST="[IP_DE_VOTRE_MACHINE_HOTE]"
fi

echo "Le reverse proxy écoute sur http://${IP_HOST}:80"
for i in $(seq 1 3); do
  echo "    Backend $i (web${i} sur ${WEB_IP[$i]} via db${i} sur ${DB_IP[$i]}) accessible via : http://${IP_HOST}/server${i}/"
done
echo
echo "*** Vérifiez que votre application web (index.php) utilise les bonnes informations de connexion à la base de données (probablement root/$NEW_DB_ROOT_PWD sur l'IP ${DB_IP[X]}) ***" 