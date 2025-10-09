#!/bin/bash

# ╔════════════════════════════════════════════════════════════════════╗
# ║  Script:   install_docker.sh                                        ║
# ║  Autor:    TrastoTech                                               ║
# ║  Descripción: Instalación automatizada de Docker Engine             ║
# ║               con configuración de log rotation y usuario non-root  ║
# ╚════════════════════════════════════════════════════════════════════╝
set -euo pipefail

echo "=== Instalación de Docker Engine ==="

# 1. Dependencias y repositorio
echo "[1/5] Configurando repositorio..."
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/keyrings/docker.asc > /dev/null
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update

# 2. Instalar Docker Engine
echo "[2/5] Instalando Docker..."
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 3. Configurar log rotation (ANTES de iniciar)
echo "[3/5] Configurando log rotation..."
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

# 4. Habilitar y arrancar Docker
echo "[4/5] Iniciando Docker..."
sudo systemctl enable --now docker.service containerd.service

# 5. Añadir usuario al grupo docker
echo "[5/5] Configurando usuario..."
sudo groupadd -f docker
ACTUAL_USER=${SUDO_USER:-$USER}
sudo usermod -aG docker "$ACTUAL_USER"

# Aviso si se ejecuta como root
if [ "$ACTUAL_USER" = "root" ]; then
  echo "Atención: has ejecutado el script como root."
  echo "Añade manualmente tu usuario real al grupo docker con:"
  echo "sudo usermod -aG docker <tu_usuario>"
fi

echo ""
echo "✓ Instalación completada"
echo "✓ Usuario $ACTUAL_USER añadido al grupo docker"
echo ""
echo "Cierra sesión y vuelve a entrar, o ejecuta: newgrp docker"
echo ""
docker --version
