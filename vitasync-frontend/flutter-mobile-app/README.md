# flutter-mobile-app

Vista móvil de VitaSync: una página web hecha en Flutter Web, pensada para
pantallas de teléfono y publicable como PWA. Se abre desde el navegador del
teléfono, sin APK ni tienda de aplicaciones. Es la extensión de la materia
Desarrollo Móvil Integral (ver `Propuesta-VitaSync-Mobile-Web.docx` y
`Parcial-1-Documentacion.docx` en la raíz del repositorio).

Sigue el mismo esquema que `flutter-stats-widget/`: proyecto Flutter aparte
(pubspec propio, se compila por separado) que vive dentro de
`vitasync-frontend/` porque forma parte del sitio web.

## Estado

La vista ya habla con el backend real: diseño del Parcial 1, PIN real del
Parcial 2 (verificado en el backend) y las prácticas de la materia integradas:

| Práctica | Qué se integró aquí |
|---|---|
| **P3** ConsultaWeb | `ApiCliente` y los repositorios `Http*`: petición HTTP con tiempo límite, estados cargando/éxito/error y mensajes claros (`ApiException`). La URL base vive en `config/api_config.dart`, separada de la lógica, como `ApiConfig.kt`. |
| **P4** Room | Caché local de métricas: entidad `MetricaLocal`, `MetricaDao`, esquema versionado con migración 1→2 y `CacheSaludRepository`. Sin conexión se muestra la última lectura guardada. |
| **P1** Firmware | Pantalla Dispositivo con versión de firmware y botón "Actualizar firmware" (flujo OTA). Lo atiende el firmware simulado de `../../vitasync-firmware-sim/`. |
| **P1 y P2** Firmware / sensor | Las lecturas del dispositivo se guardan como historial en la base de datos y se ven al tocar una card del Resumen (`HistorialScreen`). Ver "Historial de las cards". |
| **P6** Interacción entre dispositivos | Pestaña Chat médico-paciente entre dos teléfonos, con el backend como servidor intermediario (`ChatScreen`, `ChatRepository`). Ver "Chat médico-paciente". |

El PIN de la cuenta se crea y verifica en el backend (con salt y hash); con
`--dart-define=MUESTRA=true` la app corre con datos de ejemplo y acepta
cualquier PIN de 4 dígitos.

Capturas de la app contra el backend real en `evidencias-integracion/`.

## Estructura (`lib/`)

| Carpeta | Contenido |
|---|---|
| `config/` | `ApiConfig`: host y puerto del backend, intervalo de sondeo (3 s) y del chat (2 s) |
| `models/` | `Metricas`, `Dispositivo`, `Usuario` (formato de los DTO del backend), `EstadoDispositivo`, `EstadoFirmware`, `LecturaMetricas`, `TipoMetrica` (las 4 cards: título, ícono, valor y formato), `MensajeChat` / `RolChat` / `ConversacionChat` y `EstadoVista` (clase sellada: cargando / éxito / fallo) |
| `services/` | Contratos y sus implementaciones: `Http*` (backend real), `Muestra*` (ejemplo), `CacheSaludRepository` (métricas e historial con respaldo local), `ChatRepository`, `ApiCliente` |
| `data/` | Caché local (P4): `MetricaLocal`, `MetricaDao`, `MetricaDaoPrefs` |
| `screens/` | Selección de cuenta, PIN, estructura con navegación (Resumen, Dispositivo, Chat), resumen, `HistorialScreen`, dispositivo y `ChatScreen` |
| `widgets/` | Teclado de PIN, tarjeta de métrica y `VistaEstado` |
| `theme/` | Tema (mismo teal que la app del reloj) |

## Probarlo

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d chrome --web-port 5001
# o sin backend, con datos de ejemplo:
flutter run -d chrome --dart-define=MUESTRA=true
```

Con backend: levantar Elasticsearch y el backend como indica el README de la
raíz, y el firmware simulado (`vitasync-firmware-sim/`) para que lleguen datos.

## Historial de las cards (Prácticas 1 y 2)

Las cards del Resumen (Pasos, Calorías, Sueño, Ritmo cardíaco) muestran la
última lectura guardada en la base de datos; **al tocar una card se abre su
historial**: todas las lecturas con fecha y hora, mínimo / promedio / máximo y
una gráfica. Las lecturas las produce el dispositivo (el reloj o el firmware
simulado de `vitasync-firmware-sim/`, que es la parte de firmware de las
prácticas 1 y 2): cada sincronización se guarda en Firestore
(`devices/{usuarioId}/historial`) y la app las pide con
`GET /api/smartwatch/historial`. Sin conexión se muestra el historial que quedó
en la caché local del teléfono. Para ver un historial real hay que dejar correr
el firmware simulado un rato (`dart run bin/vitasync_firmware.dart --usuario <id> --auto 3`).

## Chat médico-paciente (Práctica 6)

Pestaña **Chat**: dos teléfonos con la misma app, uno como **Médico
(Dispositivo A)** y otro como **Paciente (Dispositivo B)**. No se conectan
entre sí; ambos hablan con el backend (`/api/chat/{pacienteId}/...`), que
guarda la conversación en memoria **hasta que el paciente cierra el chat**
(entonces borra todo el historial).

Para probarlo con dos teléfonos:

1. Backend corriendo en la PC; teléfonos y PC en la misma red (o zona Wi-Fi de
   un celular).
2. En cada teléfono: `flutter run --dart-define=API_HOST=<IP de la PC>`.
3. Teléfono 1: entrar con la cuenta del paciente → Chat → «Paciente».
   Teléfono 2: entrar con otra cuenta → Chat → «Médico» → elegir al paciente.
4. Escribir en ambos. El paciente puede **cerrar el chat y borrar el historial**
   (y abrir uno nuevo); el médico puede limpiar su pantalla.

Los mensajes nuevos llegan por sondeo cada 2 s (`ApiConfig.intervaloChat`).
Validaciones: no se envían mensajes vacíos ni de más de 200 caracteres (también
las aplica el backend). Limitación: como el resto de la API, el chat no
autentica al emisor; en producción se usaría un token.

## Demo en el emulador Android

La vista es una PWA: se abre en Chrome dentro del emulador (sin APK). Desde el
emulador la PC se ve como `10.0.2.2`, y la app toma de ahí el host del backend.

1. Elasticsearch y backend arriba (README de la raíz).
2. Compilar con los recursos incluidos, porque el emulador no tiene internet y
   Flutter Web descarga CanvasKit de un CDN si no:
   `flutter build web --release --no-web-resources-cdn`
3. Servir `build/web` en el puerto 5002 con un servidor robusto, por ejemplo
   `npx http-server build/web -p 5002 -c-1`. (`python -m http.server` corta los
   archivos grandes por el NAT del emulador: `ERR_CONTENT_LENGTH_MISMATCH`.)
4. Abrir el emulador (`flutter emulators --launch Pixel_8_Pro`) y en Chrome ir a
   `http://10.0.2.2:5002`. Si adb lo ve `offline`, reiniciarlo con
   `emulator -avd Pixel_8_Pro -no-snapshot-load`.
