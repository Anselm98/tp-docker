#!/bin/bash
set -e

# Installation de LXC (Linux Containers)
echo "== Installation de LXC =="
sudo apt update
sudo apt install -y lxc lxc-templates lxc-utils uidmap

# Ajout de ton utilisateur courant (si pas déjà fait, évite le sudo à chaque fois)
if ! grep -q "^$(whoami):" /etc/subuid; then
    echo "== Configuration subuid/subgid pour $(whoami) =="
    sudo sh -c "echo '$(whoami):100000:65536' >> /etc/subuid"
    sudo sh -c "echo '$(whoami):100000:65536' >> /etc/subgid"
fi

# Installation de Docker (dépôt officiel et version à jour)
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

# Ajoute l'utilisateur courant au groupe docker pour exécuter docker sans sudo
echo "== Ajout au groupe docker (relogin nécessaire après le script) =="
sudo usermod -aG docker $USER

echo
echo "== Installation terminée. =="
echo "Déconnecte-toi/reconnecte-toi pour activer le groupe docker."
echo "Teste Docker avec : docker run hello-world"
echo "Teste LXC avec : lxc launch images:ubuntu/22.04 monconteneur"

# Conseil optionnel: Active et démarre docker au boot (normalement fait par l’install)
sudo systemctl enable docker
sudo systemctl start docker

exit 0