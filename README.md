# Kime Infra

Infraestructura Docker auto-alojada para desarrollo, automatización y experimentación con IA. Un único Compose maestro orquesta proxy, datos, Git, workflows y observabilidad detrás de un `Makefile` de operaciones.

![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=for-the-badge&logo=docker&logoColor=white)
![Postgres](https://img.shields.io/badge/postgres-%23316192.svg?style=for-the-badge&logo=postgresql&logoColor=white)
![Redis](https://img.shields.io/badge/redis-%23DD0031.svg?style=for-the-badge&logo=redis&logoColor=white)
![Caddy](https://img.shields.io/badge/Caddy-lightgrey?style=for-the-badge&logo=caddy&logoColor=111111)
![n8n](https://img.shields.io/badge/n8n-FF6D5A?style=for-the-badge&logo=n8n&logoColor=white)
![Langfuse](https://img.shields.io/badge/Langfuse-Observabilidad-black?style=for-the-badge)

---

## Arquitectura

```text
Internet / LAN
      │
      ▼
   [Caddy]  ── edge ──► Homepage, n8n, Forgejo, Langfuse, SonarQube,
                         Release Dashboard, Uptime Kuma, Mailpit UI,
                         MinIO, Portainer
      │
      │   (solo consumidores de datos; Caddy no llega a Postgres)
      ▼
   [data]   ── Postgres · Redis · MinIO · Mailpit (SMTP)
      │
      └── también en [dev-network] ──► apps de repositories/
```

| Red | Rol |
|-----|-----|
| `edge` | Ingress: Caddy y todo lo que proxya |
| `data` | Capa de datos (`internal`: sin salida a internet) |
| `dev-network` | Red permanente para apps externas en `repositories/` |
| `ci-jobs` | Jobs del runner de Forgejo. Alcanzan Forgejo + SonarQube; **no** Postgres/Redis/MinIO |

**Stack:** Caddy · Postgres 16 + pgvector · Redis 7 · MinIO · Forgejo + runner · n8n · Langfuse · SonarQube · Release Dashboard · Homepage (vía docker-socket-proxy) · Uptime Kuma · Mailpit · Portainer (opcional) · Watchtower (solo servicios con label).

**Prácticas aplicadas:** secretos solo en `.env`, roles de Postgres por app, usuario S3 dedicado para Langfuse, límites de recursos, healthchecks en cascada, backups automatizables, imágenes pineadas.

---

## Prerrequisitos

- Ubuntu/Debian con **Docker** y **Docker Compose** (v2)
- `make` (`sudo apt install make`)
- DNS en Cloudflare: registros **A** de cada subdominio → IP LAN del servidor, **proxy OFF** (tráfico local; certs Let's Encrypt vía DNS challenge)
- Disco de backups recomendado en `/mnt/storage` (ajustable)

---

## Instalación limpia (desde cero)

### 1. Clonar

```bash
mkdir -p ~/projects && cd ~/projects
git clone <url-del-repo> docker-infra
cd docker-infra
```

### 2. Configurar secretos

```bash
cp .env.example .env
```

Editá `.env` y reemplazá **todos** los placeholders. Generadores útiles:

```bash
openssl rand -hex 24    # passwords (Postgres apps, Redis, MinIO app)
openssl rand -base64 32 # tokens Forgejo / Langfuse
```

Variables críticas:

| Variable | Para qué |
|----------|----------|
| `HOST_IP` | IP del host (APIs en desarrollo vía Caddy) |
| `DOCKER_SOCKET` | Ruta del socket (`/var/run/docker.sock` en instalaciones nativas) |
| `DOCKER_GID` | GID del grupo `docker` del host (runners de Forgejo) |
| `FORGEJO_GIT_STORAGE` | Disco de repos Git (ej. `/mnt/storage/forgejo-data`) |
| `POSTGRES_PASSWORD` | Superusuario Postgres (solo admin / migraciones) |
| `N8N_DB_PASSWORD`, `LANGFUSE_DB_PASSWORD`, `SONAR_DB_PASSWORD`, `N8N_APPS_DB_PASSWORD` | Roles por app |
| `REDIS_PASSWORD` | Auth de Redis |
| `MINIO_ROOT_*` + `LANGFUSE_S3_*` | Root MinIO + usuario de Langfuse |
| `CLOUDFLARE_API_TOKEN` | ACME DNS para dominio público de Forgejo |
| `FORGEJO_*`, `NEXTAUTH_*`, `SALT` | Secretos de apps |

> En un install nuevo, `init-scripts/` crea schemas y roles automáticamente en el **primer** arranque de Postgres. No hace falta correr `migrate-db-roles.sh`.

### 3. (Opcional) Logging de Docker

Limita el tamaño de logs del daemon para no llenar el disco:

```bash
bash scripts/setup-docker-logging.sh
# luego: sudo systemctl restart docker
```

### 4. Levantar

```bash
make up
```

Esto crea redes/volumes si faltan y arranca todo en orden (respeta healthchecks de Postgres/Redis/MinIO).

### 5. Post-install obligatorio

```bash
# Bucket S3 + usuario langfuse-app (política limitada al bucket)
make init-minio

# Cron diario de backup a las 03:30 → /mnt/storage/backups/
make backup-cron
```

### 6. Portainer (opcional)

Si **no** tenés Portainer ya corriendo:

```bash
COMPOSE_PROFILES=portainer make up
```

Si Portainer ya existe como contenedor standalone en la red `edge`, **no** actives el profile (conflicto de nombre).

### 7. Verificar

```bash
make ps
make logs app=caddy   # Ctrl+C para salir
```

Dominios (TLS Let's Encrypt vía Cloudflare DNS; tráfico en LAN):

| URL | Servicio | Upstream |
|-----|----------|----------|
| https://home.garatortiz.xyz | Homepage | `homepage:3000` |
| https://n8n.garatortiz.xyz | n8n | `n8n:5678` |
| https://ai.garatortiz.xyz | Langfuse | `langfuse-web:3000` |
| https://sonar.garatortiz.xyz | SonarQube | `sonarqube:9000` |
| https://status.garatortiz.xyz | Uptime Kuma | `uptime-kuma:3001` |
| https://mail.garatortiz.xyz | Mailpit UI | `mailpit:8025` |
| https://s3.garatortiz.xyz | MinIO API S3 | `minio:9000` |
| https://minio.garatortiz.xyz | MinIO consola | `minio:9001` |
| https://docker.garatortiz.xyz | Portainer | `portainer:9443` |
| https://git.garatortiz.xyz | Forgejo | `forgejo:3000` |
| https://releases.garatortiz.xyz | Release Dashboard | `release-dashboard:3000` (basic auth) |
| https://api-local.garatortiz.xyz | API host | `{$HOST_IP}:3500` |
| https://admin.garatortiz.xyz | Admin host | `:3501` |
| https://\*.admin.garatortiz.xyz | Previews admin | `:3501` |
| https://kime.garatortiz.xyz | App Kime | `:3502` |
| https://landing.garatortiz.xyz | Landing | `:3503` |
| https://loyalty.garatortiz.xyz | Loyalty | `:3504` |
| https://cows.garatortiz.xyz | Cows | `:3505` |
| https://blog.garatortiz.xyz | Blog | `:3506` |
| https://lab.garatortiz.xyz | Lab | `:3507` |
| https://aka.garatortiz.xyz | Aka | `:3508` |
| https://radar84.garatortiz.xyz | Radar84 | `:3509` |
| `host:2323` | Forgejo SSH | — |

---

## Layout recomendado en el servidor

```text
projects/
├── docker-infra/     # este repositorio (plataforma)
└── repositories/     # tus APIs, bots, frontends
```

Las apps de `repositories/` se conectan a Postgres/Redis/MinIO uniéndose a la red **`dev-network`** en su propio Compose. Esa red es permanente: no se migra ni se elimina.

```yaml
# ejemplo en repositories/mi-api/docker-compose.yml
networks:
  dev-network:
    external: true

services:
  mi-api:
    networks: [dev-network]
    environment:
      DATABASE_URL: postgresql://...@postgres:5432/postgres?schema=...
```

### Qué va en git vs runtime

| En git | Fuera de git |
|--------|----------------|
| `docker-compose.yml`, módulos, `Caddyfile` | `.env` |
| `caddy/certs/root.crt` (CA pública) | Named volumes `docker-infra_caddy_*` (TLS/ACME) |
| `homepage/config/`, `init-scripts/`, `scripts/` | `data/` (Postgres, n8n, Forgejo, etc.) |
| `.env.example`, `Makefile` | `forgejo/runner-data/` |

---

## Panel de control (`make help`)

Todos los comandos se ejecutan desde la raíz del repo (`docker-infra/`).

### Ciclo de vida

| Comando | Qué hace |
|---------|----------|
| `make up` | Crea redes/volumes si faltan y levanta todo (`up -d --remove-orphans`) |
| `make down` | Apaga y elimina contenedores del proyecto (datos en disco/volumes se conservan) |
| `make restart` | `down` + espera + `up` completo (recrea contenedores) |
| `make restart-one app=<servicio>` | Reinicia un solo servicio sin tocar el resto |
| `make ps` | Lista contenedores y estado |
| `make logs` | Logs de todo el stack (seguir con Ctrl+C) |
| `make logs app=<servicio>` | Logs de un servicio (ej. `make logs app=n8n`) |
| `make pull` | Descarga imágenes actualizadas (respetando tags pineados) |

Nombres de servicio útiles para `app=`:

`postgres` · `redis` · `minio` · `mailpit` · `caddy` · `server` (Forgejo) · `runner` · `n8n` · `langfuse-web` · `langfuse-worker` · `sonarqube` · `homepage` · `docker-socket-proxy` · `uptime-kuma` · `release-dashboard` · `watchtower`

### Datos y provisión

| Comando | Qué hace |
|---------|----------|
| `make init-minio` | Crea bucket `langfuse` + usuario `langfuse-app` con política acotada |
| `make migrate-legacy` | Mueve directorios antiguos (`postgres-data/`, etc.) a `data/` |
| `make migrate-caddy` | Copia `data/caddy*` a named volumes (idempotente) |

Migración de roles Postgres en una instancia **ya existente** (no hace falta en install limpio):

```bash
bash scripts/migrate-db-roles.sh
make restart-one app=n8n
make restart-one app=langfuse-web
make restart-one app=langfuse-worker
make restart-one app=sonarqube
```

### Backups

| Comando | Qué hace |
|---------|----------|
| `make backup` | Backup inmediato a `/mnt/storage/backups/<timestamp>/` |
| `make backup-cron` | Instala cron diario (03:30), log en `/mnt/storage/backups/backup.log` |

Cada backup incluye: `pg_dumpall`, Redis RDB, mirror MinIO, dump nativo de Forgejo, tar de `data/n8n` (clave de cifrado) y datos de Uptime Kuma. Retención: últimos 7.

Variable opcional: `BACKUP_ROOT=/otra/ruta make backup`.

### Limpieza

| Comando | Qué hace |
|---------|----------|
| `make clean` | `down --remove-orphans` + prune de imágenes dangling |
| `make clean-all` | **Destructivo** en todo el Docker del host (pide escribir `yes`) |

`make down` / `make clean` **no** borran `data/` ni los volumes de Caddy. `make clean-all` sí puede borrar volumes del sistema entero: usalo solo con backups previos.

---

## Operaciones de mantenimiento

### Alta (arranque diario / después de reboot)

```bash
cd ~/projects/docker-infra
make up
make ps
```

Los servicios tienen `restart: unless-stopped`: tras un reboot del host suelen volver solos si el daemon de Docker arranca. Si no, `make up`.

### Baja (apagar sin perder datos)

```bash
make down
```

### Restart total vs parcial

```bash
# Todo el stack (recrea contenedores; útil tras cambios grandes de compose)
make restart

# Un solo servicio (rápido; no recrea, solo reinicia el proceso)
make restart-one app=n8n
make restart-one app=caddy
```

Tras editar el `Caddyfile` o variables de entorno de un servicio, preferí recrear ese servicio:

```bash
docker compose --env-file .env up -d --force-recreate caddy
# o, para aplicar todo lo pendiente:
make up
```

### Actualizar imágenes

```bash
make pull
make up
```

Los tags están pineados (n8n, MinIO, Caddy, runner, etc.). Renovate puede proponer bumps vía PR.

### Rebuild de Caddy (plugin Cloudflare)

```bash
docker compose --env-file .env build caddy
docker compose --env-file .env up -d caddy
```

### Agregar / quitar un módulo del stack

1. Editá el `include:` en `docker-compose.yml` (o el `profiles` de Portainer).
2. `make up` para aplicar; `make down` no es obligatorio.
3. Huérfanos: `make up` ya usa `--remove-orphans`.

### Conectar una app nueva de `repositories/`

1. Red `dev-network` (external).
2. Credenciales propias (ideal: rol + schema en Postgres; plantilla en `scripts/migrate-db-roles.sh`).
3. No montes el socket de Docker ni te unas a `ci-jobs` salvo que sepas por qué.

Runners offline de Forgejo (requiere `curl` y `jq`):

```bash
FORGEJO_TOKEN=... FORGEJO_URL=https://git.garatortiz.xyz bash scripts/clean-forgejo-runners.sh
```

Desde un workflow de Forgejo Actions, SonarQube se alcanza por la red interna del runner:

```bash
# Secret / variable del repo de la app
SONAR_HOST_URL=http://sonarqube:9000
```

(`https://sonar.garatortiz.xyz` es solo para el navegador vía Caddy; el scanner en `ci-jobs` debe usar el hostname Docker.)

### Desarrollo en el host (`pnpm start:dev`, Nest, etc.)

Las apps de `repositories/` que corren **en el host** (no en Docker) usan una superficie TCP solo en **localhost del servidor**. No están expuestas a la LAN.

| Servicio | Bind | Notas |
|----------|------|--------|
| Postgres | `127.0.0.1:5432` | User/schema propios; password del `.env` de la infra |
| Redis | `127.0.0.1:6379` | Requiere `REDIS_PASSWORD` |
| MinIO (API S3) | `127.0.0.1:9000` | `MINIO_ROOT_*` o usuario de app; path-style |
| Mailpit (SMTP) | `127.0.0.1:1025` | Sin auth típica en lab |
| Consola MinIO / UI Mailpit / Langfuse / … | `https://*.garatortiz.xyz` | Vía Caddy (Let's Encrypt) |

Ejemplo de variables para una API en el host (ajustá nombres a tu app):

```bash
DATABASE_URL=postgresql://USER:PASS@127.0.0.1:5432/postgres?schema=silphcore
REDIS_HOST=127.0.0.1
REDIS_PORT=6379
REDIS_PASSWORD=<REDIS_PASSWORD de docker-infra/.env>
# o: REDIS_URL=redis://:<REDIS_PASSWORD>@127.0.0.1:6379

S3_ENDPOINT=http://127.0.0.1:9000
S3_ACCESS_KEY_ID=<MINIO_ROOT_USER o key de app>
S3_SECRET_ACCESS_KEY=<MINIO_ROOT_PASSWORD o secret de app>
S3_FORCE_PATH_STYLE=true

SMTP_HOST=127.0.0.1
SMTP_PORT=1025
```

Si la app corre **como contenedor** en `dev-network`, usá hostnames Docker (`postgres`, `redis`, `minio`, `mailpit`) y **no** hace falta esta superficie localhost.

### Conectar desde la Mac (DBeaver / clientes)

Los puertos solo escuchan en el servidor. Desde la Mac usá túnel SSH (o el SSH Tunnel de DBeaver):

```bash
ssh -N -p 2222 -L 5432:127.0.0.1:5432 matias@<IP_DEL_SERVIDOR>
# opcional: -L 6379:127.0.0.1:6379 -L 9000:127.0.0.1:9000
```

| Campo DBeaver | Valor |
|---------------|--------|
| Host | `127.0.0.1` |
| Port | `5432` |
| Database | `postgres` |
| User | `postgres` o un rol de app (`n8n_app`, …) |
| Password | el del `.env` correspondiente |
| Schema (opcional) | `n8n`, `langfuse`, `sonar`, `silphcore`, … |
| SSH (si usás el de DBeaver) | host del servidor, puerto `2222`, user `matias` |

### Restaurar desde backup (resumen)

```bash
# Postgres
gunzip -c /mnt/storage/backups/<ts>/postgres.sql.gz | docker exec -i postgres psql -U postgres

# Forgejo: usar el zip del dump nativo (ver docs de forgejo dump)
# n8n: restaurar data/n8n desde n8n-data.tar.gz ANTES de levantar n8n
# MinIO: mc mirror desde el directorio minio/ del backup
```

---

## Referencia rápida de comandos

```bash
make help                 # lista todo
make up                   # alta
make down                 # baja
make restart              # restart total
make restart-one app=n8n  # restart de un servicio
make ps                   # estado
make logs app=caddy       # logs
make pull                 # pull de imágenes
make init-minio           # provisionar S3
make backup               # backup ahora
make backup-cron          # instalar cron
make migrate-legacy       # layouts antiguos → data/
make migrate-caddy        # data/caddy → named volumes
make clean                # down + prune dangling
```

---

## Serie del blog

* [ ] **Parte 1: La Fundación** (Orquestación, Zero-Trust y Proxy Inverso con Caddy). *(Próximamente)*
* [ ] **Parte 2: La Capa de Datos** (PostgreSQL + pgvector, Redis y MinIO). *(Próximamente)*
* [ ] **Parte 3: El Motor del Lab** (Forgejo, n8n y Mailpit). *(Próximamente)*
* [ ] **Parte 4: Operaciones de Día 2** (Observabilidad, backups y prevención de disco lleno). *(Próximamente)*

---

*Hecho con ☕ y buenas prácticas DevOps.*
