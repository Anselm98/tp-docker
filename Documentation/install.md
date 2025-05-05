# Utilisation

# Guide d'Installation - Script d'Automatisation Docker & LXC

<aside>
**Prérequis Système**
Ubuntu 22.04 ou supérieur

</aside>

## Étapes d'Installation

### 1. Mise à jour du système et installation de Git (Optionnel)

```bash
sudo apt update
sudo apt install -y git
```

### 2. Téléchargement du dépôt

Choisissez un dossier d'installation et exécutez :

```bash
git clone https://github.com/Anselm98/tp-docker.git
cd tp-docker
```

### 3. Consultation de la documentation

```bash
cat README.md
```

### 4. Configuration (Optionnel)

Ouvrez le script d'installation pour adapter les options :

```bash
sudo nano install_docker.sh
```

### 5. Installation LXD

Suivre les commandes ci-dessous et mettre tout par défaut durant l’initialisation

```bash
sudo snap install lxd
sudo lxd init
```

### 6. Installation Docker

```bash
sudo chmod +x install_docker.sh
sudo ./install_docker.sh
```

<aside>
Déconnectez-vous puis reconnectez-vous pour appliquer les changements de groupe (utilisation de Docker sans sudo)

</aside>

### 7. Déploiement de l'infrastructure

Revenir dans le dossier tp-docker et Nouvelle_infra et lancer le déploiement :

```bash
sudo chmod +x lxc_docker_new_infra.sh
sudo ./lxc_docker_new_infra.sh
```

### 8. Informations de connexion

<aside>
⚠️ Important : Conservez les informations affichées à la fin du script (adresses IP, noms d'hôtes). Ces données sont nécessaires pour accéder aux serveurs web via le reverse-proxy et aux bases de données.

</aside>

### 9. Nettoyage

Vous pouvez nettoyer tout le réseau avec le script :

```bash
sudo chmod +x clean_infra.sh
sudo ./clean_infra.sh
```