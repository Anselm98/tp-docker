#!/bin/bash

# Adresses des réseaux
NET1=10.10.1
NET2=10.10.2
NET3=10.10.3

# Noms des conteneurs
C1=web1
C2=web2
C3=web3

# Noms des réseaux LXC
N1=net1
N2=net2
N3=net3

# Reverse proxy (nom de l'image et du conteneur)
PROXY_IMG=my-reverseproxy
PROXY_CTR=reverseproxy

set -e

echo "== 1. Création des réseaux LXC =="
lxc network create $N1 ipv4.address=$NET1.1/24 ipv4.nat=true || true
lxc network create $N2 ipv4.address=$NET2.1/24 ipv4.nat=true || true
lxc network create $N3 ipv4.address=$NET3.1/24 ipv4.nat=true || true

echo "== 2. Création des conteneurs LXC Apache/MariaDB =="

for i in 1 2 3; do
  CNT="web$i"
  NET="net$i"
  IMG="ubuntu:22.04"
  echo " - $CNT sur $NET"
  lxc launch $IMG $CNT -n $NET || echo "$CNT existe déjà"
done

echo "== 3. Installation Apache/MariaDB + index personnalisé =="

for i in 1 2 3; do
  CNT="web$i"
  echo " [${CNT}] Installation..."
  lxc exec $CNT -- bash -c 'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y apache2 mariadb-server php php-mysql'
  lxc exec $CNT -- systemctl enable apache2 mariadb
  lxc exec $CNT -- systemctl start apache2 mariadb

  echo " [${CNT}] Déploiement index.html..."
  lxc exec $CNT -- bash -c "
cat >/var/www/html/index.php <<EOF
<!DOCTYPE html>
<html>
<head>
  <title>Company 01 - \$HOSTNAME</title>
  <meta charset=\"utf-8\">
</head>
<body>
  <h1>Bienvenue chez Company 01</h1>
  <p>
    Ce site est hébergé sur le conteneur <strong><?php echo gethostname(); ?></strong>.<br>
    Vous êtes actuellement sur : <strong><?php echo \$_SERVER['SERVER_ADDR']; ?></strong>
  </p>
</body>
</html>
EOF
"
done

echo "== 4. Récupération des IPs LXC =="
WEB1_IP=$(lxc list $C1 -c 4 --format csv | cut -d' ' -f1)
WEB2_IP=$(lxc list $C2 -c 4 --format csv | cut -d' ' -f1)
WEB3_IP=$(lxc list $C3 -c 4 --format csv | cut -d' ' -f1)
echo "Web1: $WEB1_IP"
echo "Web2: $WEB2_IP"
echo "Web3: $WEB3_IP"

echo "== 5. Génération NGINX config =="
mkdir -p nginx-reverse-proxy
cat > nginx-reverse-proxy/nginx.conf <<EOF
events {}

http {
    server {
        listen 80;
        server_name web1.local;
        location / {
            proxy_pass http://$WEB1_IP/;
        }
    }
    server {
        listen 80;
        server_name web2.local;
        location / {
            proxy_pass http://$WEB2_IP/;
        }
    }
    server {
        listen 80;
        server_name web3.local;
        location / {
            proxy_pass http://$WEB3_IP/;
        }
    }
}
EOF

echo "== 6. Génération Dockerfile NGINX reverse-proxy =="
cat > nginx-reverse-proxy/Dockerfile <<EOF
FROM nginx:alpine
COPY ./nginx.conf /etc/nginx/nginx.conf
RUN rm /etc/nginx/conf.d/default.conf
EOF

echo "== 7. Build & Run NGINX reverse proxy =="
cd nginx-reverse-proxy
docker build -t $PROXY_IMG .
docker rm -f $PROXY_CTR 2>/dev/null || true
docker run -d -p 80:80 --name $PROXY_CTR --network host $PROXY_IMG
cd ..

echo
echo "== DONE ! =="
echo "Ajoute ceci à /etc/hosts pour tester :"
echo "$(hostname -I | awk '{print $1}') web1.local web2.local web3.local"
echo "Ensuite visite http://web1.local, http://web2.local, http://web3.local"
