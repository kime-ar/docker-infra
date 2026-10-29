# dCal en Kime Infra

Entorno de pruebas de [dCal / Dapta Calendars](https://github.com/Dapta-Tech/dapta-calendars-slate) (MIT): agenda tipo Calendly con servidor MCP para agentes. Se buildea desde el clon con los mismos Dockerfiles que Railway, así lo que probás acá es el mismo artefacto que va a prod.

| URL | Servicio | Upstream |
|-----|----------|----------|
| https://cal.garatortiz.xyz | dCal web (booking + dashboard) | `dcal-web:3000` |
| https://cal-api.garatortiz.xyz | dCal API + MCP (`/mcp`) | `dcal-api:4000` |

## Alta

```bash
# 1. Clonar upstream junto al resto de repos (pineá un commit si querés reproducibilidad)
cd ~/projects/repositories
git clone https://github.com/Dapta-Tech/dapta-calendars-slate.git dcal

# 2. Secretos en docker-infra/.env (ver bloque "dCal" en .env.example)

# 3. DNS en Cloudflare: A cal + cal-api → IP LAN, proxy OFF

# 4. Base + rol + btree_gist en el Postgres compartido (idempotente)
cd ~/projects/docker-infra
make init-dcal

# 5. Build + levantar (migraciones corren solas en dcal-migrate)
make dcal-up
docker compose --env-file .env up -d --force-recreate caddy   # nuevos hosts/aliases
```

Actualizar a la última versión upstream: `make dcal-update` (git pull + rebuild + up).

## Decisiones

- **Base `dcal` propia, rol `dcal_app` dueño** (patrón Plane, no schema): las migraciones Drizzle asumen `public` y así queda igual que el Postgres dedicado de Railway. Entra solo en `make backup` vía `pg_dumpall`.
- **Mails a Mailpit** (`EMAIL_PROVIDER=smtp`, `mailpit:1025`): confirmaciones, reprogramaciones y recordatorios se ven en https://mail.garatortiz.xyz.
- **Servicios prefijados `dcal-*`**: Plane ya usa `api` y `web`, y con `include:` los nombres son globales.
- **Web → API por red interna** (`API_URL=http://dcal-api:4000` + `INTERNAL_API_SECRET`): el rate limit cuenta por visitante y no por el server del web.
- **Sin label de Watchtower**: imagen local, se actualiza con `make dcal-update`.

## Lo que hay que saber antes de prod

1. **Auth del dashboard.** El OSS trae dos providers: `local` (stub sin autenticación; la API se niega a arrancar con `NODE_ENV=production`) y `workos`, que en realidad es un verificador genérico de JWT HS256 (`sub`, `account_id`, `email`, `name`) firmado con un secreto compartido. El login web con `workos` redirige a un servicio de identidad (`IAM_BASE_URL`) que **no viene en el repo**. En local se usa `local` (LAN only); para Railway hace falta poner algo que emita esos JWT: un IAM propio mínimo, o adaptar el provider a algo que ya tengas (ej. el auth de silph-core).
2. **Sync con Google Calendar / Outlook no está en el OSS.** `CALENDAR_PROVIDER=external` habla un contrato REST genérico `/v1` contra un backend que tenés que proveer vos. Sin eso, la disponibilidad solo descuenta reservas propias de dCal y no se escriben eventos en tu calendario.
3. **MCP con OAuth** (para conectar Claude/Cursor sin API key pegada) es opcional: `OAUTH_ENABLED=true` + `OAUTH_ISSUER` + `OAUTH_SIGNING_JWK` + `MCP_PUBLIC_URL`. Depende de que el punto 1 esté resuelto (la persona se loguea vía `AUTH_PROVIDER`).

## Railway (prod)

Mismo repo, tres servicios:

| Servicio | Config |
|----------|--------|
| Postgres | Plugin de Railway. `btree_gist` la crea la migración (el usuario de Railway puede). |
| `dcal-api` | Root `/`, `RAILWAY_DOCKERFILE_PATH=apps/api/Dockerfile`. Variables: `DATABASE_URL=${{Postgres.DATABASE_URL}}`, `NODE_ENV=production`, `AUTH_PROVIDER=workos`, `JWT_SECRET`, `PUBLIC_APP_URL`, `API_PUBLIC_URL`, `MCP_PUBLIC_URL`, `INTERNAL_API_SECRET`, `INTEGRATION_ENCRYPTION_KEY`, `EMAIL_PROVIDER=smtp` (o `http`) + credenciales reales, `API_PORT=4000`. Pre-deploy: la migración (abajo). |
| `dcal-web` | Root `/`, `RAILWAY_DOCKERFILE_PATH=apps/web/Dockerfile`. Variables: `NEXT_PUBLIC_API_URL` (se usa en **build**), `API_URL=http://${{dcal-api.RAILWAY_PRIVATE_DOMAIN}}:4000`, `INTERNAL_API_SECRET` (mismo valor), `AUTH_PROVIDER=workos`, `WEB_SESSION_SECRET`, `PUBLIC_APP_URL`, `IAM_BASE_URL`, `KEEP_ALIVE_TIMEOUT=65000`. |

Migración como pre-deploy del API (la imagen es distroless, sin shell; el comando tiene que ejecutar `node` directo):

```
node node_modules/tsx/dist/cli.mjs --tsconfig tsconfig.runtime.json node_modules/@slate/db/src/cli/migrate.ts
```

A verificar al montar Railway: que el pre-deploy funcione sobre la imagen distroless (si no, un servicio one-shot aparte con ese comando) y que las variables de servicio lleguen como build args al web (necesario para `NEXT_PUBLIC_API_URL`). La API escucha en dual-stack, así que la red privada de Railway no necesita ajuste.

Paridad local ↔ Railway: lo único que cambia es auth (`local` → `workos`), email (Mailpit → proveedor real) y `NODE_ENV` del API. El resto de variables tiene el mismo nombre y significado.