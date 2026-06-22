.PHONY: help up down restart logs ps clean pull

# ==========================================
# Variables Globales
# ==========================================
# Usamos el binario de Snap y forzamos la inyección del archivo .env maestro
DOCKER = docker compose --env-file .env

# ==========================================
# Panel de Operaciones (Kime Infra)
# ==========================================

help:
	@echo "🛠️  Panel de Control - Kime Infraestructura"
	@echo "========================================"
	@echo "Comandos disponibles:"
	@echo "  make up       - Levanta toda la infraestructura en segundo plano"
	@echo "  make down     - Apaga y destruye todos los contenedores de la infra"
	@echo "  make restart  - Reinicia toda la infraestructura"
	@echo "  make logs     - Muestra todos los logs (usa 'make logs app=n8n' para uno específico)"
	@echo "  make ps       - Muestra el estado de los contenedores"
	@echo "  make pull     - Descarga las últimas versiones de las imágenes"
	@echo "  make clean    - 🧹 Elimina contenedores huérfanos, redes sin uso y caché"

up:
	@echo "🚀 Levantando toda la infraestructura..."
	$(DOCKER) up -d --remove-orphans

down:
	@echo "🛑 Apagando el laboratorio..."
	$(DOCKER) down

restart:
	@echo "🔄 Reiniciando servicios..."
	$(DOCKER) down
	@echo "⏳ Esperando que se liberen los puertos..."
	@sleep 5
	@echo "🚀 Levantando toda la infraestructura..."
	$(DOCKER) up -d --remove-orphans

logs:
	@echo "📋 Mostrando logs (Ctrl+C para salir)..."
	$(DOCKER) logs -f $(app)

ps:
	@echo "📊 Estado de los contenedores:"
	$(DOCKER) ps

pull:
	@echo "⬇️ Descargando actualizaciones de imágenes..."
	$(DOCKER) pull

clean:
	@echo "🧹 Limpiando el sistema Docker (Imágenes sin uso, redes colgadas)..."
	sudo docker system prune -a --volumes
