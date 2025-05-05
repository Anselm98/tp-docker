# Déploiement de l'infrastructure de COMPANY01

## 1. Prérequis du serveur

Pour commencer, le serveur hôte doit pouvoir utiliser LXD et Docker. Si ce n'est pas le cas, vous pouvez tout installer en utilisant le script "install_docker_lxd.sh" :

```bash
$ chmod +x install_docker_lxd.sh
$ install_docker_lxd.sh
```

---

## 2. L'infrastructure d'origine

### Déploiement de l'infrastructure de base

Afin de déployer l'ancienne infrastructure, vous pouvez vous référer aux instructions contenues dans le fichier suivant :

```bash
"Documentation/Infra_de_base/Deploiement_ancienne_infra.md"
```

### Déploiement de nouveaux conteneurs

Une fois l'infrastructure de base déployée, vous pouvez ajouter de nouvelles paires de conteneurs serveur web + base de données en suivant les instructions du fichier suivant :

```bash
"Documentation/Infra_de_base/Deploiement_nouveaux_conteneurs_ancienne_infra.md"
```

## 3. La nouvelle infrastructure

### Déploiement de l'infrastructure de base

Afin de déployer la nouvelle infrastructure, vous pouvez vous référer aux instructions contenues dans le fichier suivant :

```bash
"Documentation/Nouvelle_infra/Deploiement_nouvelle_infra.md"
```

### Déploiement de nouveaux conteneurs

Une fois l'infrastructure de base déployée, vous pouvez ajouter de nouvelles paires de conteneurs serveur web + base de données en suivant les instructions du fichier suivant :

```bash
"Documentation/Nouvelle_infra/Deploiement_nouveaux_conteneurs_nouvelle_infra.md"
```

## 4. Migration vers la nouvelle infrastructure

Si vous avez déjà l'infrastructure de base et que vous souhaitez passer à la nouvelle infrastructure, vous devrez migrer votre infrastructure en suivant les instructions contenues dans le fichier suivant :

```bash
"Documentation/Nouvelle_infra/Migration.md"
```