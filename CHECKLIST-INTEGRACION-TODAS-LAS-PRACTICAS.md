# VitaSync: cómo vamos a integrar todas las prácticas (1–10 y Actividades 1–3)

Revisado el 3 de noviembre de 2026 contra el código real. Reemplaza a `CHECKLIST-INTEGRACION-PRACTICAS.md` (que solo cubría hasta la Práctica 8).

Leyenda: ✅ ya está · 🟡 está a medias · ❌ falta

---

## 0. Carpetas: ya quedó una sola

Había dos copias del mismo repositorio (`github.com/YosueCh/vitasync`, mismo último commit):

| Carpeta | Qué tenía |
|---|---|
| `PRACTICA 8/` | **Todo el trabajo**: chat, historial, caché, PIN, firmware simulado, pruebas, documentos (Parcial 2). 34 cambios sin commit |
| `Proyecto individual/` | Una copia más vieja del repositorio. Sus 3 cambios propios ya estaban en la otra, así que no había nada único que perder |

**Hecho hoy:** copié el trabajo de `PRACTICA 8/` a **`Proyecto individual/`** (124 archivos nuevos o más recientes; no sobrescribí nada más nuevo y no borré nada de ninguna carpeta).

➡️ **A partir de ahora se trabaja solo en `Proyecto individual/`.**
`PRACTICA 8/` queda intacta como respaldo y para la entrega de la Práctica 8 (`Practica8_PruebasCajaNegra.docx/.pdf` y `evidencias-caja-negra/`, que no copié a propósito).

Falta al abrir el proyecto por primera vez: `flutter pub get` en `vitasync-frontend/flutter-mobile-app/` (el `pubspec.lock` de esa carpeta es el viejo).

- [x] Fusionar las dos carpetas
- [ ] Probar que compila y corre desde `Proyecto individual/` (backend y app)
- [ ] Cuando confirmes que todo funciona: archivar o borrar las carpetas `vitasync-*` que quedaron dentro de `PRACTICA 8/` (**solo con tu visto bueno**)

---

## Estado final de esta ronda (4 de noviembre de 2026)

Pruebas al cierre, todas verdes: **backend 137 · app 184 (análisis sin avisos) · firmware 15**, más la prueba de integración de la app real en el emulador de Android, 29 casos de seguridad de punta a punta y 22 de reglas de Firestore.

**Integrado y probado:** Prácticas 1, 3, 4 (SQLite real), 5, 6, 8 y 10 y la Actividad 1 (contactos de emergencia); Práctica 9 (indicador de estado, mensajes pendientes y metas compartidas paciente–médico con control de versión) y Práctica 7 en parte (roles en lote y archivos en el chat); Actividad 3 en parte.

**Defectos de la Práctica 8:** corregidos los seis. D-06 (detalles de interfaz) con una salvedad: tres de sus cuatro detalles se corrigieron y se probaron por comportamiento y posición; el cuarto (espera de ~12 s sin servidor) no se pudo reproducir porque el código ya limita la espera a 4 s, y ese límite quedó protegido con una prueba. **El orden de las cuentas y la posición del botón conviene mirarlos a simple vista en un emulador.**

**Lo que queda, en orden de prioridad:**
1. Probar los repositorios contra Firestore (borrado real de subcolecciones y persistencia del servidor): no se pudo con el cliente de Java y el emulador; probar el backend real con `FIRESTORE_EMULATOR_HOST` o con el proyecto de Firebase de la nube. Ahí mismo, probar la firma real de los tokens.
2. Actividad 2: ejecutar el CI de verdad en GitHub (hoy solo está escrito), sumar las pruebas de Angular y ampliar las pruebas con la app real (ver `PIRAMIDE-DE-PRUEBAS.md`).
3. ~~Actividad 1 (contactos de emergencia) dentro de VitaSync~~ — hecha el 4 de noviembre.
4. ~~Práctica 9: conflictos de versión~~ — hecha el 4 de noviembre (metas compartidas entre paciente y médico). La Práctica 7 quedó en parte (ver abajo).
5. Práctica 2: Bluetooth (o justificar HTTP).
6. Encender la seguridad por omisión cuando se decida (hoy está apagada en el servidor y en la app).

**Límites que conviene tener presentes:** todo lo de Firebase se probó con emuladores, no con un proyecto en la nube; el servidor de pruebas acepta tokens sin firma del emulador; no se hizo ningún commit.

---

## Avance (se actualiza en cada sesión)

**4 de noviembre de 2026 — Etapa 1 completa** (salvo probar la firma real de los tokens, que necesita tu proyecto de Firebase). Las tres piezas existen y están probadas:

