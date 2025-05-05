#!/bin/bash
set -e

# --- PARAMETRES ---
# NBCLIENTS=3              # Nombre de clients/serveurs à migrer (doit correspondre à l'infra Docker)
BASE_NET=10.10           # Les réseaux LXC seront 10.10.1, 10.10.2, ...
PROXY_IMG=my-reverseproxy-migrated
PROXY_CTR=reverseproxy-migrated
OLD_DB_ROOT_PWD="michel" # Mot de passe root des BDD MariaDB Docker existantes
NEW_DB_ROOT_PWD="michel" # Mot de passe root pour les nouvelles BDD MariaDB LXC (peut être changé)
DUMP_DIR="./db_dumps_migration" # Répertoire temporaire pour les dumps SQL (local)

declare -A WEB_IP
declare -A DB_IP
declare -A DBNAME # Stocker les noms des BDD Docker

# --- 0. PREPARATION & DUMP DES BASES DOCKER ---
echo "--- Préparation de la migration ---"
echo "Création du répertoire de dump: $DUMP_DIR"
rm -rf "$DUMP_DIR" 2>/dev/null || true
mkdir -p "$DUMP_DIR"
chmod 777 "$DUMP_DIR"

echo "Vérification de l'existence du répertoire de dump..."
if [ ! -d "$DUMP_DIR" ]; then
  echo "ERREUR: Échec de création du répertoire $DUMP_DIR"
  exit 1
