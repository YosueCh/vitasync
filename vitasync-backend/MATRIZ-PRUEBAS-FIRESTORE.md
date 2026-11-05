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

## Verificación contra Firestore REAL (5 de noviembre de 2026)

Con la clave de servicio del proyecto de Firebase se corrió `FirestoreRealTest` (6 pruebas, todas pasan, 41 s) contra el Firestore de la nube —no un emulador— usando los repositorios reales de VitaSync. Todo lo que crea lleva el prefijo `zz-prueba-` y se borra al terminar; después se comprobó por REST que no quedó ningún resto y que no se tocó ningún documento previo.

| Caso | Qué se demostró contra Firestore real |
|---|---|
| TC01 Alta | La cuenta se guarda con su dueña y se lee de vuelta |
| TC04 Actualización | Metas: guardar con versión sube la versión; un segundo guardado con la versión vieja da conflicto y devuelve lo actual |
| TC05 Eliminación | Cuenta con contactos (subcolección), metas, reloj y 3 lecturas de historial: al eliminarla desaparece todo y no queda ningún documento en las subcolecciones. **Esto era lo que no se había podido demostrar** |
| TC08 Persistencia | Un repositorio nuevo (otra instancia del cliente) lee los contactos y las metas guardados por el primero; el historial vuelve ordenado, la lectura más reciente primero |
| Transacciones | Dos guardados de metas con la misma versión a la vez: pasa exactamente uno y el otro recibe el conflicto (la versión final es 1). Dos personas canjeando el mismo código de invitación a la vez: lo canjea solo una. Invitación caducada o inexistente: se rechaza |

Para repetirlo: `mvn test -Dtest=FirestoreRealTest -Dfirestore.real=true -Dfirebase.auth.emulator.host=` (el último parámetro es importante: si la variable del emulador de Authentication está puesta, el cliente de Java falla con UNAUTHENTICATED contra la nube).

## Personas reales y reglas en la nube (5 de noviembre de 2026)

Con el método «Correo y contraseña» activado y la app web registrada se corrió `FirebaseNubeRealTest` (3 pruebas, todas pasan, 23 s) contra Authentication y Firestore reales. Crea dos personas «zz-prueba-…» y una cuenta VitaSync, y todo se borró al terminar (se comprobó: 0 restos).

| Qué se demostró | Resultado |
|---|---|
| Dos personas reales se registran y el servidor verifica su token firmado | Pasa; el rol por omisión es paciente |
| Un token con la firma alterada, con el contenido cambiado (otro UID) o inventado | Rechazado (esto comprueba la firma real, que el emulador no puede) |
| Asignar el rol «medico» en la nube | El token nuevo de esa persona lo trae y el servidor lo lee |
| Reglas, la dueña con su token | Lee su cuenta, su contacto y sus metas (200) |
| Reglas, otra persona real (aunque sea médica) y un anónimo | 403 en todo |
| Reglas, escribir desde el cliente | 403 aun siendo la dueña (cuenta, metas y crear cuentas) |
| Reglas, `tv_sessions`, `invitaciones` y listar todas las cuentas | 403 |

Para repetirlo: `mvn test -Dtest=FirebaseNubeRealTest -Dfirestore.real=true -Dfirebase.auth.emulator.host= -Dfirebase.apikey=<clave de API web>` (la clave de API web no es secreta).

## Lo que sigue sin verificar

- **Reiniciar el backend completo** y ver los datos: lo que se probó es leer con un cliente nuevo; los datos viven en la nube, así que sobreviven por construcción, pero no se hizo la prueba literal de apagar y volver a encender.
- **TC07 contra Firestore real**: la pérdida de conexión solo se probó con fallos simulados.
- **Las reglas por dueño de Firestore, con una persona real:** SÍ se probaron en la nube (ver abajo).
- **El backend completo (`VitasyncBackendApplication`) arrancado contra la nube:** no se hizo, porque pide Elasticsearch; las pruebas de la nube usan los repositorios y el verificador de tokens reales directamente.
