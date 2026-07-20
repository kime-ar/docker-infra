#!/usr/bin/env bash
set -euo pipefail

sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json > /dev/null <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

echo "Configuración de logs de Docker aplicada en /etc/docker/daemon.json"
echo "Reiniciá Docker para aplicar: sudo systemctl restart docker"
