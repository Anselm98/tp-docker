# Déploiement automatique de la nouvelle infrastructure

## Utilisation du script

Le déploiement de base de la nouvelle infrastructure se fait à l'aide d'un script bash. Ce dernier déploie automatiquement les serveurs web et les bases de données. Il suffit donc de l'exécuter :

```bash
$ chmod +x lxc_docker_new_infra.sh
$ lxc_docker_new_infra.sh
```

Les trois paires de deux conteneurs (serveur web et base de données) se déploieront alors automatiquement, et vous le script vous retournera un tableau contenant l'utilisateur de votre base de données et ses identifiants, ainsi que les liens pour accéder aux serveurs web.

### Exemple :
```bash
== IDENTIFIANTS SECURISES MARIA-DB CLIENTS ==
Host            | Username   | Password                         | Database
------------------------------------------------------------------------------------------------
10.10.1.127     | user1      | EjirIZd5sqVvGYeB6pleLfJCbNJeUzmx | client1
10.10.2.247     | user2      | KGOGTDUIAGjWjiqNG6IqYvx2fXDisD6b | client2
10.10.3.107     | user3      | JYkZ85yOSFtwGt9aJESY2i7LQSWVVoJg | client3
------------------------------------------------------------------------------------------------

Accédez aux serveurs via le Nginx Reverse Proxy :
    https://192.168.77.136/server1/
    https://192.168.77.136/server2/
    https://192.168.77.136/server3/

```

Un dossier partagé entre l'hôte et le serveur est également mis en place, au niveau du conteneur il s'agit de /srv/share et au niveau de l'hôte ce sera tp-docker/Nouvelle_infra/share_client??.

### Exemple :
```bash
$ ls tp-docker/Nouvelle_infra
add_new_srv.sh  clean_infra.sh  lxc_docker_new_infra.sh  nginx-reverse-proxy  share_client2
apache_conf     index.php       migrate_infra_to_lxc.sh  share_client1        share_client3
```