| Pieza | Qué hace | Pruebas |
|---|---|---|
| Backend | Token obligatorio, cada cuenta de su dueño, clave de dispositivo, validaciones D-01/D-02 | 83 (todas pasan) |
| Firmware simulado | Se identifica con `--clave` (cabecera `X-Clave-Dispositivo`) | 15 (todas pasan) |
| App Flutter | Inicio de sesión con correo, UID en pantalla, crear cuenta VitaSync, vincular reloj (muestra su clave una vez) | 103 (todas pasan) |

**Prueba de punta a punta:** `vitasync-backend/seguridad-e2e/prueba-seguridad.mjs` — dos personas reales del emulador de Authentication contra el backend con la seguridad activa: **20 de 20 casos pasan** (401 sin token, 403 al tocar lo ajeno en 11 rutas, clave de dispositivo, chat, cuentas propias).

El control de acceso sigue **apagado por omisión** (`vitasync.seguridad.activa: false` en el servidor y `SEGURIDAD` sin definir en la app); se enciende en los dos lados a la vez (ver README del backend).

**Verificado en el emulador de Android (4 de noviembre):** `flutter drive` con `integration_test/seguridad_test.dart` — la app real, en el emulador, contra el backend con seguridad y el emulador de Authentication: acceso rechazado con mensaje genérico, registro con correo, UID en pantalla, cuenta propia, PIN, reloj vinculado con clave de 48 caracteres, lectura del reloj con esa clave (y 401 sin ella), y una segunda persona (Beto) que no ve ni toca nada de Ana (403). 6 capturas en `flutter-mobile-app/evidencias-integracion/seguridad/`.

**Reglas de Firestore:** `vitasync-backend/firestore.rules` + `seguridad-e2e/prueba-reglas.mjs` — **17 de 17**: cada persona lee solo lo suyo y desde el cliente no se escribe nada (todo lo escribe el backend).

**Lo que todavía NO está verificado:** el verificador de producción (`FirebaseVerificadorToken`) comprobando una firma real: el emulador de Authentication firma con «alg: none», así que eso solo se puede probar con tu proyecto de Firebase real; y la repetición de la matriz original TC-01…TC-23 de la Práctica 8 con tokens (la cubren los 20 casos de punta a punta, no se rehízo esa matriz).

---

**Etapa 2 casi completa (4 de noviembre):** hechos D-05, D-04, el indicador de estado, la matriz de la Actividad 3 (con repositorios en memoria) y SQLite real. Falta probar los repositorios contra Firestore. Pruebas actuales: backend 91 · app 125 (+ 1 de integración en el emulador de Android) · firmware 15.

**Documentación:** `Parcial-2-Documentacion.docx` actualizado con las secciones 10.5 a 10.10 (estado de todas las prácticas, control de acceso, chat, defectos de la práctica 8, práctica 9 y verificación). Copia del original: `Parcial-2-Documentacion.version-anterior.docx`.

## 1. Semáforo de las 13 tareas

| Tarea | De qué trata | Estado | Cómo está hoy en VitaSync |
|---|---|---|---|
| Práctica 1 | Firmware (LED, botón) | ✅ | `vitasync-firmware-sim/` y pantalla Dispositivo |
| Práctica 2 | Sensor + Bluetooth | 🟡 | Sensor simulado, pero las lecturas viajan por HTTP; **no hay Bluetooth** |
| Práctica 3 | Consumir una URL | ✅ | `ApiCliente` y URL separada en `api_config.dart` |
| Práctica 4 | Base local (Room/SQLite) | ✅ | SQLite real en Android e iOS (`MetricaDaoSqlite`: índice, transacción, consultas parametrizadas y migración 1→2); en la web `localStorage`. Es solo una caché: la única fuente de verdad es Firestore |
| Práctica 5 | Código seguro | 🟡 | PIN con hash, bloqueo, inactividad; ahora también token, dueño por cuenta y clave de dispositivo, **pero apagados por omisión** |
| Práctica 6 | Dos dispositivos conversando | ✅ | Chat médico-paciente por el backend |
| Práctica 7 | Roles masivos y archivos | 🟡 | Roles en lote por el administrador y archivos en el chat, con pruebas. Faltan invitaciones por URL y probar contra Firebase Authentication real
| Práctica 8 | Pruebas de caja negra | ✅ | Documento entregado. Los 6 defectos están corregidos (D-06 con la salvedad de arriba). Caja negra del backend: 22 de 23 (falla TC-20 porque ese servidor corre sin seguridad) |
| Práctica 9 | Base compartida entre dispositivos | ✅ | El Resumen dice si los datos están confirmados por el servidor o vienen de la caché; el Chat guarda como «pendiente» lo que no se pudo enviar; y las **metas** las editan la paciente y su médico con control de versión (409 + diálogo «usar las del otro / sobrescribir»). Falta probar la transacción contra Firestore real
| Práctica 10 | Autenticación y reglas de seguridad | ✅ | Correo/contraseña, UID en pantalla, dueño por cuenta, reglas de Firestore (17/17) y la app probada en emulador; solo en emuladores, no en la nube real |
| Actividad 1 | Capturar, enviar y consultar en la nube | ✅ | Pestaña «Contactos» de emergencia: alta, lista y borrado guardados en Firestore (`usuarios/{cuenta}/contactos`), con validación en el servidor, máximo 5, sin teléfonos repetidos, control de dueño y reglas de Firestore |
| Actividad 2 | Pirámide de pruebas | 🟡 | Diagnóstico en `PIRAMIDE-DE-PRUEBAS.md` (315 pruebas: 99 unitarias, 164 de integración, 52 de punta a punta, de las cuales **solo 1 usa la app real**) y CI escrito en `.github/workflows/pruebas.yml` (**validado como YAML, sin ejecutar todavía en GitHub**) |
| Actividad 3 | Matriz de pruebas de Firestore | 🟡 | Aplicada a VitaSync en `vitasync-backend/MATRIZ-PRUEBAS-FIRESTORE.md` con repositorios en memoria y HTTP; **falta probarla contra Firestore** (eliminación de subcolecciones y persistencia del servidor) |

