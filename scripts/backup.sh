#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ ! -f .env ]]; then
  echo "Error: .env no encontrado."
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

BACKUP_ROOT="${BACKUP_ROOT:-/mnt/storage/backups}"
RETENTION="${RETENTION:-7}"   # cantidad de backups a conservar
STAMP="$(date +%Y-%m-%d_%H%M%S)"
DEST="${BACKUP_ROOT}/${STAMP}"

mkdir -p "$DEST"
echo "==> Backup en ${DEST}"

echo "[1/5] PostgreSQL (pg_dumpall, todas las bases y schemas)..."
docker exec postgres pg_dumpall -U postgres | gzip > "${DEST}/postgres.sql.gz"

echo "[2/5] Redis (BGSAVE + copia del RDB)..."
# REDISCLI_AUTH está definida dentro del contenedor
LAST_SAVE="$(docker exec redis redis-cli LASTSAVE)"
docker exec redis redis-cli BGSAVE > /dev/null
for _ in $(seq 1 30); do
  [[ "$(docker exec redis redis-cli LASTSAVE)" != "$LAST_SAVE" ]] && break
  sleep 1
done
docker cp redis:/data/dump.rdb "${DEST}/redis.rdb" > /dev/null

echo "[3/5] MinIO (mirror de todos los buckets)..."
mkdir -p "${DEST}/minio"
docker run --rm --network dev-network \
  --user "$(id -u):$(id -g)" \
  --env HOME=/tmp \
  -v "${DEST}/minio:/backup" \
  --entrypoint sh \
  minio/mc:latest \
  -c "mc alias set local http://minio:9000 '${MINIO_ROOT_USER}' '${MINIO_ROOT_PASSWORD}' > /dev/null && mc mirror --overwrite local/ /backup"

echo "[4/5] Forgejo (dump nativo: repos + base SQLite + config)..."
docker exec -u 1000:1000 forgejo sh -c \
  'cd /tmp && rm -f forgejo-dump.zip && forgejo dump -c /data/gitea/conf/app.ini -f /tmp/forgejo-dump.zip' > /dev/null
docker cp forgejo:/tmp/forgejo-dump.zip "${DEST}/forgejo-dump.zip" > /dev/null
docker exec forgejo rm -f /tmp/forgejo-dump.zip

echo "[5/5] n8n (clave de cifrado y datos locales) y Uptime Kuma..."
# Sin data/n8n/config (encryption key) las credenciales guardadas en Postgres
# son irrecuperables: este tar es tan importante como el dump de la base.
tar czf "${DEST}/n8n-data.tar.gz" -C data n8n
docker cp uptime-kuma:/app/data "${DEST}/uptime-kuma" > /dev/null

echo "==> Aplicando retención (últimos ${RETENTION} backups)..."
ls -1dt "${BACKUP_ROOT}"/*/ 2>/dev/null | tail -n "+$((RETENTION + 1))" | xargs -r rm -rf

echo "==> Backup OK: $(du -sh "$DEST" | cut -f1) en ${DEST}"
