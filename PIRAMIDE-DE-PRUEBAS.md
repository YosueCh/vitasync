# Pirámide de pruebas de VitaSync (Actividad 2 aplicada al proyecto)

Revisado el 4 de noviembre de 2026. Los conteos salen de `node scripts/diagnostico-piramide.mjs` y coinciden con las ejecuciones reales (backend 154, app 189, firmware 15).

## Fase 1 · Diagnóstico

**Función crítica:** iniciar sesión y ver *mis* datos de salud sin que nadie más pueda verlos (autenticación, dueño por cuenta, lecturas del reloj y su caché).

| Nivel | Qué es aquí | Pruebas | % |
|---|---|---|---|
| Unitarias | Una clase sola con sus dependencias simuladas o en memoria (servicios del backend, DAO, servicios de la app, firmware) | 99 | 24.0 % |
| Integración | Varias piezas reales juntas (controlador + filtro de seguridad + servicio; pantalla + repositorio) | 262 | 63.4 % |
| De punta a punta | El sistema entero: servidor con personas reales del emulador de Authentication, y la app real en un emulador de Android | 52 | 12.6 % |
| **Total** | | **413** | |

Por capa: backend 154 en JUnit + 51 casos de punta a punta · app móvil 189 + 1 de integración en emulador · firmware 15 · web (Angular) 3.

**Dos matices que cambian la lectura:**
1. De los 52 «de punta a punta», **51 son casos por API** (un servidor real, pero sin interfaz). **Con la app real hay 1 sola prueba** (de muchos pasos, en un solo emulador).
2. La pirámide no tiene forma de pirámide: es más ancha en el medio (53 % integración) que en la base (31 % unitarias). La mayoría de las pruebas de la app son de pantalla, no de clase.

**Cobertura de líneas:** app móvil **90.2 %** (1467 de 1627; lo menos cubierto: `contactos_repository` 62 %, `dispositivo_screen` 69 %, `salud_repository` 70 %). Backend, firmware y web: **no medida** (no está configurada).

**¿Se ejecutan solas?** Sí: `.github/workflows/pruebas.yml` (4 trabajos: backend, firmware, app y seguridad de punta a punta) **ya corre en GitHub Actions en cada push; las 5 corridas de la ronda del 4 de noviembre salieron en verde.** Las 3 pruebas de Angular se ejecutaron a mano y pasan, pero el CI todavía no las incluye.

**Lo que no se ejecutó en esta ronda:** las 3 pruebas de Angular (`app.spec.ts`) y la prueba por omisión de la app de Wear OS (una sola, la que trae Flutter).

## Fase 5 · Capa más débil y mejoras

**Capa más débil: la de punta a punta con la app real.** Una sola prueba, un solo emulador, un solo recorrido. Es la única que protege la unión de todo (pantalla → red → servidor → caché), y sin ella un cambio que rompa esa unión pasa las otras 300 pruebas. Todo lo que hoy la interfaz promete en tiempo real (mensajes pendientes sin conexión, bloqueo del PIN, límite de contactos) se prueba solo con dobles.

**Dos mejoras priorizadas por riesgo:**

| # | Mejora | Riesgo que reduce | Esfuerzo |
|---|---|---|---|
| 1 | ~~Ejecutar el CI de verdad~~ (hecho). Falta sumarle las pruebas de Angular | Sin ejecución automática, cualquier regresión llega a la entrega sin que nadie corra las pruebas | Bajo |
| 2 | **Ampliar las pruebas con la app real en emulador**: mensajes pendientes con el modo avión real, bloqueo del PIN a los 5 fallos, límite de 5 contactos; y medir la cobertura del backend (JaCoCo) | Errores de la unión pantalla-red-servidor que solo se ven con la app entera | Medio |

## Qué ejecutar y cuándo

| Momento | Qué se ejecuta |
|---|---|
| Cada cambio (local) | Las pruebas de la capa tocada: `mvn test`, `flutter test` o `dart test` |
| Cada push / pull request (CI) | Backend + app (con `flutter analyze`) + firmware + seguridad de punta a punta |
| Antes de entregar | Todo lo anterior + la prueba con la app real en un emulador (`flutter drive …`, ver el README de la app) |

## Cómo reproducir

```bash
node scripts/diagnostico-piramide.mjs                         # esta tabla
cd vitasync-backend && mvn test                               # 154
cd vitasync-frontend/flutter-mobile-app && flutter test --coverage   # 189 + cobertura
cd vitasync-firmware-sim && dart test                         # 15
```

## Límites de este diagnóstico
- La clasificación por nivel es un criterio mío (arriba); otra persona podría mover algunas pruebas de capa.
- El conteo de pruebas de Dart y Java es por lectura del código; coincide con los totales ejecutados, pero un test generado en un ciclo contaría una sola vez.
- No se midió la calidad de las pruebas (por ejemplo con mutaciones, como en la Actividad 2 original), solo su cantidad y cobertura de líneas de la app.
