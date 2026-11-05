# VitaSync

Aplicación de salud que conecta un sitio web, un servidor y un smartwatch: el
usuario ve su información y administra su cuenta desde la web, sincroniza sus
datos de salud desde el reloj, y ambos comparten siempre la misma fuente de
verdad a través del backend.

Proyecto académico — Desarrollo para Dispositivos Inteligentes — que integra
las 13 prácticas de la materia en un solo producto funcional.

## Estructura del repositorio

| Carpeta | Qué es | Con qué se hizo |
|---|---|---|
| `vitasync-frontend/` | Sitio web | Angular |
| `vitasync-frontend/flutter-stats-widget/` | Micro-frontend de estadísticas, incrustado en el Dashboard | Flutter Web |
| `vitasync-frontend/flutter-mobile-app/` | Vista móvil (PWA), se abre desde el navegador del teléfono sin APK | Flutter Web |
| `vitasync-backend/` | Servidor / API | Spring Boot (Java) |
| `vitasync_wear/` | App del smartwatch | Flutter |
| `vitasync-firmware-sim/` | Firmware simulado del reloj (setup/loop, LED, botón, actualización OTA) | Dart |

## Cómo correrlo

1. **Elasticsearch** (buscador real): `docker compose up -d elasticsearch` dentro de `vitasync-backend/`.
2. **Backend**: abrir `vitasync-backend/` y correr `VitasyncBackendApplication` (puerto 8081).
3. **Frontend**: `cd vitasync-frontend && ng serve` (puerto 4200).
4. **Reloj**: abrir `vitasync_wear/` en un emulador de Wear OS y correrlo desde Android Studio.
5. **Vista móvil**: `cd vitasync-frontend/flutter-mobile-app && flutter run -d chrome --web-port 5001`.
   La primera vez, cada cuenta crea su PIN de 4 dígitos (se guarda con salt y hash en el backend).
   En el emulador de Android la app llega al backend por `10.0.2.2:8081`; con `--dart-define=MUESTRA=true` corre con datos de ejemplo.
6. **Firmware simulado** (genera datos y atiende las actualizaciones de firmware):
   `cd vitasync-firmware-sim && dart run bin/vitasync_firmware.dart --usuario <id> --auto 3`.

Ver `CHANGELOG.md` para el historial de versiones.

## Funciones de la vista móvil

- **Resumen con historial (Prácticas 1 y 2):** las cards de pasos, calorías, sueño y ritmo cardíaco
  muestran la última lectura guardada en la base de datos; al tocar una card se abre su historial
  (lecturas con fecha y hora, mínimo / promedio / máximo y gráfica). Las lecturas las produce el
  reloj o el firmware simulado y se guardan en Firestore (`GET /api/smartwatch/historial`).
- **Chat médico-paciente (Práctica 6):** pestaña "Chat". Un teléfono entra como **Médico
  (Dispositivo A)** y elige al paciente; el otro como **Paciente (Dispositivo B)**. Ambos usan el
  backend (`/api/chat/...`) como servidor intermediario, que guarda la conversación hasta que el
  paciente cierra el chat (entonces se borra). Para probarlo con dos teléfonos:
  `flutter run --dart-define=API_HOST=<IP de la PC>` en cada uno (ver el README de
  `vitasync-frontend/flutter-mobile-app/`).

Pruebas automáticas: `mvn test` en `vitasync-backend/` (41) y `flutter test` en
`vitasync-frontend/flutter-mobile-app/` (84).

## Documentación completa

El reporte `REPORTE-PROYECTO.docx` (raíz del repositorio) explica, en lenguaje
sencillo, qué pide cada práctica y cómo se resolvió en este proyecto, con
capturas de cada función probada de verdad. `VitaSync-Presentacion.pptx` es
la guía usada para la presentación en vivo.
