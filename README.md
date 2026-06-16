# 🚀 Kime Infra: Laboratorio Docker de Grado Empresarial

![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=for-the-badge&logo=docker&logoColor=white)
![Postgres](https://img.shields.io/badge/postgres-%23316192.svg?style=for-the-badge&logo=postgresql&logoColor=white)
![Caddy](https://img.shields.io/badge/Caddy-lightgrey?style=for-the-badge&logo=caddy&logoColor=111111)
![n8n](https://img.shields.io/badge/n8n-FF6D5A?style=for-the-badge&logo=n8n&logoColor=white)

Bienvenido a **Kime Infra**, una infraestructura auto-alojada (Home Lab) estructurada bajo estrictos estándares DevOps. Este proyecto demuestra cómo pasar de un conjunto de contenedores "sueltos" a una plataforma centralizada, segura y optimizada para el desarrollo de software y experimentación con IA.

## 🏗️ Arquitectura y Stack Tecnológico

Este laboratorio utiliza una arquitectura modular orquestada desde un único archivo maestro de Compose, compartiendo una red interna Zero-Trust (`dev-network`) [3, 4].

*   **Enrutamiento y Seguridad:** Caddy (Proxy Inverso con resolución de dominios locales `.lan` y manejo estricto de CORS) [1, 5].
*   **Capa de Datos:** PostgreSQL 16 con extensión `pgvector` [4] (aislado por esquemas para cada app [2, 3]), Redis 7 Alpine [4] y MinIO para almacenamiento de objetos S3 local [6].
*   **Desarrollo y Workflows:** Forgejo (Servidor Git) [7], n8n en modo colas (fijado en versión v1) [3, 8] y Mailpit para intercepción de correos SMTP [6].
*   **Observabilidad:** Homepage (Dashboard central conectado de forma segura al socket de Docker) [2], Uptime Kuma (Monitoreo) [8] y Langfuse (Observabilidad para LLMs) [9].

## 🛡️ Características DevOps (El Valor de esta Infra)

A diferencia de las configuraciones de Docker típicas de tutoriales, este entorno aplica prácticas de producción:

1.  **Redes Zero-Trust:** Ningún puerto de base de datos o aplicación está expuesto directamente al Host [1, 5]. Todo el tráfico es gestionado y securizado obligatoriamente a través de Caddy.
2.  **Centralización de Secretos:** Ausencia total de credenciales en los archivos `docker-compose.yml` [3, 4] y `app.ini` de Forgejo [10, 11]. Todo se inyecta desde un único archivo `.env` maestro.
3.  **Límites de Recursos (Cgroups):** Los contenedores pesados (Postgres, n8n, Redis) tienen límites estrictos de RAM y CPU (`deploy.resources`) para evitar caídas del servidor por fugas de memoria.
4.  **Mantenibilidad Extrema:** Uso de la directiva `include` de Docker Compose y un `Makefile` dedicado para orquestar la infraestructura sin lidiar con comandos extensos.

---

## ⚙️ Guía de Inicio Rápido

### 1. Prerrequisitos
*   Un servidor Ubuntu/Debian con **Docker y Docker Compose** instalados (compatible con instalaciones nativas o vía Snap).
*   Utilidad `make` instalada (`sudo apt install make`).

### 2. Instalación y Configuración

1. **Clona este repositorio** en tu servidor (preferentemente dentro de un directorio `projects/docker-infra`).
2. **Prepara tus secretos:** Crea tu archivo de entorno a partir de la plantilla.
   ```bash
   cp .env.example .env
```
Edita el .env con contraseñas seguras y tus propios tokens generados (ej. usando openssl rand -base64 32).
Inicia la infraestructura: Utiliza el panel de control integrado en el Makefile.
3. Operaciones de Día 2 (Panel de Control)
Hemos abstraído la complejidad de Docker detrás de un Makefile. Ejecuta make help en la raíz para ver todos los comandos:
make up - Levanta toda la infraestructura de forma ordenada respetando los healthchecks de la base de datos.
make down - Apaga el laboratorio de manera segura.
make ps - Muestra el estado de salud de todos los contenedores.
make logs app=<nombre> - Revisa los logs en vivo de un servicio (ej. make logs app=n8n).
make clean - Elimina contenedores huérfanos e imágenes sin uso para liberar espacio en disco.
📂 Estructura de Directorios Recomendada
Para mantener la Separación de Responsabilidades, te sugiero mantener tu código fuente fuera de este directorio, estructurándolo así en tu servidor:
projects/
├── docker-infra/       # (Este repositorio: Tu plataforma y bases de datos)
└── repositories/       # (Tus aplicaciones: APIs, Bots, Frontends)
Tus aplicaciones en repositories/ pueden conectarse mágicamente a las bases de datos de esta infraestructura uniéndose a la red externa dev-network en sus propios archivos Compose.
📖 Serie del Blog: "Construyendo un Home Lab de Grado Empresarial"
Si quieres entender el "por qué" detrás de cada decisión arquitectónica de este repositorio, he documentado el proceso de construcción paso a paso:
[ ] Parte 1: La Fundación (Orquestación, Zero-Trust y Proxy Inverso con Caddy). (Próximamente)
[ ] Parte 2: La Capa de Datos (PostgreSQL centralizado con pgvector, Redis y MinIO). (Próximamente)
[ ] Parte 3: El Motor del Lab (Git local con Forgejo, Workflows con n8n y Mailpit). (Próximamente)
[ ] Parte 4: Operaciones de Día 2 (Observabilidad, Dashboard y Prevención de Disco Lleno). (Próximamente)
Hecho con ☕ y buenas prácticas DevOps.
