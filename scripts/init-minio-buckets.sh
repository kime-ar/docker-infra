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
LANGFUSE_S3_ACCESS_KEY="$(read_env LANGFUSE_S3_ACCESS_KEY langfuse-app)"
LANGFUSE_S3_SECRET_KEY="$(read_env LANGFUSE_S3_SECRET_KEY)"

if [[ -z "$MINIO_ROOT_PASSWORD" ]]; then
  echo "Error: MINIO_ROOT_PASSWORD no está definido en .env"
  exit 1
fi

if [[ -z "$LANGFUSE_S3_SECRET_KEY" ]]; then
  echo "Error: LANGFUSE_S3_SECRET_KEY no está definido en .env"
  exit 1
fi

POLICY_NAME="langfuse-rw"

echo "Creando bucket '${BUCKET}' y usuario '${LANGFUSE_S3_ACCESS_KEY}' (política ${POLICY_NAME}) en MinIO..."
docker run --rm --network data \
  --entrypoint sh \
  -e MINIO_ROOT_USER="$MINIO_ROOT_USER" \
  -e MINIO_ROOT_PASSWORD="$MINIO_ROOT_PASSWORD" \
  -e ACCESS_KEY="$LANGFUSE_S3_ACCESS_KEY" \
  -e SECRET_KEY="$LANGFUSE_S3_SECRET_KEY" \
  -e BUCKET="$BUCKET" \
  -e POLICY_NAME="$POLICY_NAME" \
  minio/mc:latest \
  -c '
    set -e
    mc alias set local http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" > /dev/null
    mc mb --ignore-existing "local/$BUCKET"
    cat > /tmp/policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:*"],
      "Resource": [
        "arn:aws:s3:::$BUCKET",
        "arn:aws:s3:::$BUCKET/*"
      ]
    }
  ]
}
EOF
    mc admin policy create local "$POLICY_NAME" /tmp/policy.json
    mc admin user add local "$ACCESS_KEY" "$SECRET_KEY"
    mc admin policy attach local "$POLICY_NAME" --user "$ACCESS_KEY" || true
  '

echo "Bucket '${BUCKET}' y usuario '${LANGFUSE_S3_ACCESS_KEY}' listos."