**Resumen:** ✅ 7 · 🟡 5 · ❌ 1.

---

## 2. Plan en 5 etapas (en este orden, porque unas dependen de otras)

Tamaño: **S** = unas horas · **M** = una sesión larga · **L** = varias sesiones.

### Etapa 1 — Seguridad (cubre P5, P10 y cierra los defectos D-01, D-02 y D-03) · tamaño L
*Por qué primero: el resto (roles, sincronización, pruebas) se apoya en saber quién es cada usuario.*

- [x] **Decisión A** (ver sección 3): se adoptó la opción A (Firebase Authentication) por ser la recomendada; si prefieres la B, se cambia solo el verificador de tokens
- [x] Inicio de sesión con correo y contraseña en la app Flutter (por la API REST de Firebase Authentication, sin plugin nativo); UID en pantalla; crear cuenta VitaSync desde la app (19 pruebas nuevas)
- [x] El backend verifica el token en cada petición y rechaza con 401 si falta o es inválido (`seguridad/ControlDeAcceso`, apagado por omisión)
- [x] Cada cuenta guarda `propietarioUid` y el servidor comprueba que quien pide es el dueño (403 si no); lecturas, historial, chat y firmware se protegen por la cuenta a la que pertenecen
- [x] Validar en el servidor: nombre y usuario obligatorios y únicos (D-01, D-02) — TC-11 y TC-12 de la Práctica 8 ya pasan
- [x] Clave de dispositivo para el firmware simulado (sync, orden y aplicar no pueden pedir token de persona); la app tiene el botón «Vincular reloj» que la muestra una sola vez
- [x] Activar la seguridad en el servidor de pruebas y probar de punta a punta (20 de 20)
- [x] Caja negra con seguridad: cubierta por los 20 casos de punta a punta (no se rehízo la matriz original de la Práctica 8). Pendiente solo: decidir cuándo encender la seguridad por omisión
- [x] Probar la app en un emulador de Android contra el servidor con seguridad activa (prueba de integración, 6 capturas)
- [ ] Probar `FirebaseVerificadorToken` (firma real): solo se puede con el proyecto de Firebase real (el emulador no firma los tokens)
- [x] Escribir `firestore.rules` (solo el dueño lee; el cliente no escribe; lo demás cerrado) y probarlas: 17 de 17
- [x] Borrar reloj, lecturas, chat y orden de firmware al eliminar una cuenta (D-04): interfaz `LimpiezaDeCuenta` en cada servicio; la cuenta se borra al final para poder reintentar si algo falla (6 pruebas nuevas)

**Listo cuando:** los casos TC-11, TC-12, TC-20 de la Práctica 8 pasan y A no puede leer, modificar ni eliminar nada de B.

> Ojo: el backend usa el *Admin SDK* de Firebase, que **se salta las reglas**. Por eso las reglas solas no protegen a VitaSync: la protección real es la comprobación de dueño en el backend. Las reglas quedan como segunda barrera por si algún día la app accede directo a Firestore.

### Etapa 2 — Datos confiables (cubre P4, P9 y Actividad 3) · tamaño M

