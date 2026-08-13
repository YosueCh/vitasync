# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.0.0/)
y versionado con [SemVer](https://semver.org/lang/es/) (`MAYOR.MENOR.PARCHE`):
- **MAYOR**: cambios que rompen compatibilidad con versiones anteriores.
- **MENOR**: funciones nuevas que no rompen lo existente.
- **PARCHE**: correcciones de bugs.

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
