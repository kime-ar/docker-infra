#!/usr/bin/env bash
# One-shot: borra lo que Plane dejó en una instancia existente (Plane quedó
# descartado del stack). Correr DESPUÉS de sacar plane/ del include y de un
# `make up` (el --remove-orphans baja sus contenedores).
#
# Hace, en orden: verifica que no queden contenedores de Plane, dump de la base
# `plane` a BACKUP_ROOT, DROP DATABASE plane + DROP ROLE plane_app, borra los
# named volumes de Plane y sus imágenes. Pide confirmación antes de borrar.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PROJECT="${COMPOSE_PROJECT_NAME:-$(basename "$ROOT_DIR")}"
BACKUP_ROOT="${BACKUP_ROOT:-/mnt/storage/backups}"
STAMP="$(date +%Y-%m-%d_%H%M%S)"

# Volúmenes declarados en el viejo plane/docker-compose.yml (prefijo del proyecto)
VOLUMES=(redisdata uploads logs_api logs_worker logs_beat-worker logs_migrator
  rabbitmq_data proxy_config proxy_data)

leftover="$(docker ps -a --format '{{.Names}}' \
  | grep -E '(^plane-|-(web|space|admin|live|api|worker|beat-worker|migrator|plane-redis|plane-mq|plane-minio)-[0-9]+$)' \
  | grep -v -E '^dcal-' || true)"
if [[ -n "$leftover" ]]; then
  echo "Todavía hay contenedores que parecen de Plane:"
  echo "$leftover"
  echo "Sacá plane/ del include y corré 'make up' primero (o bajalos a mano)."
  exit 1
fi

has_db="$(docker exec postgres psql -U postgres -Atc \
  "SELECT 1 FROM pg_database WHERE datname = 'plane'")"

echo "Se va a borrar:"
[[ "$has_db" == "1" ]] && echo "  - base 'plane' y rol 'plane_app' (con dump previo en ${BACKUP_ROOT})"
for v in "${VOLUMES[@]}"; do
  docker volume inspect "${PROJECT}_${v}" >/dev/null 2>&1 && echo "  - volume ${PROJECT}_${v}"
done
echo "  - imágenes makeplane/*, valkey/valkey:9.1.2, rabbitmq:4.3.2-management-alpine"
read -r -p "Escribí 'plane' para continuar: " confirm
[[ "$confirm" == "plane" ]] || { echo "Cancelado."; exit 1; }

if [[ "$has_db" == "1" ]]; then
  mkdir -p "$BACKUP_ROOT"
  dump="${BACKUP_ROOT}/plane-final-${STAMP}.sql.gz"
  echo "==> Dump de plane -> ${dump}"
  docker exec postgres pg_dump -U postgres -d plane | gzip > "$dump"
  echo "==> DROP DATABASE plane / DROP ROLE plane_app"
  docker exec -i postgres psql -v ON_ERROR_STOP=1 -U postgres -d postgres <<'SQL'
DROP DATABASE IF EXISTS plane WITH (FORCE);
DROP ROLE IF EXISTS plane_app;
SQL
fi

for v in "${VOLUMES[@]}"; do
  if docker volume inspect "${PROJECT}_${v}" >/dev/null 2>&1; then
    echo "==> volume rm ${PROJECT}_${v}"
    docker volume rm "${PROJECT}_${v}" >/dev/null
  fi
done

echo "==> Imágenes"
mapfile -t images < <(docker images --format '{{.Repository}}:{{.Tag}}' \
  | grep -E '^(makeplane/|valkey/valkey:9\.1\.2$|rabbitmq:4\.3\.2-management-alpine$)' || true)
if (( ${#images[@]} )); then
  docker rmi "${images[@]}" || true
fi

echo "Plane eliminado. Quitá PLANE_* de .env y el registro DNS 'plane' si lo tenés explícito."