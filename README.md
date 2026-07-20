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
                         Uptime Kuma, Mailpit UI, MinIO, Portainer
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
| `ci-jobs` | Jobs del runner de Forgejo (sin acceso a la capa de datos) |

**Stack:** Caddy · Postgres 16 + pgvector · Redis 7 · MinIO · Forgejo + runner · n8n · Langfuse · SonarQube · Homepage (vía docker-socket-proxy) · Uptime Kuma · Mailpit · Portainer (opcional).

**Prácticas aplicadas:** secretos solo en `.env`, roles de Postgres por app, usuario S3 dedicado para Langfuse, límites de recursos, healthchecks en cascada, backups automatizables, imágenes pineadas.

---

## Prerrequisitos

- Ubuntu/Debian con **Docker** y **Docker Compose** (v2)
- `make` (`sudo apt install make`)
- DNS local o hosts para `*.kime.lan` apuntando al servidor (y el dominio público de Forgejo si aplica)
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
| `FORGEJO_GIT_STORAGE` | Disco de repos Git (ej. `/mnt/storage/forgejo-data`) |
| `POSTGRES_PASSWORD` | Superusuario Postgres (solo admin / migraciones) |
| `N8N_DB_PASSWORD`, `LANGFUSE_DB_PASSWORD`, `SONAR_DB_PASSWORD` | Roles por app |
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

Dominios típicos (TLS interno `.lan`, excepto Forgejo público):

| URL | Servicio |
|-----|----------|
| https://home.kime.lan | Homepage |
| https://n8n.kime.lan | n8n |
| https://ai.kime.lan | Langfuse |
| https://sonar.kime.lan | SonarQube |
| https://status.kime.lan | Uptime Kuma |
| https://mail.kime.lan | Mailpit |
| https://s3.kime.lan | MinIO API S3 |
| https://minio.kime.lan | MinIO consola |
| https://docker.kime.lan | Portainer |
| https://git.garatortiz.xyz | Forgejo |
| `host:2323` | Forgejo SSH |

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

`postgres` · `redis` · `minio` · `mailpit` · `caddy` · `server` (Forgejo) · `runner` · `n8n` · `langfuse-web` · `langfuse-worker` · `sonarqube` · `homepage` · `docker-socket-proxy` · `uptime-kuma`

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
