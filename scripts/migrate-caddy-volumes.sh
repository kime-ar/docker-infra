#!/usr/bin/env bash
# Migra data/caddy y data/caddy_config hacia named volumes de Compose.
# Idempotente: si el volume ya tiene contenido, no pisa nada.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PROJECT="${COMPOSE_PROJECT_NAME:-$(basename "$ROOT_DIR")}"
DATA_VOL="${PROJECT}_caddy_data"
CONFIG_VOL="${PROJECT}_caddy_config"

migrate_one() {
  local vol="$1"
  local src="$2"

  if [[ ! -d "$src" ]] || [[ -z "$(ls -A "$src" 2>/dev/null || true)" ]]; then
    echo "Omitiendo ${src} (vacío o inexistente)"
    return 0
  fi

  docker volume create "$vol" >/dev/null
  # Si el volume ya tiene archivos, no sobrescribir
  local count
  count="$(docker run --rm -v "${vol}:/to" alpine sh -c 'ls -A /to 2>/dev/null | wc -l')"
  if [[ "$count" -gt 0 ]]; then
    echo "Omitiendo ${vol}: ya tiene datos"
    return 0
  fi

  echo "Migrando ${src} -> volume ${vol}"
  docker run --rm \
    -v "${ROOT_DIR}/${src}:/from:ro" \
    -v "${vol}:/to" \
    alpine sh -c 'cp -a /from/. /to/'
}

migrate_one "$DATA_VOL" "data/caddy"
migrate_one "$CONFIG_VOL" "data/caddy_config"

# Asegurar que la CA pública esté disponible para Langfuse
mkdir -p caddy/certs
if [[ ! -f caddy/certs/root.crt ]]; then
  if [[ -f data/caddy/caddy/pki/authorities/local/root.crt ]]; then
    cp -a data/caddy/caddy/pki/authorities/local/root.crt caddy/certs/root.crt
  else
    # Extraer desde el volume ya migrado
    docker run --rm -v "${DATA_VOL}:/data:ro" alpine \
      cat /data/caddy/pki/authorities/local/root.crt > caddy/certs/root.crt
  fi
  chmod 644 caddy/certs/root.crt
fi

echo "Migración de volúmenes Caddy lista."
echo "Tras verificar TLS (git.garatortiz.xyz / *.kime.lan), podés borrar data/caddy y data/caddy_config."
