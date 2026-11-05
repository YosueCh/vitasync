# vitasync-backend

Backend Spring Boot de VitaSync. Expone estos grupos de endpoints:

| Grupo | Base | Respaldo | Estado |
|---|---|---|---|
| Búsqueda del sitio | `/api/search` | Elasticsearch | Funciona sin configuración adicional (solo necesita el contenedor de Elasticsearch corriendo) |
| Enlace con smartwatch | `/api/smartwatch/*` | Cloud Firestore (Firebase) | Requiere `serviceAccountKey.json` propio (ver abajo); mientras no exista, responde `503`. Incluye el **historial de lecturas** (`/historial`) |
| Chat médico-paciente (Práctica 6) | `/api/chat/{pacienteId}/*` | Memoria del servidor | No necesita Firebase. La conversación se borra cuando el paciente cierra el chat (o al reiniciar el servidor) |
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

## 5. Historial de lecturas del smartwatch (Prácticas 1 y 2)

Cada vez que el reloj (o el firmware simulado de `vitasync-firmware-sim/`) sincroniza con
`POST /api/smartwatch/sync`, la lectura se guarda además en la subcolección
`devices/{usuarioId}/historial` de Firestore (campos `pasos`, `calorias`, `suenoHoras`,
`frecuenciaCardiaca`, `bateria`, `timestamp` y `ts` en milisegundos para ordenar).

| Endpoint | Qué hace |
|---|---|
| `GET /api/smartwatch/metrics?usuarioId=` | Última lectura: la de memoria o, si el servidor se reinició, la última guardada en la base de datos (solo se inventa una si nunca hubo ninguna) |
| `GET /api/smartwatch/historial?usuarioId=&limite=30` | Lecturas guardadas, la más reciente primero. `limite` se acota entre 1 y 200 |

Si falla el guardado del historial, la sincronización del reloj continúa (solo se registra una
advertencia). La vista móvil usa este historial al tocar una card del Resumen.

## 6. Chat médico-paciente (Práctica 6)

Es la "URL asignada" a la que se conectan los dos teléfonos (médico = Dispositivo A, paciente =
Dispositivo B); no se hablan entre sí. Hay una conversación por paciente (id de su cuenta).

| Endpoint | Qué hace |
|---|---|
| `POST /api/chat/{pacienteId}/mensajes` `{emisor, texto}` | Guarda un mensaje (`emisor`: `MEDICO` o `PACIENTE`). `400` si el texto está vacío, pasa de 200 caracteres o el emisor/id es inválido; `409` si el paciente cerró el chat |
| `GET /api/chat/{pacienteId}/mensajes?desde=N` | Mensajes con `id` mayor a `N` y si el chat está cerrado (`{cerrado, mensajes}`); la app lo consulta cada 2 s |
| `POST /api/chat/{pacienteId}/cerrar` | El paciente cierra el chat: **se borra todo el historial** |
| `POST /api/chat/{pacienteId}/abrir` | Abre un chat nuevo después de cerrar. Los `id` no se reinician, para que quien ya leyó no pierda mensajes |

Los mensajes viven solo en memoria (máx. 500 por conversación). Como el resto de la API, no
autentica al emisor: en producción se usaría un token.

## 7. Pruebas

```bash
mvn test
```

Cubren el chat (`ChatServiceTest`, `ChatControllerTest`), el historial de lecturas
(`SmartwatchHistorialTest`), el servicio del smartwatch, el firmware y el PIN.

## 8. Conectar el frontend Angular

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
├── chat/                          # /api/chat/* — memoria (Práctica 6)
│   ├── ChatService.java
│   ├── ChatController.java
│   ├── MensajeChatDTO.java
│   └── ConversacionDTO.java
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
│   ├── repository/                # DispositivoRepository, HistorialMetricasRepository
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

## Seguridad: control de acceso (Práctica 10)

