# Guide de Migration d'Infrastructure vers LXC

Ce guide explique comment utiliser le script `migrate_infra_to_lxc.sh` pour migrer une infrastructure Docker existante vers une infrastrucutre LXC.

## Prérequis

- Une infrastructure Docker fonctionnelle avec des serveurs web et des bases de données
- LXC et Docker installé sur votre machine
- Accès root ou sudo

## Paramètres configurables

Les paramètres suivants peuvent être modifiés au début du script:

```bash
BASE_NET=10.10           # Les réseaux LXC seront 10.10.1, 10.10.2, ...
PROXY_IMG=my-reverseproxy-migrated
PROXY_CTR=reverseproxy-migrated
OLD_DB_ROOT_PWD="michel" # Mot de passe root des BDD MariaDB Docker existantes
NEW_DB_ROOT_PWD="michel" # Mot de passe root pour les nouvelles BDD MariaDB LXC
DUMP_DIR="./db_dumps_migration" # Répertoire temporaire pour les dumps SQL
```

## Étapes de migration

Le script effectue les étapes suivantes:

1. **Préparation et dump des bases Docker**
   - Dump des bases de données existantes
   - Extraction des utilisateurs et privilèges

2. **Arrêt et suppression de l'ancienne infrastructure Docker**
   - Arrêt et suppression de tous les conteneurs Docker

3. **Création des réseaux LXC**
   - Création de 3 réseaux isolés (net1, net2, net3)

4. **Création des conteneurs LXC**
   - Création des conteneurs web1, web2, web3 (Apache+PHP)
   - Création des conteneurs db1, db2, db3 (MariaDB)

5. **Installation des services et migration des données**
   - Installation d'Apache/PHP sur les conteneurs web
   - Installation et configuration de MariaDB sur les conteneurs db
   - Restauration des bases de données et utilisateurs
   - Configuration des accès réseau

6. **Déploiement des applications web**
   - Déploiement de index.php sur tous les conteneurs web

7. **Configuration et lancement du reverse proxy**
   - Génération de la configuration nginx
   - Création d'un conteneur Docker pour le reverse proxy

8. **Renforcement de la sécurité**
   - Désactivation des services non essentiels (cron, ssh)
   - Désactivation de l'utilisateur root

## Utilisation

1. Assurez-vous que votre infrastructure Docker est en cours d'exécution
2. Placez-vous dans le répertoire contenant le script
3. Exécutez le script:

```bash
sudo bash migrate_infra_to_lxc.sh
```

## Accès à la nouvelle infrastructure

Une fois la migration terminée, vous pouvez accéder aux applications via:

- http://HOST_IP/server1/
- http://HOST_IP/server2/
- http://HOST_IP/server3/

## Identifiants de connexion aux bases de données

Pour chaque serveur web (web1, web2, web3):
- **Hôte**: db1, db2 ou db3 (correspondant au serveur web)
- **Utilisateur**: user1, user2 ou user3 (NE PAS utiliser root)
- **Mot de passe**: défini dans NEW_DB_ROOT_PWD (par défaut: "michel")
- **Base de données**: webserver1db, webserver2db, webserver3db

## Sécurité

Note: Pour renforcer la sécurité, l'accès root distant aux bases de données a été désactivé. Utilisez les comptes userX créés pendant la migration.
