# Déploiement automatique de l'ancienne infrastructure

## Utilisation du script

Le déploiement de base de l'ancienne infrastructure se fait à l'aide d'un script bash. Ce dernier déploie automatiquement les serveurs web et les bases de données. Il suffit donc de l'exécuter :

```bash
$ chmod +x start-containers.sh
$ start-containers.sh
```

Les trois paires de deux conteneurs (serveur web et base de données) se déploieront alors automatiquement.