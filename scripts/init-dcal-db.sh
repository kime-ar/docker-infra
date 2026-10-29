#!/usr/bin/env bash
# Crea (idempotente) la base `dcal` y su rol dueño `dcal_app` en el Postgres
# compartido. Base propia y no schema: las migraciones de dCal asumen `public`,
# y así el entorno local queda igual que el Postgres dedicado de Railway.
#
# btree_gist (requerido por el EXCLUDE anti doble-reserva) es una extensión
# "trusted" desde PG13: el dueño de la base puede crearla, pero la dejamos
# creada acá como superusuario para no depender de eso.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ ! -f .env ]]; then
  echo "Error: .env no encontrado."
  exit 1
fi

read_env() {
  local key="$1"
  local value
  value="$(grep -E "^${key}=" .env | tail -n1 | cut -d= -f2- || true)"
  value="${value%\"}"; value="${value#\"}"
  value="${value%\'}"; value="${value#\'}"
  if [[ -z "$value" ]]; then
    echo "Error: ${key} no está definido en .env" >&2
    exit 1
  fi
  printf '%s' "$value"
}

DCAL_DB_PASSWORD="$(read_env DCAL_DB_PASSWORD)"

if ! docker ps --format '{{.Names}}' | grep -qx postgres; then
  echo "Error: el contenedor 'postgres' no está corriendo (make up primero)."
  exit 1
fi

echo "==> Rol dcal_app"
docker exec -i postgres psql -v ON_ERROR_STOP=1 -U postgres -d postgres \
  -v pw="$DCAL_DB_PASSWORD" <<'SQL'
SELECT format('CREATE ROLE dcal_app LOGIN PASSWORD %L', :'pw')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'dcal_app')
\gexec
SELECT format('ALTER ROLE dcal_app WITH LOGIN PASSWORD %L', :'pw')
\gexec
SQL

echo "==> Base dcal"
docker exec -i postgres psql -v ON_ERROR_STOP=1 -U postgres -d postgres <<'SQL'
SELECT 'CREATE DATABASE dcal OWNER dcal_app'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'dcal')
\gexec
SQL

echo "==> Extensión btree_gist en dcal"
docker exec -i postgres psql -v ON_ERROR_STOP=1 -U postgres -d dcal \
  -c "CREATE EXTENSION IF NOT EXISTS btree_gist;"

echo "Listo. Levantá dCal con: make up  (o: make dcal-up para solo ese módulo)"