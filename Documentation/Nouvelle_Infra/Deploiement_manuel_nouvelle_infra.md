# Déploiement Manuel de la nouvelle infrastructure

## Utilisation du script

Afin de faciliter le déploiement de nouveaux serveurs web, un script a été créé afin de le faire automatiquement. Il suffit donc de rendre ce script exécutable puis de l'exécuter :

```bash
$ chmod +x add_new_srv.sh
$ add_new_srv.sh
```

Les deux conteneurs (serveur web et base de données) se déploieront alors automatiquement et il vous sera retourné les informations de connexion à la base de données.

### Exemple :
```bash
== IDENTIFIANTS SECURISES MARIA-DB CLIENT ==
Host            | Username   | Password                         | Database
------------------------------------------------------------------------------------------------
10.10.4.144     | user4      | qlMSSUahO/91WC/U                 | client4
------------------------------------------------------------------------------------------------
```

Un dossier partagé entre l'hôte et le serveur est également mis en place, au niveau du conteneur il s'agit de /srv/share et au niveau de l'hôte ce sera tp-docker/Nouvelle_infra/share_client??.

### Exemple :
```bash
$ ls tp-docker/Nouvelle_infra
add_new_srv.sh  clean_infra.sh  lxc_docker_new_infra.sh  share_client1  share_client3  share_client5
apache_conf     index.php       nginx-reverse-proxy      share_client2  share_client4
```