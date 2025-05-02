#!/bin/bash
set -e

echo "== Installation de Docker (version officielle) =="

# Désinstalle les éventuels vieux paquets Docker
sudo apt-get remove -y docker docker-engine docker.io containerd runc || true

sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release

# Ajout de la clé GPG officielle Docker
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Ajout du dépôt officiel Docker à APT sources
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Met l'utilisateur courant dans le groupe docker (pour éviter sudo à chaque fois)
sudo usermod -aG docker $USER

# Active et démarre Docker au boot
sudo systemctl enable docker
sudo systemctl start docker

echo
echo "== Installation terminée. =="
echo "Déconnecte-toi et reconnecte-toi pour activer le groupe 'docker'."
echo "Teste Docker : docker run hello-world"
echo "Teste Git    : git --version"
echo "Pour voir les groupes : id"

exit 0