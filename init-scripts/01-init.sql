-- 1. Asegurar la extensión de vectores en la base de datos raíz
CREATE EXTENSION IF NOT EXISTS vector;

-- 2. Crear los Schemas aislados para tu ecosistema de proyectos
CREATE SCHEMA IF NOT EXISTS n8n;
CREATE SCHEMA IF NOT EXISTS langfuse;
CREATE SCHEMA IF NOT EXISTS silphcore;
CREATE SCHEMA IF NOT EXISTS landingo;
CREATE SCHEMA IF NOT EXISTS sonar;
-- apps ejecutadas desde n8n (02-app-roles.sh le asigna dueño)
CREATE SCHEMA IF NOT EXISTS n8n_apps_schema;
