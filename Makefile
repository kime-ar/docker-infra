.PHONY: help up down restart restart-one logs ps clean clean-all pull init-minio migrate-legacy migrate-caddy backup backup-cron networks

# ==========================================
# Variables Globales
# ==========================================
DOCKER = docker compose --env-file .env

# ==========================================
# Panel de Operaciones (Kime Infra)
# ==========================================

help:
	@echo "🛠️  Panel de Control - Kime Infraestructura"
	@echo "========================================"
	@echo "Comandos disponibles:"
	@echo "  make up              - Levanta toda la infraestructura en segundo plano"
	@echo "  make down            - Apaga y destruye todos los contenedores de la infra"
	@echo "  make restart         - Reinicia toda la infraestructura (recrea contenedores)"
	@echo "  make restart-one app=n8n - Reinicia un servicio sin recrear el resto"
	@echo "  make logs            - Muestra todos los logs (usa 'make logs app=n8n' para uno específico)"
	@echo "  make ps              - Muestra el estado de los contenedores"
	@echo "  make pull            - Descarga las últimas versiones de las imágenes"
	@echo "  make init-minio      - Crea buckets S3 y usuario dedicado de Langfuse"
	@echo "  make migrate-legacy  - Migra datos de directorios legacy a data/"
	@echo "  make migrate-caddy   - Migra data/caddy* a named volumes"
	@echo "  make backup          - Backup completo (Postgres, Redis, MinIO, Forgejo, n8n)"
	@echo "  make backup-cron     - Instala cron diario de backup (03:30)"
	@echo "  make clean           - Apaga contenedores y elimina recursos huérfanos del proyecto"
	@echo "  make clean-all       - ⚠️  Limpieza destructiva de TODO el sistema Docker"

networks:
	@docker network inspect edge >/dev/null 2>&1 || docker network create edge
	@docker network inspect data >/dev/null 2>&1 || docker network create --internal data
	@docker network inspect dev-network >/dev/null 2>&1 || docker network create dev-network
	@docker volume inspect docker-infra_caddy_data >/dev/null 2>&1 || docker volume create docker-infra_caddy_data
	@docker volume inspect docker-infra_caddy_config >/dev/null 2>&1 || docker volume create docker-infra_caddy_config

up: networks
	@echo "🚀 Levantando toda la infraestructura..."
	$(DOCKER) up -d --remove-orphans

down:
	@echo "🛑 Apagando el laboratorio..."
	$(DOCKER) down

restart: networks
	@echo "🔄 Reiniciando servicios..."
	$(DOCKER) down
	@echo "⏳ Esperando que se liberen los puertos..."
	@sleep 5
	@echo "🚀 Levantando toda la infraestructura..."
	$(DOCKER) up -d --remove-orphans

restart-one:
	@test -n "$(app)" || (echo "Uso: make restart-one app=<servicio>"; exit 1)
	@echo "🔄 Reiniciando $(app)..."
	$(DOCKER) restart $(app)

logs:
	@echo "📋 Mostrando logs (Ctrl+C para salir)..."
	$(DOCKER) logs -f $(app)

ps:
	@echo "📊 Estado de los contenedores:"
	$(DOCKER) ps

pull:
	@echo "⬇️ Descargando actualizaciones de imágenes..."
	$(DOCKER) pull

init-minio:
	@bash scripts/init-minio-buckets.sh

migrate-legacy:
	@bash scripts/migrate-legacy-data.sh

migrate-caddy:
	@bash scripts/migrate-caddy-volumes.sh

backup:
	@bash scripts/backup.sh

backup-cron:
	@bash scripts/install-backup-cron.sh

clean:
	@echo "🧹 Limpiando recursos huérfanos del proyecto..."
	$(DOCKER) down --remove-orphans
	docker image prune -f

clean-all:
	@echo "⚠️  Esto eliminará imágenes, contenedores y volúmenes de TODO el sistema Docker."
	@read -p "Escribí 'yes' para continuar: " confirm && [ "$$confirm" = "yes" ] || (echo "Cancelado." && exit 1)
	sudo docker system prune -a --volumes
