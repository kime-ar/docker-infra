#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ ! -f .env ]]; then
  echo "Error: .env no encontrado. Copiá .env.example a .env primero."
  exit 1
fi

read_env() {
  local key="$1"
  local default="${2:-}"
  local value

  value="$(grep -E "^${key}=" .env | tail -n1 | cut -d= -f2- || true)"
  if [[ -z "$value" ]]; then
    printf '%s' "$default"
  else
    value="${value%\"}"
    value="${value#\"}"
    value="${value%\'}"
    value="${value#\'}"
    printf '%s' "$value"
  fi
}

MINIO_ROOT_USER="$(read_env MINIO_ROOT_USER minioadmin)"
MINIO_ROOT_PASSWORD="$(read_env MINIO_ROOT_PASSWORD)"
BUCKET="$(read_env LANGFUSE_S3_EVENT_UPLOAD_BUCKET langfuse)"

if [[ -z "$MINIO_ROOT_PASSWORD" ]]; then
  echo "Error: MINIO_ROOT_PASSWORD no está definido en .env"
  exit 1
fi

echo "Creando bucket '${BUCKET}' en MinIO..."
docker run --rm --network dev-network \
  --entrypoint sh \
  minio/mc:latest \
  -c "mc alias set local http://minio:9000 '${MINIO_ROOT_USER}' '${MINIO_ROOT_PASSWORD}' && mc mb --ignore-existing local/${BUCKET}"

echo "Bucket '${BUCKET}' listo."
