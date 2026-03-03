#!/bin/bash

# ╔════════════════════════════════════════════════════════════════════╗
# ║  Script:   install_docker.sh                                        ║
# ║  Autor:    TrastoTech                                               ║
# ║  Descripción: Instalación automatizada de Docker Engine             ║
# ║               con detección de distro, log rotation y usuario       ║
# ║               non-root. Soporta APT, DNF y Zypper.                 ║
# ╚════════════════════════════════════════════════════════════════════╝
set -euo pipefail

echo "=== Instalación de Docker Engine ==="

# ── Guard: idempotencia ───────────────────────────────────────────
if command -v docker &>/dev/null; then
  echo "⚠  Docker ya está instalado: $(docker --version)"
  echo "   Para reinstalar, elimina primero los paquetes existentes."
  exit 0
fi

# ── Detección de distribución ──────────────────────────────────────
if [ ! -f /etc/os-release ]; then
  echo "ERROR: No se puede detectar la distribución (falta /etc/os-release)."
  exit 1
fi

. /etc/os-release
ID_LOWER="${ID,,}"
ID_LIKE_LOWER="${ID_LIKE:-}"
ID_LIKE_LOWER="${ID_LIKE_LOWER,,}"

echo "  Distro detectada: ${PRETTY_NAME:-$ID}"

DISTRO_FAMILY=""
DOCKER_REPO_DISTRO=""
CODENAME=""

case "$ID_LOWER" in
  ubuntu|linuxmint|pop)
    DISTRO_FAMILY="apt"
    DOCKER_REPO_DISTRO="ubuntu"
    CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
    ;;
  debian|raspbian)
    DISTRO_FAMILY="apt"
    DOCKER_REPO_DISTRO="$ID_LOWER"
    CODENAME="${VERSION_CODENAME:-}"
    ;;
  fedora)
    DISTRO_FAMILY="dnf"
    DOCKER_REPO_DISTRO="fedora"
    ;;
  centos|rhel|rocky|almalinux)
    DISTRO_FAMILY="dnf"
    DOCKER_REPO_DISTRO="centos"
    ;;
  opensuse*|sles)
    DISTRO_FAMILY="zypper"
    ;;
  *)
    # Fallback por ID_LIKE (Elementary, Kali, Zorin, etc.)
    if echo "$ID_LIKE_LOWER" | grep -q "ubuntu"; then
      DISTRO_FAMILY="apt"
      DOCKER_REPO_DISTRO="ubuntu"
      CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
    elif echo "$ID_LIKE_LOWER" | grep -q "debian"; then
      DISTRO_FAMILY="apt"
      DOCKER_REPO_DISTRO="debian"
      CODENAME="${VERSION_CODENAME:-}"
    elif echo "$ID_LIKE_LOWER" | grep -q "fedora"; then
      DISTRO_FAMILY="dnf"
      DOCKER_REPO_DISTRO="fedora"
    elif echo "$ID_LIKE_LOWER" | grep -qE "(rhel|centos)"; then
      DISTRO_FAMILY="dnf"
      DOCKER_REPO_DISTRO="centos"
    elif echo "$ID_LIKE_LOWER" | grep -qE "(suse|sles)"; then
      DISTRO_FAMILY="zypper"
    else
      echo "ERROR: Distribución no soportada: ${PRETTY_NAME:-$ID}"
      echo "Soportadas: Ubuntu, Debian, Linux Mint, Fedora, CentOS, RHEL,"
      echo "            Rocky Linux, AlmaLinux, openSUSE, SLES"
      exit 1
    fi
    ;;
esac

echo "  Familia de paquetes: ${DISTRO_FAMILY^^}${DOCKER_REPO_DISTRO:+ -> repo: $DOCKER_REPO_DISTRO}"

# ── 1. Dependencias y repositorio ─────────────────────────────────
echo "[1/5] Configurando repositorio..."

case "$DISTRO_FAMILY" in

  apt)
    if [ -z "$CODENAME" ]; then
      echo "ERROR: No se pudo determinar el codename de la distribución."
      exit 1
    fi
    # Eliminar paquetes conflictivos
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 \
                podman-docker containerd runc; do
      sudo apt-get remove -y "$pkg" 2>/dev/null || true
    done
    sudo apt-get update -qq
    sudo apt-get install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL "https://download.docker.com/linux/${DOCKER_REPO_DISTRO}/gpg" \
      -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    _ARCH="$(dpkg --print-architecture)"
    _KEYRING="signed-by=/etc/apt/keyrings/docker.asc"
    _REPO_URL="https://download.docker.com/linux/${DOCKER_REPO_DISTRO}"
    DOCKER_REPO_LINE="deb [arch=${_ARCH} ${_KEYRING}] ${_REPO_URL} ${CODENAME} stable"
    echo "$DOCKER_REPO_LINE" \
      | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update -qq
    ;;

  dnf)
    # Eliminar paquetes conflictivos
    sudo dnf remove -y docker docker-client docker-client-latest \
      docker-common docker-latest docker-latest-logrotate \
      docker-logrotate docker-engine 2>/dev/null || true
    sudo dnf -y install dnf-plugins-core
    # Compatibilidad con dnf5 (Fedora 41+) y dnf3
    if ! sudo dnf config-manager --add-repo \
        "https://download.docker.com/linux/${DOCKER_REPO_DISTRO}/docker-ce.repo" \
        2>/dev/null; then
      sudo dnf-3 config-manager --add-repo \
        "https://download.docker.com/linux/${DOCKER_REPO_DISTRO}/docker-ce.repo"
    fi
    ;;

  zypper)
    # Repo oficial Docker para SLES; compatible con openSUSE Leap/Tumbleweed
    sudo zypper addrepo \
      https://download.docker.com/linux/sles/docker-ce.repo \
      || sudo zypper modifyrepo -e docker-ce-stable
    sudo zypper --gpg-auto-import-keys refresh
    ;;

esac

# ── 2. Instalar Docker Engine ──────────────────────────────────────
echo "[2/5] Instalando Docker..."

case "$DISTRO_FAMILY" in
  apt)
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
      docker-buildx-plugin docker-compose-plugin
    ;;
  dnf)
    sudo dnf install -y docker-ce docker-ce-cli containerd.io \
      docker-buildx-plugin docker-compose-plugin
    ;;
  zypper)
    sudo zypper install -y docker-ce docker-ce-cli containerd.io \
      docker-buildx-plugin docker-compose-plugin
    ;;
esac

# ── 3. Configurar log rotation (ANTES de iniciar) ─────────────────
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

# ── 4. Habilitar y arrancar Docker ────────────────────────────────
echo "[4/5] Iniciando Docker..."
sudo systemctl enable --now docker.service containerd.service

# ── 5. Añadir usuario al grupo docker ────────────────────────────
echo "[5/5] Configurando usuario..."
sudo groupadd -f docker
ACTUAL_USER="${SUDO_USER:-$USER}"
sudo usermod -aG docker "$ACTUAL_USER"

if [ "$ACTUAL_USER" = "root" ]; then
  echo "Atención: has ejecutado el script como root."
  echo "Añade manualmente tu usuario real al grupo docker con:"
  echo "sudo usermod -aG docker <tu_usuario>"
fi

echo ""
echo "✓ Instalación completada"
echo "✓ Distro: ${PRETTY_NAME:-$ID}"
echo "✓ Usuario $ACTUAL_USER añadido al grupo docker"
echo ""
echo "Cierra sesión y vuelve a entrar, o ejecuta: newgrp docker"
echo ""
docker --version
