#!/usr/bin/env bash
# Borra runners offline de Forgejo, página 1, hasta que no quede ninguno.
# Uso: FORGEJO_TOKEN=... FORGEJO_URL=https://git.garatortiz.xyz bash scripts/clean-forgejo-runners.sh
set -euo pipefail

: "${FORGEJO_TOKEN:?Necesitás exportar FORGEJO_TOKEN}"
: "${FORGEJO_URL:?Necesitás exportar FORGEJO_URL}"

while :; do
  body=$(curl -fsS -H "Authorization: token ${FORGEJO_TOKEN}" \
    "${FORGEJO_URL}/api/v1/user/actions/runners?limit=50&page=1")

  mapfile -t offline_ids < <(jq -r '.[]? | select(.status=="offline") | .id' <<<"${body}")

  if ((${#offline_ids[@]} == 0)); then
    echo "No quedan runners offline en la página 1."
    break
  fi

  for id in "${offline_ids[@]}"; do
    echo -n "Borrando runner id=${id}... "
    code=$(curl -sS -o /dev/null -w '%{http_code}' -X DELETE \
      -H "Authorization: token ${FORGEJO_TOKEN}" \
      "${FORGEJO_URL}/api/v1/user/actions/runners/${id}")
    echo "HTTP ${code}"
  done
done

echo "Listo. Total restante:"
curl -fsS -H "Authorization: token ${FORGEJO_TOKEN}" \
  "${FORGEJO_URL}/api/v1/user/actions/runners?limit=1&page=1" -D - -o /dev/null | grep -i x-total-count
