# Déploiement Manuel de l'Ancienne Infrastructure

## 1. Vérification des conteneurs existants

Pour commencer, utilisez la commande suivante pour obtenir une liste des noms de tous les conteneurs existants :

```bash
docker ps -a --format '{{.Names}}'
```

Ensuite, identifiez les numéros des conteneurs pour déterminer lesquels associer à vos nouveaux conteneurs.

### Exemple :
```bash
$ docker ps -a --format '{{.Names}}'
reverse-proxy
webserver3
webserver2
webserver1
db3
db2
db1
```

Dans cet exemple, vous devrez créer `webserver4` et `db4`.

---

## 2. Création des conteneurs

### Création du nouveau réseau
Pour isoler la nouvelle paire de conteneurs des conteneurs existants, créez un nouveau réseau avec la commande suivante :

```bash
docker network create webserver??-network
```

En reprenant l'exemple précédent :
```bash
docker network create webserver4-network
```

### Création des conteneurs
Créez les nouveaux conteneurs dans ce réseau avec les commandes suivantes :

#### Conteneur de base de données :
```bash
docker run -d --name db?? --network webserver??-network -e MARIADB_ROOT_PASSWORD=michel -e DB_INSTANCE=db?? -v db??-data:/var/lib/mysql my-mariadb
```

#### Conteneur du serveur web :
```bash
docker run -d --name webserver?? --network webserver??-network -e DB_HOST=db?? -e DB_NAME=webserver??db -p 8083:80 my-webserver
```

Pour l'exemple précédent :
```bash
docker run -d --name db4 --network webserver4-network -e MARIADB_ROOT_PASSWORD=michel -e DB_INSTANCE=db4 -v db4-data:/var/lib/mysql my-mariadb
docker run -d --name webserver4 --network webserver4-network -e DB_HOST=db4 -e DB_NAME=webserver4db -p 8084:80 my-webserver
```

---

## 3. Modification du reverse-proxy

### Connexion au nouveau réseau
Ajoutez le nouveau réseau créé au reverse-proxy avec la commande suivante :
```bash
docker network connect webserver??-network reverse-proxy
```

Pour l'exemple précédent :
```bash
docker network connect webserver4-network reverse-proxy
```

### Modification de la configuration
Connectez-vous au conteneur `reverse-proxy` :
```bash
docker exec -it reverse-proxy sh
```

#### Ajout du nouveau serveur dans la configuration Nginx
Ajoutez le nouveau serveur dans le fichier `/etc/nginx/conf.d/default.conf` avec la commande suivante :
```bash
sed -i '/server webserver??:80;/a\    server webserver??:80;' /etc/nginx/conf.d/default.conf
```

Pour l'exemple précédent :
```bash
sed -i '/server webserver3:80;/a\    server webserver4:80;' /etc/nginx/conf.d/default.conf
```

#### Ajout de la route spécifique pour le nouveau serveur
Ajoutez une route spécifique pour le nouveau serveur avec la commande suivante :
```bash
sed -i '$i\\n\    # Specific route for webserver??\n\    location /server??/ {\n\        proxy_pass http://webserver??:80/;\n\        proxy_set_header Host $host;\n\        proxy_set_header X-Real-IP $remote_addr;\n\        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n\        proxy_set_header X-Forwarded-Proto $scheme;\n\    }' /etc/nginx/conf.d/default.conf
```

Pour l'exemple précédent :
```bash
sed -i '$i\\n\    # Specific route for webserver4\n\    location /server4/ {\n\        proxy_pass http://webserver4:80/;\n\        proxy_set_header Host $host;\n\        proxy_set_header X-Real-IP $remote_addr;\n\        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n\        proxy_set_header X-Forwarded-Proto $scheme;\n\    }' /etc/nginx/conf.d/default.conf
```

### Rechargement de la configuration
Pour valider la configuration, rechargez Nginx avec la commande suivante (toujours dans le conteneur `reverse-proxy`) :
```bash
nginx -s reload
```