5. Correr el firmware simulado con el id de la cuenta que se va a elegir
   (`vitasync-firmware-sim/`) para que lleguen datos.

Capturas de esta demo en `evidencias-integracion/emulador/`. La prueba sin
conexión se hace con el modo avión del emulador.

## Compilarlo para servirlo en `/movil/`

```bash
flutter build web --release --base-href /movil/
```

El `--base-href /movil/` es obligatorio por la misma razón que en
`flutter-stats-widget/`: se sirve desde una subcarpeta. En Git Bash de Windows
hay que anteponer `MSYS_NO_PATHCONV=1` (o usar PowerShell); si no, Git Bash
convierte `/movil/` en una ruta de disco y el build falla.

Copiar `build/web/` a `vitasync-frontend/public/movil/` (Parcial 3):

```powershell
# PowerShell, desde vitasync-frontend/flutter-mobile-app/
Copy-Item -Recurse -Force build\web\* ..\public\movil\
```

## Notas para el Parcial 2 y 3

- El host del backend se toma de `Uri.base.host`, porque en el teléfono
  `localhost` es el propio teléfono.
- CORS ya acepta `localhost` en cualquier puerto y las redes privadas
  (`CorsConfig.java`), así que funciona desde la IP de la PC en la red local.
- La caché local de métricas usa **SQLite real** en Android e iOS (`MetricaDaoSqlite`) y `shared_preferences`
  (localStorage) en web (`MetricaDaoPrefs`), detrás del mismo contrato `MetricaDao`; `abrirDaoLocal()` elige
  según la plataforma. Es solo una caché: la única fuente de verdad es Firestore, en el servidor.

## Con la seguridad activa (Práctica 10)

Por omisión la app **pide correo y contraseña** (el backend arranca con la seguridad encendida). Para un backend sin
seguridad (pruebas locales) se apaga con `--dart-define=SEGURIDAD=false`; con la seguridad encendida basta ejecutar:

```bash
flutter run -d chrome --web-port 5001   # con seguridad (por omisión)
flutter run -d chrome --web-port 5001 --dart-define=SEGURIDAD=false   # backend sin seguridad
# emulador de Android: lo mismo, con el emulador de Authentication en la PC (puerto 9099)
```

Flujo: **correo y contraseña** (Firebase Authentication) → la pantalla muestra el **correo y el UID** → cada persona
ve solo **sus** cuentas (puede crear la suya) → PIN → contenido. En la pestaña Dispositivo, **Vincular reloj** entrega
la clave del dispositivo una sola vez (se usa con `--clave` en el firmware simulado).
Con la nube real: `--dart-define=AUTH_BASE=https://identitytoolkit.googleapis.com --dart-define=FIREBASE_API_KEY=<clave web>`.
Sin plugin nativo: el inicio de sesión usa la API REST de Firebase Authentication.

## Prueba de integración en un emulador de Android

Corre la app **real** (con SQLite real) contra el backend con la seguridad activada y el emulador de Authentication:
inicio de sesión con correo, UID, cuenta propia, PIN, reloj vinculado con clave, lectura del reloj, contactos de
emergencia, aislamiento entre dos personas y caché local. Deja capturas en `evidencias-integracion/seguridad/`.

```bash
# 1) Authentication:  firebase emulators:start --only auth --project demo-vitasync
# 2) backend de pruebas con seguridad (ver vitasync-backend/README.md, sección «Seguridad»)
# 3) con un emulador de Android encendido:
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/seguridad_test.dart -d emulator-5554 --dart-define=SEGURIDAD=true
```

No corre en el CI (necesita un emulador y es lenta): se ejecuta a mano antes de entregar. Ver `../../PIRAMIDE-DE-PRUEBAS.md`.
