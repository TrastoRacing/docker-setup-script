# Docker Engine - Script de Instalación

Script automatizado para instalar Docker Engine en Ubuntu/Debian con configuración optimizada.

## Instalación rápida
```
curl -O https://raw.githubusercontent.com/TrastoRacing/docker-setup-script/main/install_docker.sh
chmod +x install_docker.sh
sudo ./install_docker.sh
newgrp docker
```
**Verificar versiones:**
```
docker --version
docker compose version
```
## Incluye

- Docker Engine (última versión estable)
- Docker Compose v2
- Docker Buildx
- Containerd
- Log rotation (10MB, 3 archivos)
- Usuario non-root configurado
- Inicio automático en boot
