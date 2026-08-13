# vitasync-backend

Backend Spring Boot de VitaSync. Expone dos grupos de endpoints:

| Grupo | Base | Respaldo | Estado |
|---|---|---|---|
| Búsqueda del sitio | `/api/search` | Elasticsearch | Funciona sin configuración adicional (solo necesita el contenedor de Elasticsearch corriendo) |
| Enlace con smartwatch | `/api/smartwatch/*` | Cloud Firestore (Firebase) | Requiere `serviceAccountKey.json` propio (ver abajo); mientras no exista, responde `503` |
| Gestión de usuarios (Práctica 13) | `/api/usuarios/*` | Cloud Firestore (Firebase) | Mismo requisito que smartwatch; ver `docs/practica-13/Integracion-en-VitaSync.md` |
| Enlace con Smart TV (Práctica 9-10) | `/api/cast/*` | Cloud Firestore (Firebase) | Mismo requisito que smartwatch; ver `docs/practica-09-10/Actualizacion-smarttv-y-despliegue.md` |

Ver también [`docs-elasticsearch/GUIA_ELASTICSEARCH.md`](docs-elasticsearch/GUIA_ELASTICSEARCH.md) para el detalle paso a paso del buscador.

## 1. Requisitos

- JDK 21+
- Maven (o abrir la carpeta en IntelliJ IDEA, que trae Maven integrado y detecta el `pom.xml` automáticamente)
- Docker Desktop (para levantar Elasticsearch)

## 2. Levantar Elasticsearch

```bash
docker compose up -d
```

Verifica que responde:

```bash
curl http://localhost:9200
```

Kibana (opcional, para inspeccionar el índice) queda disponible en `http://localhost:5601`.

## 3. Ejecutar el backend

```bash
mvn spring-boot:run
```

Al arrancar, `SearchIndexSeeder` siembra automáticamente el índice `vitasync-content` con el mismo contenido que usa el frontend en modo local (`search-index.ts`), así que no hace falta cargar nada a mano.

Prueba el buscador:

```bash
curl "http://localhost:8081/api/search?q=sueño"
```

## 4. Habilitar `/api/smartwatch/*` (opcional)

1. Crea un proyecto en https://console.firebase.google.com y habilita Cloud Firestore.
2. Configuración del proyecto → Cuentas de servicio → "Generar nueva clave privada".
3. Guarda el archivo descargado como `src/main/resources/serviceAccountKey.json` (ya está en `.gitignore`, nunca se sube al repo).
4. Reinicia el backend. `GET /api/smartwatch/status` debe dejar de devolver `503`.

Sin este archivo, el backend arranca igual: solo los módulos de smartwatch, usuarios y cast quedan deshabilitados (responden `503 Service Unavailable` con un mensaje explicando qué falta), el buscador no se ve afectado.

Con Firebase configurado, `UsuarioSeeder` crea automáticamente tres cuentas (`alumno1`, `alumno2`, `invitado`) la primera vez que arranca el backend, listas para probarse desde `/usuarios` en el frontend.

## 5. Conectar el frontend Angular

En `vitasync-frontend/src/app/services/search.service.ts`, cambia:

```ts
private readonly MODO_LOCAL = false; // antes: true
```

Con el backend y Elasticsearch corriendo, `ng serve` empezará a consumir `/api/search` en vez del índice FlexSearch en memoria.

## Estructura

```
src/main/java/com/vitasync/backend/
├── VitasyncBackendApplication.java
├── config/
│   └── FirebaseConfig.java        # Firestore condicional a serviceAccountKey.json
├── search/                        # /api/search — Elasticsearch
│   ├── SearchDocument.java
│   ├── SearchDocumentRepository.java
│   ├── SearchIndexSeeder.java
│   ├── SearchResultDTO.java
│   ├── SearchService.java
│   └── SearchController.java
├── smartwatch/                    # /api/smartwatch/* — Firestore
│   ├── dto/
│   ├── model/
│   ├── repository/
│   ├── service/
│   └── controller/
├── usuarios/                      # /api/usuarios/* — Firestore (Práctica 13)
│   ├── dto/
│   ├── model/
│   ├── repository/
│   ├── service/
│   ├── controller/
│   └── UsuarioSeeder.java
└── cast/                          # /api/cast/* — Firestore (Práctica 9-10, enlace Smart TV)
    ├── dto/
    ├── model/
    ├── repository/
    ├── service/
    └── controller/
```
