# Probar VitaSync en un celular Android

Hay dos caminos. El celular y la PC tienen que estar **en la misma red Wi-Fi**.

| | Camino A: servidor de pruebas | Camino B: tu Firebase real |
|---|---|---|
| Datos | En memoria (se pierden al apagar el servidor) | Guardados de verdad en Firestore |
| Inicio de sesión | Emulador de Authentication en la PC | Firebase Authentication de la nube |
| Sirve para | Ver y enseñar la app rápido | Probar el proyecto completo |
| Necesita | Node (firebase-tools) y Maven | `serviceAccountKey.json` y Maven |

En los dos, `<IP-DE-LA-PC>` es la dirección de la PC en la red (en Windows: `ipconfig`, línea «Dirección IPv4»,
por ejemplo `192.168.100.57`).

## Preparación común

1. **Celular:** Ajustes → Acerca del teléfono → toca 7 veces «Número de compilación» → Opciones de desarrollador →
   activa «Depuración USB». Conéctalo por USB y acepta el aviso. Comprueba con `adb devices` que aparezca.
   (Si prefieres no usar cable, el APK de abajo se pasa por mensaje, correo o USB.)
2. **Firewall de Windows** (PowerShell como administrador), una vez:
   ```powershell
   netsh advfirewall firewall add rule name="VitaSync 8081" dir=in action=allow protocol=TCP localport=8081
   netsh advfirewall firewall add rule name="VitaSync Auth 9099" dir=in action=allow protocol=TCP localport=9099
   ```
3. Cierra cualquier otro servidor que esté usando el puerto 8081.

## Camino B: contra tu Firebase real (recomendado)

1. Pon `serviceAccountKey.json` en `vitasync-backend/src/main/resources/` (ya está ignorado por git).
2. Arranca el backend real (no necesita Elasticsearch):
   ```bash
   cd vitasync-backend
   mvn spring-boot:run
   ```
   Debe terminar con «Started VitasyncBackendApplication». Con la seguridad encendida (por omisión) exige sesión.
3. Corre la app en el celular, apuntando a la PC y a Firebase de la nube:
   ```bash
   cd vitasync-frontend/flutter-mobile-app
   flutter run -d <id-del-celular> \
     --dart-define=API_HOST=<IP-DE-LA-PC> \
     --dart-define=AUTH_BASE=https://identitytoolkit.googleapis.com \
     --dart-define=FIREBASE_API_KEY=<Clave de API web del proyecto>
   ```
   La «Clave de API web» está en la consola de Firebase → Configuración del proyecto → General → «Tus apps». No es
   secreta (va dentro de cualquier app).
4. En la app: «Crear cuenta» con un correo y contraseña, crea tu cuenta VitaSync, elige un PIN y listo.

## Camino A: servidor de pruebas y emulador de Authentication

1. Emulador de Authentication **abierto a la red** (por omisión solo escucha en la propia PC). En `firebase.json`:
   ```json
   { "emulators": { "auth": { "host": "0.0.0.0", "port": 9099 } } }
   ```
   y luego `npx firebase-tools emulators:start --only auth --project demo-vitasync`.
2. Servidor de pruebas con la seguridad encendida:
   ```bash
   cd vitasync-backend
   mvn test-compile spring-boot:run -Dspring-boot.run.useTestClasspath=true \
     -Dspring-boot.run.directories=target/test-classes \
     -Dspring-boot.run.main-class=com.vitasync.backend.blackbox.ServidorPruebas \
     "-Dspring-boot.run.arguments=--vitasync.seguridad.activa=true"
   ```
3. App: `flutter run -d <id-del-celular> --dart-define=API_HOST=<IP-DE-LA-PC>` (el inicio de sesión toma
   `<IP-DE-LA-PC>:9099` por omisión).

## Instalar un APK en vez de usar `flutter run`

```bash
flutter build apk --release --dart-define=API_HOST=<IP-DE-LA-PC> \
  --dart-define=AUTH_BASE=https://identitytoolkit.googleapis.com --dart-define=FIREBASE_API_KEY=<clave>
```
El archivo queda en `build/app/outputs/flutter-apk/app-release.apk`. Cópialo al celular y ábrelo (Android pedirá
permitir «instalar apps de origen desconocido»). El APK lleva la IP de la PC dentro: si cambia, hay que
volver a generarlo.

## Qué conviene probar

- Crear cuenta, cuenta VitaSync y PIN; cerrar sesión y volver a entrar.
- Pestaña **Dispositivo**: vincular el reloj (muestra su clave una sola vez).
- **Contactos**: agregar y borrar.
- **Resumen → Mis metas**: cambiar la meta de pasos.
- **Chat**: elegir rol; adjuntar un archivo (PNG, JPG, PDF o TXT de hasta 300 KB) con el clip.
- **Sin conexión**: apaga el Wi-Fi del celular y manda un mensaje: debe quedar «Pendiente de enviar» y salir solo al
  volver la red.

## Si algo falla

- *«No se pudo conectar al servidor»*: la IP está mal, el firewall bloquea el 8081, o PC y celular no están en la
  misma red. Prueba abrir `http://<IP-DE-LA-PC>:8081/api/firmware/ultima` en el navegador del celular.
- *«Correo o contraseña incorrectos» al crear cuenta*: en el camino A, el emulador de Authentication no está abierto
  a la red (paso 1); en el B, revisa la clave de API web.
- *«Tu sesión venció»*: el token dura una hora; vuelve a iniciar sesión.
- *El rol de médico o administrador no cambia*: el rol llega con el token; cierra sesión y vuelve a entrar.
- El **iPhone** no está cubierto: instalar en iOS requiere compilar desde una Mac.
