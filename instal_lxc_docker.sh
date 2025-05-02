#!/bin/bash
set -e

# Installation de LXD (Linux Containers Daemon moderne)
echo "== Installation de LXD =="
sudo apt update
sudo apt install -y lxd

# Ajoute l'utilisateur courant au groupe lxd (pour permettre lxc sans sudo)
sudo usermod -aG lxd $USER

# Initialisation (pré-remplie, tu pourras la refaire avec "sudo lxd init")
echo "== Initialisation de LXD (interactive recommandée ensuite) =="

# Installation de Docker (version officielle à jour)
echo "== Installation de Docker =="
sudo apt-get remove -y docker docker-engine docker.io containerd runc || true
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Ajout du user au groupe docker pour éviter sudo docker
sudo usermod -aG docker $USER

# (Optionnel) Installation de git si besoin
echo "== Installation de Git =="
sudo apt install -y git

# Active et démarre Docker au boot
sudo systemctl enable docker
sudo systemctl start docker

echo
echo "== Installation terminée. =="
echo
echo "Déconnecte-toi et reconnecte-toi pour activer les groupes 'docker' et 'lxd' !"
echo "Teste Docker     : docker run hello-world"
echo "Teste LXD (lxc)  : lxc launch images:ubuntu/22.04 testfirst"
echo "Pour configurer LXD : sudo lxd init"
echo "Pour voir les groupes : id"

exit 0