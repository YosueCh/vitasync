# vitasync_wear — app del reloj (Wear OS)

App Flutter para relojes **Wear OS 3 o superior** (Android 11+). Lee los sensores del reloj, pide los permisos con el diálogo del sistema y
manda las lecturas al backend de VitaSync por HTTP (Wi-Fi). Funciona igual en el emulador `Wear_OS_Large_Round` de Android Studio y en un reloj físico.

## Qué mide
| Dato | Origen |
|---|---|
| Ritmo cardíaco | **Sensor real** (necesita permiso; si no hay sensor o se rechaza, valor simulado) |
| Pasos del día | **Contador de pasos real** (permiso de actividad física); si el reloj no lo tiene, simulado |
| Batería | **Real** (sin permiso) |
| Calorías | Estimadas de los pasos (≈0,04 kcal por paso); simuladas si los pasos lo son |
| Sueño | No se mide aquí: se conserva el último valor del servidor (simulado) |

La pantalla principal dice siempre de dónde salen los números («Medido: … Simulado: …»).

## Configurar el servidor y la clave (icono ⚙ de la pantalla principal)
- **IP del servidor**: la IP de la PC en la misma red Wi-Fi (p. ej. `192.168.1.50`). En el emulador: `10.0.2.2` (valor por omisión).
- **Puerto**: 8081.
- **Clave de dispositivo**: la que entrega la app del celular al vincular el reloj. Con la seguridad encendida, sin ella el backend responde 401.
- Alternativa al compilar: `--dart-define=API_HOST=192.168.1.50 --dart-define=CLAVE_DISPOSITIVO=...`.
- La app usa HTTP sin cifrar (`usesCleartextTraffic`) **solo para la red local de pruebas**; en producción hay que poner HTTPS y quitarlo.

## Probar en el emulador
1. Device Manager → `Wear_OS_Large_Round` → arrancar.
2. `flutter run -t lib/diagnostico_sensores.dart` muestra qué sensores hay, pide permisos y lee una lectura. (Con `--dart-define=CUENTA_ID=<id>` agrega «Enviar al servidor».)
3. Sensores virtuales: `adb emu sensor set heart-rate 80` (el sensor de ritmo es «al cambiar»: el valor debe cambiar mientras se mide). El emulador no trae contador de pasos.
4. App completa: `flutter run` (PIN del reloj → elegir cuenta → pantalla principal).

## Instalar en un reloj físico
1. Empareja el reloj con tu teléfono Android (app Wear OS) y conéctalo a tu Wi-Fi.
2. En el reloj: Ajustes → Acerca de → toca 7 veces «Número de compilación» → Ajustes → Opciones de desarrollador → activa **Depuración ADB** y **Depurar por Wi-Fi**.
3. En la PC: `adb pair <ip>:<puerto-de-emparejamiento>` (con el código del reloj) y luego `adb connect <ip>:<puerto>`.
4. `flutter devices` debe listar el reloj → `flutter run -d <id>` (o `flutter build apk` + `adb install`).
5. En el reloj: ⚙ → IP de la PC, puerto y clave → «Permitir sensores» → «Sincronizar».
6. Firewall de Windows abierto para el puerto 8081 (ver `PROBAR-EN-CELULAR.md`).

## Pruebas
`flutter test` (22 pruebas: lectura con sensores reales/simulados, permisos, canal nativo, cabecera de la clave, servidor configurable, pantallas).
