#!/usr/bin/env bash
# Se ejecuta automáticamente SOLO en el primer initdb de una instalación nueva
# (docker-entrypoint-initdb.d). Crea un rol por aplicación, dueño únicamente
# de su schema, para no compartir el superusuario entre apps.
set -euo pipefail

: "${N8N_DB_PASSWORD:?}"
: "${LANGFUSE_DB_PASSWORD:?}"
: "${SONAR_DB_PASSWORD:?}"

psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres <<SQL
CREATE ROLE n8n_app      LOGIN PASSWORD '${N8N_DB_PASSWORD}';
CREATE ROLE langfuse_app LOGIN PASSWORD '${LANGFUSE_DB_PASSWORD}';
CREATE ROLE sonar_app    LOGIN PASSWORD '${SONAR_DB_PASSWORD}';

ALTER SCHEMA n8n      OWNER TO n8n_app;
ALTER SCHEMA langfuse OWNER TO langfuse_app;
ALTER SCHEMA sonar    OWNER TO sonar_app;

-- n8n (TypeORM) ejecuta CREATE SCHEMA al arrancar aunque el schema exista,
-- lo que requiere CREATE sobre la base de datos.
GRANT CREATE ON DATABASE postgres TO n8n_app;

-- public queda al final para poder usar extensiones (ej. vector) sin calificar
ALTER ROLE n8n_app      IN DATABASE postgres SET search_path = n8n, public;
ALTER ROLE langfuse_app IN DATABASE postgres SET search_path = langfuse, public;
ALTER ROLE sonar_app    IN DATABASE postgres SET search_path = sonar, public;
SQL