fi
echo "Nettoyage du répertoire de dump: $DUMP_DIR"
rm -f ${DUMP_DIR}/*.sql

echo "Dump des bases de données depuis les conteneurs Docker..."
for i in $(seq 1 3); do
  DOCKER_DB_CTR="db$i"
  DOCKER_DB_NAME="webserver${i}db" # Nom de la BDD dans l'infra Docker
  DBNAME[$i]=$DOCKER_DB_NAME
  DUMP_FILE="${DUMP_DIR}/dump_${DOCKER_DB_NAME}.sql"  # Utilisez le nom de la base de données dans le nom du fichier pour être sûr
  echo " - Préparation du dump pour '$DOCKER_DB_NAME' depuis '$DOCKER_DB_CTR'"

  # Ensure mariadb-client (for mariadb-dump) is installed in the container
  echo "   - Installation de mariadb-client dans $DOCKER_DB_CTR (si nécessaire)..."
  # Use DEBIAN_FRONTEND and show output for debugging
  docker exec $DOCKER_DB_CTR bash -c "export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -qq mariadb-client"
  if [ $? -ne 0 ]; then
    echo "ERREUR: Échec de l'installation de mariadb-client dans $DOCKER_DB_CTR. Vérifiez la sortie ci-dessus, la connectivité réseau du conteneur et les dépôts apt."
    # Attempt alternative package name just in case
    echo "   - Tentative avec 'mysql-client'..."
    docker exec $DOCKER_DB_CTR bash -c "export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -qq mysql-client"
    if [ $? -ne 0 ]; then
        echo "ERREUR: Échec de l'installation de 'mysql-client' également dans $DOCKER_DB_CTR. Vérifiez la sortie ci-dessus."
        exit 1
    fi
  fi

  # Find the actual path of mariadb-dump within the container
  DUMP_CMD=$(docker exec $DOCKER_DB_CTR which mariadb-dump 2>/dev/null)
  if [ -z "$DUMP_CMD" ]; then
    echo "WARN: mariadb-dump non trouvé, tentative avec mysqldump..."
    DUMP_CMD=$(docker exec $DOCKER_DB_CTR which mysqldump 2>/dev/null)
    if [ -z "$DUMP_CMD" ]; then
      echo "WARN: mysqldump non trouvé, utilisation de 'mariadb-dump' directement (chemin par défaut)..."
      DUMP_CMD="mariadb-dump"
    fi
  fi
  echo "   - Utilisation de l'outil dump trouvé à: $DUMP_CMD"

  echo "   - Dump de la base '$DOCKER_DB_NAME' vers '$DUMP_FILE'"
  # Create a temporary directory in the container for the dump
  docker exec $DOCKER_DB_CTR mkdir -p /tmp/db_dumps
  
  # Execute dump inside the container itself first
  CONTAINER_DUMP_FILE="/tmp/db_dumps/dump_${DOCKER_DB_NAME}.sql"
  docker exec $DOCKER_DB_CTR bash -c "${DUMP_CMD} -u root -p${OLD_DB_ROOT_PWD} --databases ${DOCKER_DB_NAME} --add-drop-database --routines --events --triggers --single-transaction > ${CONTAINER_DUMP_FILE}"
  
  # Copy the dump from the container to the host
  docker cp ${DOCKER_DB_CTR}:${CONTAINER_DUMP_FILE} "$DUMP_FILE"

  if [ $? -ne 0 ] || [ ! -s "$DUMP_FILE" ]; then # Check if dump command failed or produced empty file
    echo "ERREUR: La commande dump a échoué pour $DOCKER_DB_CTR ou a produit un fichier vide."
    echo "Tentative de dump direct..."
    # Alternative method: direct pipe
    docker exec $DOCKER_DB_CTR bash -c "${DUMP_CMD} -u root -p${OLD_DB_ROOT_PWD} --databases ${DOCKER_DB_NAME} --add-drop-database --routines --events --triggers --single-transaction" > "$DUMP_FILE"
    
    if [ $? -ne 0 ] || [ ! -s "$DUMP_FILE" ]; then
      echo "ERREUR: Toutes les tentatives de dump ont échoué pour $DOCKER_DB_CTR."
      if [ -f "$DUMP_FILE" ] && [ ! -s "$DUMP_FILE" ]; then
          echo "ERREUR: Le fichier dump '$DUMP_FILE' est vide."
      elif [ ! -f "$DUMP_FILE" ]; then
          echo "ERREUR: Le fichier dump '$DUMP_FILE' n'a pas été créé."
      fi
      exit 1
    fi
  fi

  # Optional: Check if dump file is non-empty as an extra verification
  if [ ! -s "$DUMP_FILE" ]; then
      echo "ERREUR: Le fichier dump '$DUMP_FILE' est vide après une exécution apparemment réussie (exit code 0). Problème potentiel avec mariadb-dump ou la base de données elle-même."
      exit 1
  fi

  echo "   - Extraction des utilisateurs de la base $DOCKER_DB_NAME"
  # Create a specific dump of users and privileges for each database
  USER_DUMP_FILE="${DUMP_DIR}/users_${DOCKER_DB_NAME}.sql"
  
  # Create temp files in the container
  docker exec $DOCKER_DB_CTR bash -c "mkdir -p /tmp/db_dumps"
  
  # First, extract users with their creation statements
  docker exec $DOCKER_DB_CTR bash -c "mariadb -u root -p${OLD_DB_ROOT_PWD} -N -e \"
    SELECT CONCAT(
      'CREATE USER IF NOT EXISTS \\'', user, '\\'@\\'', host, '\\' IDENTIFIED BY \\'michel\\';'
    ) FROM mysql.user WHERE user NOT IN ('root', 'mysql', 'mariadb.sys', '');
  \" > /tmp/db_dumps/users_dump.sql"
  
  # Now extract grants for each user separately, directly executing each statement
  docker exec $DOCKER_DB_CTR bash -c "mariadb -u root -p${OLD_DB_ROOT_PWD} -N -e \"
    SELECT CONCAT(
      'SHOW GRANTS FOR \\'', user, '\\'@\\'', host, '\\';'
    ) FROM mysql.user WHERE user NOT IN ('root', 'mysql', 'mariadb.sys', '');
  \" > /tmp/db_dumps/grant_commands.sql"
  
  # Create file for grant results
  docker exec $DOCKER_DB_CTR bash -c "touch /tmp/db_dumps/grant_results.sql"
  
  # Process each grant command separately to avoid SQL syntax errors
  docker exec $DOCKER_DB_CTR bash -c "cat /tmp/db_dumps/grant_commands.sql | while read grant_cmd; do
    echo \"-- Getting grants for \$grant_cmd\" >> /tmp/db_dumps/grant_results.sql
    mariadb -u root -p${OLD_DB_ROOT_PWD} -N -e \"\$grant_cmd\" | 
    sed 's/\$/;/g' >> /tmp/db_dumps/grant_results.sql 2>/dev/null || 
    echo \"-- Failed to get grants for \$grant_cmd\" >> /tmp/db_dumps/grant_results.sql
  done"
  
  # Manually add critical users for the application
  docker exec $DOCKER_DB_CTR bash -c "cat > /tmp/db_dumps/critical_users.sql << EOF
-- Critical application users
CREATE USER IF NOT EXISTS 'healthcheck'@'%' IDENTIFIED BY 'michel';
GRANT ALL PRIVILEGES ON *.* TO 'healthcheck'@'%';
CREATE USER IF NOT EXISTS 'healthcheck'@'localhost' IDENTIFIED BY 'michel';
GRANT ALL PRIVILEGES ON *.* TO 'healthcheck'@'localhost';
CREATE USER IF NOT EXISTS 'healthcheck'@'127.0.0.1' IDENTIFIED BY 'michel';
GRANT ALL PRIVILEGES ON *.* TO 'healthcheck'@'127.0.0.1';
FLUSH PRIVILEGES;
EOF"
  
  # Combine all SQL files in the container
  docker exec $DOCKER_DB_CTR bash -c "cat /tmp/db_dumps/users_dump.sql /tmp/db_dumps/grant_results.sql /tmp/db_dumps/critical_users.sql > /tmp/db_dumps/final_users.sql"
  
  # Copy the combined file from the container to the host
  docker cp ${DOCKER_DB_CTR}:/tmp/db_dumps/final_users.sql "$USER_DUMP_FILE"
  
  # Check if the file was created successfully
  if [ ! -f "$USER_DUMP_FILE" ]; then
    echo "ERREUR: Impossible de copier le fichier des utilisateurs depuis le conteneur. Création d'un fichier de base..."
    cat > "$USER_DUMP_FILE" << EOF
-- Default fallback users
CREATE USER IF NOT EXISTS 'healthcheck'@'%' IDENTIFIED BY 'michel';
GRANT ALL PRIVILEGES ON *.* TO 'healthcheck'@'%';
FLUSH PRIVILEGES;
EOF
  fi
  
  echo "   - Utilisateurs extraits et sauvegardés dans $USER_DUMP_FILE"

done
echo "Dump terminé."

# Fix collation issues in dump files
echo "Correction des problèmes de collation dans les dumps..."
for dump_file in ${DUMP_DIR}/dump_*.sql; do
  echo " - Correction de $dump_file"
  sed -i 's/utf8mb4_uca1400_ai_ci/utf8mb4_general_ci/g' "$dump_file"
done
echo "Correction terminée."

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

  # --- 1.1 ARRET ET SUPPRESSION DE TOUS LES CONTENEURS DOCKER ---
  echo "--- Arrêt et suppression de tous les conteneurs Docker ---"
  if docker ps -q | grep -q .; then
    echo "Arrêt de tous les conteneurs Docker en cours..."
    docker stop $(docker ps -a -q) || true
  fi
  
  if docker ps -a -q | grep -q .; then
    echo "Suppression de tous les conteneurs Docker en cours..."
    docker rm $(docker ps -a -q) || true
  fi
  
  echo "Suppression des réseaux Docker non utilisés..."
  docker network prune -f || true
  
  echo "Tous les conteneurs Docker ont été arrêtés et supprimés."
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

# --- 5. INSTALLATION SERVICES & MIGRATION DONNEES DB ---
echo "--- Installation des services et Migration des données DB ---"
for i in $(seq 1 3); do
  WEBCTN="web$i"
  DBCTN="db$i"
  WEBCTN_IP="${WEB_IP[$i]}"
  DBCTN_IP="${DB_IP[$i]}"

  echo " [${WEBCTN}] Installation Apache2/PHP"
  lxc exec $WEBCTN -- bash -c 'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y apache2 php php-mysql'
  lxc exec $WEBCTN -- systemctl enable apache2
  lxc exec $WEBCTN -- systemctl start apache2

  echo " [${DBCTN}] Installation MariaDB"
  # Ajout de rsync au cas où lxc file push échoue.
  lxc exec $DBCTN -- bash -c 'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y mariadb-server rsync'
  
  # S'assurer que le répertoire conf.d existe
  lxc exec $DBCTN -- bash -c 'mkdir -p /etc/mysql/conf.d'

  # --- Configuration MariaDB - Garantir l'écoute sur toutes les interfaces ---
  CONF_FILE="/etc/mysql/mariadb.conf.d/50-server.cnf"
  echo " [${DBCTN}] Configuration bind-address MariaDB sur 0.0.0.0 (toutes les interfaces)"
  lxc exec $DBCTN -- test -f $CONF_FILE || (echo "Fichier $CONF_FILE non trouvé sur $DBCTN" && exit 1)
  
  # Supprimer TOUTES les directives bind-address du fichier
  lxc exec $DBCTN -- sed -i '/bind-address/d' $CONF_FILE

  # Ajouter une nouvelle directive bind-address = 0.0.0.0 dans la section [mysqld]
  lxc exec $DBCTN -- bash -c "sed -i '/\\[mysqld\\]/a bind-address = 0.0.0.0' $CONF_FILE"
  
  # Vérifier que la directive a bien été ajoutée
  BIND_CHECK=$(lxc exec $DBCTN -- grep -c "bind-address = 0.0.0.0" $CONF_FILE || echo "0")
  if [ "$BIND_CHECK" -eq "0" ]; then
    echo " [${DBCTN}] ATTENTION: Échec de configuration de bind-address. Tentative alternative..."
    lxc exec $DBCTN -- bash -c "echo 'bind-address = 0.0.0.0' >> $CONF_FILE"
  fi

  # Méthode directe et fiable: créer un fichier my.cnf qui prendra priorité
  echo " [${DBCTN}] Création de /etc/mysql/my.cnf pour garantir l'écoute sur toutes les interfaces"
  lxc exec $DBCTN -- bash -c "echo '[mysqld]' > /etc/mysql/my.cnf"
  lxc exec $DBCTN -- bash -c "echo 'bind-address = 0.0.0.0' >> /etc/mysql/my.cnf"
  lxc exec $DBCTN -- bash -c "echo 'skip-networking = 0' >> /etc/mysql/my.cnf"

  lxc exec $DBCTN -- systemctl enable mariadb

  # --- 6. RESTAURATION DES BASES DE DONNÉES À PARTIR DES DUMPS ---
  echo " [${DBCTN}] Initialisation et démarrage de MariaDB..."
  lxc exec $DBCTN -- systemctl start mariadb || true # Continue even if fails
  echo " [${DBCTN}] Attente du démarrage de MariaDB (15s)..."
  sleep 15
  
  # Vérification si MariaDB est actif
  if ! lxc exec $DBCTN -- systemctl is-active mariadb --quiet; then
      echo "ERREUR: MariaDB n'a pas pu démarrer dans $DBCTN. Vérifiez les logs."
      echo "Tentative d'initialisation manuelle..."
      
      # S'assurer que le répertoire conf.d existe
      lxc exec $DBCTN -- bash -c 'mkdir -p /etc/mysql/conf.d'
      
      # Initialiser la base de données
      lxc exec $DBCTN -- mariadb-install-db --user=mysql
      lxc exec $DBCTN -- systemctl start mariadb
      sleep 10
      
      if ! lxc exec $DBCTN -- systemctl is-active mariadb --quiet; then
          echo "ERREUR: MariaDB n'a toujours pas pu démarrer après initialisation manuelle."
          exit 1
      fi
  fi
  
  # Vérifier que MariaDB écoute bien sur toutes les interfaces (0.0.0.0)
  MYSQL_LISTEN=$(lxc exec $DBCTN -- ss -tlnp | grep -c ":3306.*0.0.0.0" || echo "0")
  if [ "$MYSQL_LISTEN" -eq "0" ]; then
    echo " [${DBCTN}] ATTENTION: MariaDB n'écoute pas sur toutes les interfaces. Redémarrage forcé..."
    lxc exec $DBCTN -- systemctl restart mariadb
    sleep 5
    
    # Vérifier à nouveau
    MYSQL_LISTEN=$(lxc exec $DBCTN -- ss -tlnp | grep -c ":3306.*0.0.0.0" || echo "0")
    if [ "$MYSQL_LISTEN" -eq "0" ]; then
      echo " [${DBCTN}] ERREUR CRITIQUE: MariaDB n'écoute toujours pas sur 0.0.0.0 après redémarrage."
      echo " Vérification de la configuration actuelle:"
      lxc exec $DBCTN -- cat /etc/mysql/my.cnf || echo "Fichier my.cnf non trouvé"
      lxc exec $DBCTN -- cat $CONF_FILE | grep -A 2 -B 2 bind-address || echo "Directive bind-address non trouvée"
      lxc exec $DBCTN -- ss -tlnp
    fi
  else
    echo " [${DBCTN}] MariaDB écoute correctement sur toutes les interfaces (0.0.0.0:3306)"
  fi
  
  # Vérifier si la base de données existe déjà
  DB_NAME="${DBNAME[$i]}"
  DUMP_FILE="${DUMP_DIR}/dump_${DB_NAME}.sql"
  USER_DUMP_FILE="${DUMP_DIR}/users_${DB_NAME}.sql"
  
  DB_EXISTS=$(lxc exec $DBCTN -- bash -c "mariadb -e 'SHOW DATABASES' | grep -w ${DB_NAME}" || echo "")
  
  if [ -n "$DB_EXISTS" ]; then
      echo " [${DBCTN}] La base de données ${DB_NAME} existe déjà, importation ignorée."
  else
      # Configuration du mot de passe root si ce n'est pas déjà fait
      echo " [${DBCTN}] Configuration du mot de passe root (local uniquement)..."
      lxc exec $DBCTN -- bash -c "mariadb -e \"SET PASSWORD FOR 'root'@'localhost' = PASSWORD('$NEW_DB_ROOT_PWD')\" || true"
      
      # Créer des utilisateurs spécifiques pour chaque web container avec tous les privilèges
      echo " [${DBCTN}] Création d'utilisateur user${i}..."
      lxc exec $DBCTN -- bash -c "mariadb -u root -p$NEW_DB_ROOT_PWD -e \"CREATE USER IF NOT EXISTS 'user${i}'@'%' IDENTIFIED BY '$NEW_DB_ROOT_PWD'; GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO 'user${i}'@'%'; FLUSH PRIVILEGES;\""
      
      # If we have user dump file, restore users
      if [ -f "$USER_DUMP_FILE" ]; then
          echo " [${DBCTN}] Restauration des utilisateurs originaux depuis $USER_DUMP_FILE"
          lxc file push "$USER_DUMP_FILE" "${DBCTN}/tmp/users.sql"
          lxc exec $DBCTN -- bash -c "mariadb -u root -p${NEW_DB_ROOT_PWD} < /tmp/users.sql || true"
          lxc exec $DBCTN -- rm -f /tmp/users.sql
      fi
      
      # Restauration du dump SQL
      echo " [${DBCTN}] Restauration du dump SQL dans MariaDB..."
      lxc file push "$DUMP_FILE" "${DBCTN}/tmp/dump.sql"
      if ! lxc exec $DBCTN -- bash -c "mariadb -u root -p${NEW_DB_ROOT_PWD} < /tmp/dump.sql"; then
          echo "ERREUR: Échec de la restauration du dump SQL dans ${DBCTN}."
          
          # Dernière tentative sans mot de passe
          echo " [${DBCTN}] Tentative de restauration sans mot de passe..."
          if ! lxc exec $DBCTN -- bash -c "mariadb < /tmp/dump.sql"; then
              exit 1
          fi
      fi
      lxc exec $DBCTN -- rm -f /tmp/dump.sql
      
      echo " [${DBCTN}] Base de données restaurée avec succès."
  fi

  # Ajouter les entrées DNS pour résoudre dbX depuis webX
  echo " [${WEBCTN}] Ajout de l'entrée host pour db${i}"
  lxc exec $WEBCTN -- bash -c "echo '${DB_IP[$i]} db${i}' >> /etc/hosts"

  # Sécurité: Désactiver l'accès remote pour root
  echo " [${DBCTN}] Désactivation de l'accès distant pour l'utilisateur root (sécurité)..."
  lxc exec $DBCTN -- bash -c "mariadb -u root -p$NEW_DB_ROOT_PWD -e \"DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1'); FLUSH PRIVILEGES;\""

  # After MariaDB starts, add a test connection to verify connectivity:
  echo " [${DBCTN}] Test de connexion locale à la base de données..."
  if lxc exec $DBCTN -- bash -c "mariadb -u root -p$NEW_DB_ROOT_PWD -h 127.0.0.1 -e 'SELECT 1'"; then
    echo " [${DBCTN}] Connexion locale réussie (127.0.0.1)"
  else
    echo " [${DBCTN}] ERREUR: Échec de connexion locale à MariaDB"
  fi
  
  # Test connection with user account (not root)
  echo " [${DBCTN}] Test de connexion réseau avec utilisateur user${i}..."
  if lxc exec $DBCTN -- bash -c "mariadb -u user${i} -p$NEW_DB_ROOT_PWD -h $DBCTN_IP -e 'SELECT 1'"; then
    echo " [${DBCTN}] Connexion réseau réussie avec user${i} ($DBCTN_IP)"
  else
    echo " [${DBCTN}] ERREUR: Échec de connexion réseau à MariaDB avec user${i}"
    
    # Try to fix the issue by creating /etc/mysql/my.cnf
    echo " [${DBCTN}] Tentative de correction - création de /etc/mysql/my.cnf..."
    lxc exec $DBCTN -- bash -c "cat > /etc/mysql/my.cnf << EOF
[mysqld]
bind-address = 0.0.0.0
skip-networking = 0
EOF"
    lxc exec $DBCTN -- systemctl restart mariadb
    sleep 5
    
    if lxc exec $DBCTN -- bash -c "mariadb -u user${i} -p$NEW_DB_ROOT_PWD -h $DBCTN_IP -e 'SELECT 1'"; then
      echo " [${DBCTN}] Connexion réseau réussie après correction"
    else
      echo " [${DBCTN}] ERREUR CRITIQUE: Connexion toujours impossible après correction"
    fi
  fi
  
  # Confirmer que root ne peut pas se connecter à distance (test de sécurité)
  echo " [${DBCTN}] Vérification que root ne peut PAS se connecter à distance (test de sécurité)..."
  if ! lxc exec $DBCTN -- bash -c "mariadb -u root -p$NEW_DB_ROOT_PWD -h $DBCTN_IP -e 'SELECT 1'" 2>/dev/null; then
    echo " [${DBCTN}] OK: L'utilisateur root ne peut pas se connecter à distance (sécurité renforcée)"
  else
    echo " [${DBCTN}] ATTENTION: L'utilisateur root peut encore se connecter à distance, nouvelle tentative de désactivation..."
    lxc exec $DBCTN -- bash -c "mariadb -u root -p$NEW_DB_ROOT_PWD -e \"DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1'); FLUSH PRIVILEGES;\""
  fi
  
  # Test with web container
  echo " [${WEBCTN}->${DBCTN}] Test de connexion depuis $WEBCTN vers $DBCTN..."
  lxc exec $WEBCTN -- bash -c "apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y mariadb-client" >/dev/null 2>&1
  if lxc exec $WEBCTN -- bash -c "mariadb -u user${i} -p${NEW_DB_ROOT_PWD} -h $DBCTN_IP -e 'SELECT 1'"; then
    echo " [${WEBCTN}->${DBCTN}] Connexion depuis $WEBCTN réussie avec utilisateur 'user${i}'"
  else
    echo " [${WEBCTN}->${DBCTN}] ERREUR: Échec de connexion depuis $WEBCTN avec utilisateur 'user${i}'"
    
    # Try with host
    if lxc exec $WEBCTN -- bash -c "mariadb -u user${i} -p${NEW_DB_ROOT_PWD} -h db$i -e 'SELECT 1'"; then
      echo " [${WEBCTN}->${DBCTN}] Connexion réussie via hostname 'db$i'"
    else 
      echo " [${WEBCTN}->${DBCTN}] ERREUR: Échec de connexion via hostname 'db$i'"
      
      # Verify host resolution
      lxc exec $WEBCTN -- bash -c "cat /etc/hosts | grep db$i" || echo "Entrée manquante dans /etc/hosts"
      lxc exec $WEBCTN -- bash -c "getent hosts db$i" || echo "Résolution d'hôte échouée"
    fi
  fi

done

# --- 7. DEPLOIEMENT index.php sur webX ---
echo "--- Déploiement application web (index.php) ---"
for i in $(seq 1 3); do
  WEBCTN="web$i"
  SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
  ORIGINAL_INDEX="${SCRIPT_DIR}/index.php"
  TEMP_INDEX="/tmp/index_temp_${WEBCTN}.php"

  if [ ! -f "$ORIGINAL_INDEX" ]; then
      echo "ERREUR: Fichier index.php non trouvé dans $SCRIPT_DIR. Impossible de déployer."
      exit 1
  fi

  # Copie directe de l'original pour le test
  cp "$ORIGINAL_INDEX" "$TEMP_INDEX"

  echo " [${WEBCTN}] Push index.php"
  lxc file push "$TEMP_INDEX" ${WEBCTN}/var/www/html/index.php --mode 0644
  rm "$TEMP_INDEX"
  lxc exec $WEBCTN -- rm -f /var/www/html/index.html 2>/dev/null || true

done
echo "IMPORTANT: Vérifiez que index.php utilise les bons identifiants BDD."
echo "Il doit se connecter via l'utilisateur user<X> et non pas root (root est désactivé pour les connexions distantes)."

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

EOF

for i in $(seq 1 3); do
cat >> ${NGINX_DIR}/nginx.conf <<EOF
        location /server${i}/ {
            proxy_pass http://${WEB_IP[$i]}/;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }

EOF
done

cat >> ${NGINX_DIR}/nginx.conf <<EOF
        location = / {
            return 200 'Reverse Proxy OK. Accedez via l'uri /server1/ /server2/ /server3/...';
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
(cd $NGINX_DIR && docker build -t $PROXY_IMG .)
if [ $? -ne 0 ]; then echo "ERREUR: Build Docker a échoué."; exit 1; fi

echo "Arrêt/Suppression de l'ancien conteneur proxy (si existant)..."
docker rm -f $PROXY_CTR 2>/dev/null || true

echo "Lancement du nouveau conteneur proxy $PROXY_CTR..."
docker run -d --name $PROXY_CTR --network host -p 80:80 $PROXY_IMG
if [ $? -ne 0 ]; then echo "ERREUR: Lancement du conteneur proxy a échoué."; exit 1; fi

# --- 8.5. DÉSACTIVATION DES SERVICES NON ESSENTIELS (CRON ET SSH) POUR DURCISSEMENT ---
echo "--- Désactivation des services non essentiels (cron et ssh) dans les conteneurs LXC ---"
for i in $(seq 1 3); do
  WEBCTN="web$i"
  DBCTN="db$i"
  
  echo " [${WEBCTN}] Désactivation de cron et ssh pour durcissement..."
  lxc exec $WEBCTN -- systemctl disable --now cron ssh || true
  
  echo " [${DBCTN}] Désactivation de cron et ssh pour durcissement..."
  lxc exec $DBCTN -- systemctl disable --now cron ssh || true
done
echo "Services non essentiels désactivés pour renforcer la sécurité."

# --- 9. FINALISATION ---
echo
echo "== MIGRATION TERMINEE ! =="
echo

# Nettoyage des dumps
echo "Nettoyage du répertoire de dump: $DUMP_DIR"
rm -rf "$DUMP_DIR"

echo "== ACCES VIA LE REVERSE PROXY =="
IP_HOST=$(hostname -I | awk '{print $1}' || echo "[IP_DE_VOTRE_MACHINE_HOTE]")

echo "Le reverse proxy écoute sur http://${IP_HOST}:80"
for i in $(seq 1 3); do
  echo "    Backend $i (web${i} sur ${WEB_IP[$i]} via db${i} sur ${DB_IP[$i]}) accessible via : http://${IP_HOST}/server${i}/"
done
echo
echo "*** La migration par copie de fichiers est terminée. ***"
echo "*** Vérifiez que votre application web (index.php) se connecte correctement. ***"
echo "*** SECURITE RENFORCEE: L'utilisateur root a été désactivé pour l'accès distant ***"
echo "*** Les identifiants de connexion pour web<X> sont: ***"
echo "***   - Hôte: db<X> ***"
echo "***   - Utilisateur: user<X> (N'utilisez PAS root pour la sécurité) ***"
echo "***   - Mot de passe: $NEW_DB_ROOT_PWD ***"
echo "***   - Base de données: ${DBNAME[X]} ***" 