- [x] Cuenta sin lecturas muestra «Aún no hay lecturas» y la caché **no guarda** valores inventados (D-05): el servidor responde 204 en vez de inventar datos; app y web lo toleran (5 pruebas nuevas en la app, 1 reescrita y 2 nuevas en el backend)
- [x] Caché en **SQLite real** (`sqflite`) sin cambiar el contrato `MetricaDao`; la web conserva `shared_preferences`. 11 pruebas nuevas (migración, persistencia, límite por cuenta, consultas parametrizadas) y verificado en el emulador de Android
- [x] Indicador de estado (Práctica 9): Resumen «Confirmado por el servidor» / «caché del teléfono»; Chat con mensajes **pendientes** que se reenvían solos y en orden (6 pruebas nuevas). Pendiente: conflictos de versión
- [~] Matriz TC01–TC08 de la Actividad 3 aplicada a VitaSync (`MATRIZ-PRUEBAS-FIRESTORE.md`): TC01–TC07 verificados con repositorios en memoria y en la app; **pendiente contra Firestore**: borrado real de subcolecciones y persistencia del servidor. Se intentó con el cliente de Java y el emulador y no se logró (el emulador rechaza la conexión) — probar arrancando el backend real con `FIRESTORE_EMULATOR_HOST` o con la nube

**Listo cuando:** los 8 casos pasan, con la base verificada directamente (no solo por la pantalla).

### Etapa 3 — Dispositivos, roles y nube (cubre P2, P7, P9 y Actividad 1) · tamaño L

- [x] **Práctica 9 dentro de VitaSync:** «Metas» (pasos, calorías, sueño) que editan la paciente y su médico, con control de versión: si el segundo guarda con una versión vieja el servidor responde 409 y la app ofrece «usar las del otro» o «sobrescribir con las mías». 16 pruebas del servidor y 16 de la app. **No probado:** la transacción contra Firestore real ni el flujo en el emulador de Android
- [x] **Actividad 1 dentro de VitaSync:** «Contactos de emergencia» (capturar, guardar en la nube y consultar): 12 pruebas del servidor, 17 de la app, 9 casos de punta a punta, 5 de reglas y la pestaña probada en el emulador de Android
- [x] **Práctica 7 (en parte):** el administrador asigna roles a varias personas de un solo envío (`PUT /api/admin/roles`: se valida todo el lote antes de cambiar nada; solo «paciente» y «médico»; no se toca a un administrador) y el chat envía archivos (PNG, JPG, PDF o TXT hasta 300 KB, con el contenido verificado en el servidor). 18 pruebas del servidor y 17 de la app. **No hecho:** invitaciones por URL de un solo uso, nombrar administrador desde la app, reparto atómico de roles (Firebase no lo ofrece), abrir PDF dentro de la app, y probar los roles contra Firebase Authentication real
- [ ] **Práctica 2:** Bluetooth (BLE) reloj → teléfono, o una nota de diseño que justifique usar HTTP

### Etapa 4 — Calidad (cubre P8 y Actividad 2) · tamaño M

- [x] D-06 (detalles de interfaz): cuentas en orden alfabético, selector de rol alineado, «Abrir chat nuevo» arriba y fuera del alcance de los avisos (9 pruebas nuevas). Pendiente: repetir la caja negra de la Práctica 8 como informe de regresión (última corrida del backend: 22 de 23; solo falla TC-20, porque ese servidor corre con la seguridad apagada)
- [ ] **Diagnóstico de la pirámide** de VitaSync (cuántas pruebas hay de cada nivel y cuáles se ejecutan solas)
- [ ] Crear `.github/workflows/pruebas.yml`: unitarias e integración en cada push; E2E antes de entregar
- [ ] Agregar al menos una prueba E2E del flujo crítico (iniciar sesión → ver métricas → chatear)
- [ ] Cobertura por capa y un par de mutaciones, como en la Actividad 2

### Etapa 5 — Cierre · tamaño S

- [ ] Actualizar `README.md` y `CHANGELOG.md` (versión 2.0.0)
- [ ] Documento final y presentación actualizados con todo lo integrado
- [ ] Commit y etiqueta de versión (**solo cuando tú lo pidas**)

---

## 3. Decisiones que necesito de ti

1. **¿Cómo se identifican las cuentas?**
   - **Opción A (recomendada):** Firebase Authentication con correo y contraseña; el backend valida el token. Cubre la Práctica 10 de verdad y reutiliza `firebase-admin`, que el backend ya tiene.
   - **Opción B:** token propio que emite el backend al verificar el PIN. Es más simple, pero no cubre «correo/contraseña» ni el UID de la Práctica 10.
2. **¿Archivamos `PRACTICA 8/vitasync-*`?** Dejar dos copias confunde. Mi sugerencia: dejarlas hasta que compiles desde `Proyecto individual/` y luego archivarlas.
3. **¿Práctica 7 y Bluetooth ahora o al final?** Son lo más grande. Mi sugerencia: al final de la Etapa 3.

## 4. Qué ya está probado hoy y qué no

- Las Prácticas 9 y 10 y las Actividades 1–3 funcionan **como proyectos separados**, no dentro de VitaSync.
- Todas las pruebas de Firebase se hicieron con los **emuladores**, no con un proyecto en la nube; para la nube real hace falta tu `google-services.json`.
- No he compilado todavía VitaSync desde `Proyecto individual/` después de la fusión.
