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
| `vitasync-backend/` | Servidor / API | Spring Boot (Java) |
| `vitasync_wear/` | App del smartwatch | Flutter |

## Cómo correrlo

1. **Elasticsearch** (buscador real): `docker compose up -d elasticsearch` dentro de `vitasync-backend/`.
2. **Backend**: abrir `vitasync-backend/` y correr `VitasyncBackendApplication` (puerto 8081).
3. **Frontend**: `cd vitasync-frontend && ng serve` (puerto 4200).
4. **Reloj**: abrir `vitasync_wear/` en un emulador de Wear OS y correrlo desde Android Studio.

Ver `CHANGELOG.md` para el historial de versiones.

## Documentación completa

El reporte `REPORTE-PROYECTO.docx` (raíz del repositorio) explica, en lenguaje
sencillo, qué pide cada práctica y cómo se resolvió en este proyecto, con
capturas de cada función probada de verdad. `VitaSync-Presentacion.pptx` es
la guía usada para la presentación en vivo.