El backend **arranca con la seguridad encendida** (`vitasync.seguridad.activa: true` en `application.yml`; sin la propiedad también cuenta como encendida) y exige identidad:

| Qué | Cómo |
|---|---|
| Personas | `Authorization: Bearer <ID token de Firebase Authentication>`. Sin token o con token malo: **401** |
| Dueño | Cada cuenta guarda `propietarioUid`. Pedir una cuenta ajena: **403** (igual si no existe, para no revelar qué cuentas hay) |
| Roles | claim `rol`: `paciente` (por omisión), `medico` (también entra al chat) y `admin` (todo) |
| Reloj / firmware | `X-Clave-Dispositivo` en `POST /smartwatch/sync`, `GET /firmware/orden` y `POST /firmware/aplicar`. La clave la entrega `POST /smartwatch/connect` una sola vez |
| Públicos | `GET /api/firmware/ultima`, búsqueda y Smart TV |

Con el emulador de Authentication, arranca el backend con la variable `FIREBASE_AUTH_EMULATOR_HOST=localhost:9099`.
La app móvil y el sitio Angular piden correo y contraseña por omisión (ver sus README). Para probar sin Firebase se apaga con `--vitasync.seguridad.activa=false` (o la variable `VITASYNC_SEGURIDAD_ACTIVA=false`) y la app con `--dart-define=SEGURIDAD=false`; deben coincidir. Con la seguridad encendida y sin `serviceAccountKey.json`, todo responde 401 porque no hay con qué verificar tokens.

El 401 y el 403 los emite el filtro antes de llegar a Spring MVC, así que CORS también corre como filtro previo (`CorsConfig`): sin eso el navegador los vería como un error de red y el sitio no sabría que la sesión venció.

**Prueba de punta a punta** (sin tocar el Firebase real: repositorios en memoria):

```bash
# 1) Authentication en el emulador (puerto 9099)
firebase emulators:start --only auth --project demo-vitasync
# 2) backend de pruebas con la seguridad activa
mvn test-compile spring-boot:run -Dspring-boot.run.useTestClasspath=true -Dspring-boot.run.directories=target/test-classes     -Dspring-boot.run.main-class=com.vitasync.backend.blackbox.ServidorPruebas "-Dspring-boot.run.arguments=--vitasync.seguridad.activa=true"
# 3) 20 casos con dos personas reales
node seguridad-e2e/prueba-seguridad.mjs
```

Limitación: el servidor de pruebas acepta los tokens sin firma del emulador (`VerificadorTokenEmulador`); en
producción `FirebaseVerificadorToken` sí comprueba la firma, pero esa ruta aún no se prueba contra el emulador.

**Reglas de Firestore** (`firestore.rules`): segunda barrera. Hoy todo el acceso pasa por el backend (Admin SDK, que se salta
las reglas); las reglas protegen si alguna vez un cliente accede directo: cada persona **lee** solo lo suyo y **nadie escribe**
desde el cliente. Se prueban con `node seguridad-e2e/prueba-reglas.mjs` (emuladores de Authentication en 9099 y de Firestore en 8085): 17 casos.

## Contactos de emergencia (Actividad 1)

| Ruta | Qué hace |
|---|---|
| `GET /api/contactos?usuarioId=` | Lista los contactos de la cuenta |
| `POST /api/contactos?usuarioId=` con `{nombre, telefono, relacion}` | Crea uno (400 si no cumple las reglas; 409 si el teléfono ya está o ya hay 5) |
| `DELETE /api/contactos/{id}?usuarioId=` | Elimina uno (404 si no existe) |

Se guardan en Firestore en `usuarios/{cuenta}/contactos`; con la seguridad activa cada persona solo toca los de sus cuentas, y se borran al eliminar la cuenta. Reglas del servidor: nombre de 2 a 60 caracteres; teléfono de 7 a 15 dígitos (los espacios, guiones y paréntesis se quitan); relación opcional (por omisión «Otro»); máximo 5 por cuenta.
