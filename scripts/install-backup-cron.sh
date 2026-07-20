#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CRON_LINE="30 3 * * * cd ${ROOT_DIR} && ./scripts/backup.sh >> /mnt/storage/backups/backup.log 2>&1"
MARKER="docker-infra/scripts/backup.sh"

if crontab -l 2>/dev/null | grep -qF "$MARKER"; then
  echo "El cron de backup ya está instalado:"
  crontab -l | grep -F "$MARKER"
  exit 0
fi

(crontab -l 2>/dev/null; echo "$CRON_LINE") | crontab -
echo "Cron instalado (diario a las 03:30):"
echo "  $CRON_LINE"
