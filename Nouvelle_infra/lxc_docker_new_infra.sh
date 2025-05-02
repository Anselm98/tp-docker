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

# --- 3. INSTALLATION Apache2+PHP sur webX, MariaDB server sur dbX ---
for i in $(seq 1 $NBCLIENTS); do
  WEBCTN="web$i"
  DBCTN="db$i"
  DBPASS="pass${i}web"
  DBNAME="client${i}"
  DBUSER="user${i}"

  echo " [${WEBCTN}] Installation Apache2/PHP"
  lxc exec $WEBCTN -- bash -c 'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y apache2 php php-mysql'
  lxc exec $WEBCTN -- systemctl enable apache2
  lxc exec $WEBCTN -- systemctl start apache2

  echo " [${DBCTN}] Installation MariaDB"
  lxc exec $DBCTN -- bash -c 'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y mariadb-server'
  lxc exec $DBCTN -- systemctl enable mariadb
  lxc exec $DBCTN -- systemctl start mariadb

  # Sécuriser MariaDB et créer BDD & user
  lxc exec $DBCTN -- bash -c "
mysql -u root <<EOS
UPDATE mysql.user SET plugin='mysql_native_password' WHERE User='root';
ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_ROOT_PWD';
FLUSH PRIVILEGES;
CREATE DATABASE IF NOT EXISTS $DBNAME;
CREATE USER IF NOT EXISTS '$DBUSER'@'%' IDENTIFIED BY '$DBPASS';
GRANT ALL PRIVILEGES ON $DBNAME.* TO '$DBUSER'@'%';
FLUSH PRIVILEGES;
EOS
"

done

# --- 4. RECUPERATION DES IPs ---
declare -A WEB_IP
declare -A DB_IP
for i in $(seq 1 $NBCLIENTS); do
  WEBCTN="web$i"
  DBCTN="db$i"
  WEB_IP[$i]=$(lxc list $WEBCTN -c 4 --format csv | cut -d' ' -f1)
  DB_IP[$i]=$(lxc list $DBCTN -c 4 --format csv | cut -d' ' -f1)
  echo " - Web$i: ${WEB_IP[$i]}"
  echo " - Db$i : ${DB_IP[$i]}"
done

# --- 5. DEPLOIEMENT index.php sur webX (connexion à dbX) ---
for i in $(seq 1 $NBCLIENTS); do
  WEBCTN="web$i"
  DBPASS="pass${i}web"
  DBNAME="client${i}"
  DBUSER="user${i}"
  DBHOST="${DB_IP[$i]}"

  # index.php fait une connexion à sa propre db
  lxc exec $WEBCTN -- bash -c "
cat >/var/www/html/index.php <<'EOF'
<!DOCTYPE html>
<html>
<head>
  <title>Company $i - <?php echo gethostname(); ?></title>
  <meta charset=\"utf-8\">
</head>
<body>
  <h1>Bienvenue chez Company $i</h1>
  <p>Hébergé sur <strong><?php echo gethostname(); ?></strong> (WebX)</p>
  <?php
  \$mysqli = new mysqli('$DBHOST', '$DBUSER', '$DBPASS', '$DBNAME');
  if(\$mysqli->connect_errno) {
    echo \"<b>Erreur connexion BDD:</b> \".\$mysqli->connect_error;
  } else {
    echo \"Connexion MariaDB: OK\";
    \$mysqli->close();
  }
  ?>
  <br>IP Web: <strong><?php echo \$_SERVER['SERVER_ADDR']; ?></strong>
  <br>IP DB : <strong>$DBHOST</strong>
</body>
</html>
EOF
"
  lxc exec $WEBCTN -- rm -f /var/www/html/index.html || true
done

# --- 6. GENERATION CONFIG NGINX et Dockerfile ---
mkdir -p nginx-reverse-proxy

cat > nginx-reverse-proxy/nginx.conf <<EOF
events {}

http {
EOF
for i in $(seq 1 $NBCLIENTS); do
cat >> nginx-reverse-proxy/nginx.conf <<EOF
    server {
        listen 80;
        server_name web${i}.local;
        location / {
            proxy_pass http://${WEB_IP[$i]}/;
        }
    }
EOF
done
echo "}" >> nginx-reverse-proxy/nginx.conf

cat > nginx-reverse-proxy/Dockerfile <<EOF
FROM nginx:alpine
COPY nginx.conf /etc/nginx/nginx.conf
RUN rm /etc/nginx/conf.d/default.conf || true
EOF

# --- 7. BUILD ET RUN NGINX ---
cd nginx-reverse-proxy
docker build -t $PROXY_IMG .
docker rm -f $PROXY_CTR 2>/dev/null || true
docker run -d -p 80:80 --name $PROXY_CTR --network host $PROXY_IMG
cd ..

echo
echo "== DONE ! =="
echo "Ajoute ceci à /etc/hosts pour tester (sur ta machine/dans une VM cliente) :"
IP_HOST=$(hostname -I | awk '{print $1}')
for i in $(seq 1 $NBCLIENTS); do
  HOSTS="$HOSTS web${i}.local"
done
echo "$IP_HOST $HOSTS"
echo
echo "Ensuite visite :"
for i in $(seq 1 $NBCLIENTS); do
  echo "    http://web${i}.local"
done
echo
echo "*** Pour vérifier la connexion base : regarde le message sur la page de webX ***"