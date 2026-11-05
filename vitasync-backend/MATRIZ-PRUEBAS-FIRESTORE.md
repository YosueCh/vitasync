# Matriz de pruebas de datos (Actividad 3) aplicada a VitaSync

La Actividad 3 probó ocho casos sobre una colección `reportes` de una app aparte (ReportesApp). Aquí se aplican los mismos ocho casos a las colecciones reales de VitaSync: **`usuarios`** (cuentas) y **`devices`** con su subcolección **`historial`** (reloj y lecturas).

Fecha: 4 de noviembre de 2026.

## Cómo leer los resultados

- **Verificado** = hay una prueba automática que pasa.
- **Verificado en memoria** = la prueba corre los controladores y servicios REALES de VitaSync, pero con repositorios en memoria en lugar de Firestore. Demuestra la lógica y el contrato HTTP, **no** el comportamiento de Firestore.
- **No verificado** = no hay prueba que lo demuestre.

| Caso | Qué se prueba en VitaSync | Evidencia | Resultado |
|---|---|---|---|
| TC01 Alta válida | Crear una cuenta con nombre y usuario correctos y poder consultarla | Caja negra TC-01 · E2E-03 (con sesión) | Verificado en memoria |
| TC02 Campos vacíos | Nombre o usuario vacíos, `{}`, usuario con espacios o nombre de un carácter: se rechaza con 400 y no se guarda nada | Caja negra TC-11 · E2E-06 · `ControlDeAccesoTest.alta_conDatosVacios_400` | Verificado en memoria |
| TC03 Identificador repetido | Un segundo alta con el mismo usuario (aunque cambien las mayúsculas) da 409 y no pisa la primera cuenta | Caja negra TC-12 · E2E-07 | Verificado en memoria |
| TC04 Actualización | Deshabilitar y volver a habilitar una cuenta; el cambio se conserva al consultarla de nuevo y no altera los demás campos | Caja negra TC-06 | Verificado en memoria |
| TC05 Eliminación | Al eliminar una cuenta desaparecen la cuenta, el reloj, el historial, el chat y la orden de firmware, sin tocar los de otra cuenta; si la limpieza falla a medias, la cuenta sigue ahí para reintentar | Caja negra TC-07 y TC-17 · `EliminarCuentaTest` (6 pruebas) | Verificado en memoria |
| TC06 Documento inexistente | Consultar, eliminar o pedir métricas de algo que no existe: 404 (o 403 con seguridad, para no revelar qué existe) y 204 sin lecturas; nada se inventa | Caja negra TC-21 · `ControlDeAccesoTest.cuentaInexistente_seResponde403…` · `SmartwatchHistorialTest.metricas_sinNingunaLectura_noInventaDatos` · `EliminarCuentaTest.eliminarUnaCuentaInexistente…` | Verificado en memoria |
| TC07 Pérdida de conexión | **App:** un mensaje sin conexión queda «Pendiente de enviar» y se reenvía solo en orden; el Resumen marca los datos de la caché como no confirmados. **Servidor:** si falla el guardado del historial la sincronización del reloj no se pierde | `pendientes_test.dart` (6) · `SmartwatchHistorialTest` | Verificado en la app y en el servidor con un fallo simulado; **no** apagando un Firestore real |
| TC08 Persistencia | **App:** las lecturas guardadas en el teléfono sobreviven al cierre de la app. **Servidor:** que lo guardado en Firestore sobreviva a un reinicio del backend | App: «los datos persisten al volver a abrir la base» (`servicios_test.dart`) | App: verificado. **Servidor contra Firestore: no verificado** |

## Defectos que esta matriz ayudó a cerrar

- **D-01 y D-02** (TC02 y TC03): el servidor validaba nada; ahora responde 400 y 409.
- **D-04** (TC05): al eliminar una cuenta quedaban el reloj, el historial y el chat huérfanos. Ahora `UsuarioService.eliminar` invoca la limpieza de cada parte antes de borrar la cuenta.
- **D-05** (TC06): una cuenta sin lecturas veía valores inventados; ahora el servidor responde 204.

## Lo que NO está verificado y por qué

Se intentó probar los repositorios de VitaSync (`UsuarioRepository`, `DispositivoRepository`, `HistorialMetricasRepository`) contra el emulador de Firestore desde Java, para demostrar TC05 con subcolecciones y TC08 con un cliente nuevo. **No se logró**: el cliente de Java no pudo comunicarse con el emulador en este equipo (el emulador registra «Detected non-HTTP/2 connection» con cuatro configuraciones distintas del cliente) y se retiró la prueba en vez de dejarla siempre omitida.

Por eso quedan sin demostrar contra Firestore:
- que `HistorialMetricasRepository.eliminarTodo` borre de verdad todos los documentos de la subcolección (Firestore no los borra solo);
- que las cuentas, relojes y lecturas guardados por el servidor persistan tras un reinicio.

Esos dos puntos sí se probaron con Firestore real en la Actividad 3 (la app ReportesApp contra el emulador, TC05 y TC08), pero allí el código de acceso a datos es el de esa app, no el de VitaSync.

**Siguiente paso recomendado:** probar esos dos puntos arrancando el backend real contra el emulador de Firestore con la variable `FIRESTORE_EMULATOR_HOST` y revisando los documentos desde la interfaz del emulador, o directamente con el proyecto de Firebase de la nube.
