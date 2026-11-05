# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.0.0/)
y versionado con [SemVer](https://semver.org/lang/es/) (`MAYOR.MENOR.PARCHE`):
- **MAYOR**: cambios que rompen compatibilidad con versiones anteriores.
- **MENOR**: funciones nuevas que no rompen lo existente.
- **PARCHE**: correcciones de bugs.

## [Sin publicar] — Desarrollo Móvil Integral: vista móvil e integración de prácticas

### Añadido
- Práctica 7 dentro de VitaSync: roles en lote y archivos en el chat. `GET /api/admin/personas` y
  `PUT /api/admin/roles` (solo administrador; el lote se valida completo antes de aplicarse; solo paciente y
  médico). `POST /api/chat/{id}/archivos` y `GET .../archivos/{mensaje}` con PNG, JPG, PDF o TXT de hasta 300 KB,
  contenido verificado por sus primeros bytes, nombre limpio, cupo por conversación y descarga como adjunto.
  En la app: botón de adjuntar, visor de imagen y texto, y pestaña «Roles». 18 pruebas del servidor y 17 de la app.
- Práctica 9 dentro de VitaSync: metas de salud (pasos, calorías, sueño) compartidas entre la paciente y su médico.
  `GET/PUT /api/metas` con control de versión (409 con las metas actuales si alguien se adelantó), fusión por
  campos sin versión, quién editó según el rol del token, acceso del médico solo a chat y metas, borrado con la
  cuenta, reglas de Firestore y metas reales en la sincronización del reloj. En la app: «Mis metas» (Resumen),
  «Metas del paciente» (Chat, médico) y diálogo de conflicto. Pruebas: 16 en el servidor y 16 en la app.

### Corregido
- D-06 de la Práctica 8 (detalles de interfaz): la lista de cuentas sale en orden alfabético estable; el
  selector de rol del chat pone «Soy:» arriba y las opciones debajo, alineadas; el botón «Abrir chat nuevo»
  pasó junto al aviso de chat cerrado, arriba, para que los avisos inferiores no lo tapen; y se protege con
  una prueba que el error sin servidor llegue a los 4 segundos. 9 pruebas nuevas.
- D-04 de la Práctica 8: al eliminar una cuenta se borran también su reloj, su historial de lecturas, su chat
  y su orden de firmware (interfaz `LimpiezaDeCuenta`); si la limpieza falla a medias la cuenta sigue
  existiendo para reintentar. 6 pruebas nuevas (`EliminarCuentaTest`).
- D-05 de la Práctica 8: una cuenta sin lecturas ya no recibe valores de ejemplo como si fueran reales.
  `GET /api/smartwatch/metrics` responde 204 cuando no hay lecturas; la app móvil muestra «Aún no hay
  lecturas» y no guarda nada en su caché local; la web simplemente no muestra el panel.
- Alta de cuentas validada en el servidor (D-01 y D-02 de la Práctica 8): nombre y usuario
  obligatorios (400) y usuario único sin distinguir mayúsculas (409).

### Agregado
- Actividad 2 en VitaSync: diagnóstico de la pirámide de pruebas (`PIRAMIDE-DE-PRUEBAS.md` y
  `scripts/diagnostico-piramide.mjs`) y ejecución automática escrita en `.github/workflows/pruebas.yml`
  (backend, app, firmware y seguridad de punta a punta). Validado como YAML; aún sin ejecutar en GitHub.
- Actividad 1 dentro de VitaSync: contactos de emergencia. Pestaña «Contactos» en la app (alta, lista y
  borrado) y `/api/contactos` en el servidor, con los datos en Firestore (`usuarios/{cuenta}/contactos`).
  El servidor valida (nombre de 2 a 60 caracteres, teléfono de 7 a 15 dígitos normalizado, máximo 5 por
  cuenta, sin teléfonos repetidos), cada persona solo toca los de sus cuentas y se borran con la cuenta.
  Reglas de Firestore para la subcolección. 12 pruebas del servidor, 17 de la app, 9 de punta a punta y 5
  de reglas.
- Práctica 4 con SQLite real: la caché local de métricas de la app usa SQLite en Android e iOS
  (`MetricaDaoSqlite`, con índice por cuenta y fecha, consultas parametrizadas y migración de esquema
  1→2 con `ALTER TABLE`); la web conserva `localStorage`. `abrirDaoLocal()` elige según la plataforma.
  Es solo una caché: la única fuente de verdad es Firestore. 11 pruebas nuevas.
- Control de acceso del backend (Práctica 10 aplicada a VitaSync, defecto D-03): filtro
  `ControlDeAcceso` que exige token de Firebase Authentication (401) y comprueba que la cuenta
  pedida sea de quien la pide (403); cada cuenta guarda su `propietarioUid`; listar devuelve solo las
  cuentas propias; el rol «medico» accede al chat y «admin» a todo. Se activa con
  `vitasync.seguridad.activa=true` (apagado por omisión hasta que la app móvil inicie sesión).
  Clave de dispositivo: al vincular el reloj (`POST /api/smartwatch/connect`) el servidor entrega una
  clave una sola vez (solo guarda su hash); el firmware la manda en `X-Clave-Dispositivo` en sync, orden
  y aplicar. 19 pruebas nuevas del backend (`ControlDeAccesoTest`).
- Práctica 9 en la app móvil: el Resumen indica si los datos están «Confirmados por el servidor» o vienen
  de la «caché del teléfono (sin confirmar)»; el Chat ya no pierde un mensaje sin conexión: queda «Pendiente
  de enviar» y se reenvía solo, en orden, al volver el servidor (6 pruebas nuevas). `ApiException` distingue
  un fallo de conexión de un rechazo del servidor.
- `vitasync-backend/MATRIZ-PRUEBAS-FIRESTORE.md`: los ocho casos de la Actividad 3 aplicados a las colecciones de
  VitaSync, con la evidencia y lo que no se pudo verificar contra Firestore.
- Documentación del Parcial 2 actualizada con el estado de todas las prácticas (secciones 10.5 a 10.10).
- Firmware simulado: opción `--clave`; con ella arranca sin conectarse solo y se identifica con la
  clave del dispositivo (3 pruebas nuevas).
- App móvil: con `--dart-define=SEGURIDAD=true` pide correo y contraseña (API REST de Firebase
  Authentication), muestra el correo y el UID, manda el token en cada petición, permite crear la cuenta
  VitaSync y vincular el reloj (muestra su clave una vez). 19 pruebas nuevas.
- `vitasync-backend/seguridad-e2e/`: prueba de punta a punta con dos personas reales del emulador de
  Authentication contra el backend con la seguridad activa (20 casos) y prueba de las reglas de
  Firestore (17 casos).
- `vitasync-backend/firestore.rules`: segunda barrera de seguridad. Cada persona lee solo lo suyo
  (cuentas con su `propietarioUid`, su reloj y su historial); desde el cliente no se escribe nada (lo escribe
  el backend con el Admin SDK); lo demás queda cerrado.
- Prueba de integración en el emulador de Android (`flutter drive`,
  `integration_test/seguridad_test.dart`): la app real contra el backend con seguridad y Authentication,
  con 6 capturas en `evidencias-integracion/seguridad/`.
- Pruebas de caja negra (Práctica 8, Desarrollo Móvil Integral): 22 requisitos
  verificables y 40 casos (23 por API y 17 en la app sobre un emulador).
  `ServidorPruebas` levanta los controladores y servicios reales con
  repositorios en memoria (sin Firestore ni Elasticsearch) y
  `CajaNegraApiTest` deja la petición y la respuesta de cada caso como
  evidencia. Resultado: 34 casos pasan y 6 fallan; la entrega se rechaza por
  falta de control de acceso en la API, datos inventados en las cards y alta de
  cuentas sin validar. Ver `Practica8_PruebasCajaNegra.docx` y
  `evidencias-caja-negra/`.
- Historial de métricas en la base de datos (integra las Prácticas 1 y 2, el
  firmware del dispositivo: lo que el reloj o el firmware simulado lee ya no se
  pierde). Cada sincronización (`POST /api/smartwatch/sync`) guarda la lectura
  en Firestore (`devices/{usuarioId}/historial`) y `GET /api/smartwatch/historial`
  la devuelve, la más reciente primero. Las cards del Resumen leen la última
  lectura de la base de datos (antes, tras reiniciar el servidor, mostraban
  datos inventados) y **al tocar una card se abre el historial** de esa
  métrica: lecturas con fecha y hora, mínimo/promedio/máximo y una gráfica.
  Sin conexión se muestra el historial guardado en el teléfono. Backend: 8
  pruebas nuevas. App: 12 pruebas nuevas.
- Chat médico-paciente (Práctica 6, Desarrollo Móvil Integral). Dos teléfonos
  con la misma app: uno entra como **Médico (Dispositivo A)** y elige al
  paciente; el otro como **Paciente (Dispositivo B)**. No se conectan entre
  sí: ambos usan la URL del backend (`/api/chat/{pacienteId}/...`), que guarda
  la conversación en memoria hasta que el paciente cierra el chat (entonces
  se borra todo). Incluye hora de envío, contador por dispositivo, aviso
  visual al enviar/recibir, validación de mensajes vacíos (y de más de 200
  caracteres) y botón de cerrar chat (paciente) o limpiar pantalla (médico).
  Backend: paquete `chat/` (14 pruebas). App: pestaña "Chat" (10 pruebas).
- Vista móvil (`flutter-mobile-app`): diseño del Parcial 1 conectado al
  backend real (cuentas, métricas y estado del dispositivo por HTTP).
- Caché local de métricas con esquema versionado y migración; sin conexión
  se muestra la última lectura guardada (integra la Práctica 4, Room).
- Actualización de firmware por aire: endpoints `/api/firmware/*`
  (`ultima`, `estado`, `solicitar`, `orden`, `aplicar`) y botón en la vista
  móvil.
- `vitasync-firmware-sim/`: firmware simulado con `setup()`/`loop()`, LED,
  botón y sensor de presencia en consola (integra la Práctica 1).
- PIN real de la vista móvil (Parcial 2): `POST /api/usuarios/{id}/pin` y
  `/pin/verificar`. El servidor guarda un salt de 16 bytes y SHA-256(salt:pin),
  compara en tiempo constante y bloquea la cuenta 5 minutos tras 5 fallos
  seguidos (429). `GET /api/usuarios` incluye `tienePin`.
- La app pide crear y confirmar el PIN si la cuenta aún no tiene uno, y
  cierra la sesión a los 45 s sin tocar la pantalla (`ControlInactividad`).
- Pruebas: 84 en la vista móvil (antes 16), 12 en el simulador y 41 en el
  backend (12 del servicio de PIN, 4 de firmware, 3 de smartwatch, 8 del
  historial de lecturas, 14 del chat).

### Cambiado
- El PIN provisional de la vista móvil (aceptaba cualquier PIN de 4 dígitos)
  se reemplazó por la verificación en el backend; se quitó el aviso de
  "vista de diseño" de la pantalla de PIN.
- CORS global (`CorsConfig`): además de `localhost:4200` acepta `localhost`
  en cualquier puerto y las redes privadas, para probar desde un teléfono.
- La pantalla Dispositivo muestra el estado real que reporta el backend
  (antes la etiqueta "Conectado" era fija).
- `GET /api/smartwatch/metrics` ya no inventa datos tras reiniciar el
  servidor: devuelve la última lectura guardada en la base de datos y solo
  genera una de ejemplo si nunca hubo ninguna.
- `SaludRepository` (app móvil) tiene un método nuevo, `obtenerHistorial`;
  `ShellScreen` pasa de 2 a 3 pestañas (Resumen, Dispositivo, Chat) y
  `VitaSyncMobileApp` acepta opcionalmente `chat` e `intervaloChat`.
- Las cards del Resumen son tocables (abren el historial de su métrica).
- `SmartwatchService` recibe además un `HistorialMetricasRepository`
  opcional (el constructor anterior sigue funcionando sin historial).

## [1.0.1] — Pruebas automatizadas

### Corregido
- El único test del frontend era el que trae Angular por defecto sin
  modificar (buscaba el texto "Hello, vitasync-web", que ya no existe) —
  se reemplazó por pruebas reales del shell de la app.

### Agregado
- El backend no tenía ninguna prueba automatizada — se agregó
  `SmartwatchServiceTest`, incluyendo una prueba de regresión para el bug
  de "Sincronizar con body vacío guardaba ceros".

## [1.0.0] — Versión estable de entrega

Primera versión completa de VitaSync: las tres piezas (web, backend, reloj)
funcionando de extremo a extremo con datos reales, no simulados.

### Agregado
- Sitio web (Angular) con las 14 páginas/elementos que pide la Práctica 1-2.
- Buscador conectado a Elasticsearch, con respaldo local (FlexSearch) si el
  servidor no está disponible.
- Widget de estadísticas en Flutter Web, incrustado en el Dashboard.
- Sincronización real reloj ↔ web ↔ servidor, separada por cuenta de usuario
  (cada cuenta tiene su propio dispositivo y sus propias métricas).
- Sondeo automático (cada 3 segundos) en la web y en el reloj, para que un
  cambio hecho en un lado aparezca solo en el otro, sin recargar nada.
- Enlace con Smart TV con código de 6 dígitos, tipo Chromecast.
- Autenticación del reloj con PIN (hash SHA-256 + salt) y bloqueo de
  capturas de pantalla (`FLAG_SECURE`) mientras la app está abierta.
- Gestión de cuentas de usuario (crear, habilitar/deshabilitar, eliminar,
  probar login) real, respaldada por Firestore.

### Corregido
- El backend no arrancaba si faltaba la configuración de Firebase — ahora
  esa parte queda opcional y el resto del servidor arranca igual.
- El widget de Flutter Web se veía en blanco por faltar `--base-href` al
  compilarlo.
- La pantalla del reloj se veía cortada en una esfera redonda real — se
  agregó scroll para que el contenido quepa.
- El panel de Smart TV no se actualizaba solo por ausencia de `zone.js` en
  el proyecto — se resolvió usando `signal()` en vez de variables planas.
- El botón "Sincronizar" de la web mandaba un cuerpo vacío que el backend
  guardaba como una lectura en cero en vez de generar datos nuevos.

## [0.1.0] — Prácticas individuales

Desarrollo de las 13 prácticas de la materia por separado, antes de
integrarlas en un solo producto.
