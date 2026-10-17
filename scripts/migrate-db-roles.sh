#!/usr/bin/env bash
# Migración one-shot para instancias EXISTENTES de Postgres: crea los roles por
# aplicación (idempotente) y transfiere la propiedad de los objetos ya creados
# en cada schema (tablas, secuencias, vistas, funciones) al rol correspondiente.
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

migrate_app() {
  local role="$1"
  local schema="$2"
  local password="$3"

  echo "==> Rol ${role} <- schema ${schema}"
  docker exec -i postgres psql -v ON_ERROR_STOP=1 -U postgres -d postgres <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${role}') THEN
    CREATE ROLE ${role} LOGIN;
  END IF;
END
\$\$;

ALTER ROLE ${role} WITH LOGIN PASSWORD '${password}';
ALTER ROLE ${role} IN DATABASE postgres SET search_path = ${schema}, public;
ALTER SCHEMA ${schema} OWNER TO ${role};

DO \$\$
DECLARE r record;
BEGIN
  FOR r IN SELECT tablename AS name FROM pg_tables WHERE schemaname = '${schema}' LOOP
    EXECUTE format('ALTER TABLE ${schema}.%I OWNER TO ${role}', r.name);
  END LOOP;
  FOR r IN SELECT sequencename AS name FROM pg_sequences WHERE schemaname = '${schema}' LOOP
    EXECUTE format('ALTER SEQUENCE ${schema}.%I OWNER TO ${role}', r.name);
  END LOOP;
  FOR r IN SELECT viewname AS name FROM pg_views WHERE schemaname = '${schema}' LOOP
    EXECUTE format('ALTER VIEW ${schema}.%I OWNER TO ${role}', r.name);
  END LOOP;
  FOR r IN SELECT matviewname AS name FROM pg_matviews WHERE schemaname = '${schema}' LOOP
    EXECUTE format('ALTER MATERIALIZED VIEW ${schema}.%I OWNER TO ${role}', r.name);
  END LOOP;
  FOR r IN
    SELECT p.proname AS name, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = '${schema}' AND p.prokind IN ('f', 'p')
  LOOP
    EXECUTE format('ALTER ROUTINE ${schema}.%I(%s) OWNER TO ${role}', r.name, r.args);
  END LOOP;
END
\$\$;
SQL
}

migrate_app n8n_app      n8n      "$(read_env N8N_DB_PASSWORD)"
migrate_app langfuse_app langfuse "$(read_env LANGFUSE_DB_PASSWORD)"
migrate_app sonar_app    sonar    "$(read_env SONAR_DB_PASSWORD)"

# n8n (TypeORM) ejecuta CREATE SCHEMA al arrancar aunque el schema exista.
docker exec postgres psql -v ON_ERROR_STOP=1 -U postgres -d postgres \
  -c "GRANT CREATE ON DATABASE postgres TO n8n_app;"

docker exec postgres psql -v ON_ERROR_STOP=1 -U postgres -d postgres \
  -c "CREATE SCHEMA IF NOT EXISTS n8n_apps_schema;"
migrate_app n8n_apps n8n_apps_schema "$(read_env N8N_APPS_DB_PASSWORD)"

echo "Migración de roles completada. Reiniciá n8n, Langfuse y SonarQube con sus nuevas credenciales."
