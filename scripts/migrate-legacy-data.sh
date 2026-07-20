#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Returns 0 if the directory has content or is inaccessible (assume in use).
dir_has_data() {
  local dir="$1"

  if [[ ! -d "$dir" ]]; then
    return 1
  fi

  if ! ls -A "$dir" &>/dev/null; then
    echo "  ${dir} existe pero no es legible; se asume que ya tiene datos (p. ej. creado por Docker)."
    return 0
  fi

  [[ -n "$(ls -A "$dir")" ]]
}

migrate_dir() {
  local legacy="$1"
  local target="$2"

  if [[ ! -d "$legacy" ]]; then
    return 0
  fi

  if ! ls -A "$legacy" &>/dev/null; then
    echo "Omitiendo ${legacy} (vacío o sin permiso de lectura)"
    return 0
  fi

  if [[ -z "$(ls -A "$legacy" 2>/dev/null || true)" ]]; then
    echo "Omitiendo ${legacy} (vacío)"
    return 0
  fi

  mkdir -p "$target"

  if dir_has_data "$target"; then
    echo "Omitiendo ${legacy}: ${target} ya tiene datos"
    return 0
  fi

  echo "Migrando ${legacy} -> ${target}"

  if cp -a "${legacy}/." "${target}/" 2>/dev/null; then
    return 0
  fi

  echo "  Permisos insuficientes; reintentando con sudo (detené el servicio que use ${target} si falla)..."
  sudo cp -a "${legacy}/." "${target}/"
}

migrate_dir "postgres-data" "data/postgres"
migrate_dir "data-redis" "data/redis"
migrate_dir "forgejo/forgejo-data" "data/forgejo"
migrate_dir "uptime-kuma/data" "data/uptime-kuma"

echo "Migración completada. Revisá los datos y eliminá manualmente los directorios legacy si todo está OK."
