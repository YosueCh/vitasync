# vitasync-firmware-sim

Firmware simulado del reloj VitaSync. Es la integración de la **Práctica 1**
(firmware con `setup()`/`loop()`, botón, LED y monitor serial) y de la idea de
la **Práctica 2** (sensor de presencia) sin necesitar un ESP32: el "hardware"
se simula en la terminal y el firmware habla con el backend real.

## Correspondencia con la práctica

| Práctica 1 / 2 (ESP32) | Aquí |
|---|---|
| `setup()` se ejecuta una vez | `Firmware.setup()`: se vincula con el servidor |
| `loop()` se repite | `Firmware.loop()`, una vuelta por segundo |
| `digitalRead(BOTON)` | `Hardware.leerBoton()` (tecla `s`) |
| Sensor infrarrojo (P2) | `Hardware.leerRelojPuesto()` (tecla `p`: reloj puesto / retirado) |
| `digitalWrite(LED, ...)` | `Hardware.escribirLed()`: 🟢 conectado, 🟡 sincronizando, 🔴 error, ⚫ apagado |
| `Serial.println(...)` | `Hardware.imprimir()` |
| Bluetooth hacia el teléfono | HTTP al backend; la vista móvil lo lee por sondeo |

## Qué hace

- Al arrancar se vincula con el backend (o recupera su versión de firmware si ya estaba vinculado).
- Con el reloj puesto, el botón (o `--auto`) envía una lectura de métricas a `POST /api/smartwatch/sync`.
- Cada lectura enviada se guarda en el historial del backend (Firestore, `devices/{usuarioId}/historial`):
  es lo que la vista móvil muestra al tocar una card del Resumen. Para tener historial hay que dejar
  correr el simulador un rato (p. ej. `--auto 3`).
- Sin reloj puesto no captura datos.
- Si el servidor se cae, pasa a LED rojo y reintenta solo.
- **Actualización de firmware (OTA)**: cuando alguien pulsa "Actualizar firmware" en la vista móvil, el
  firmware recoge la orden (`GET /api/firmware/orden`), simula la instalación con avance, se reinicia
  y reporta la versión nueva (`POST /api/firmware/aplicar`).

## Uso

```bash
dart pub get
dart run bin/vitasync_firmware.dart --usuario <id-de-la-cuenta> --auto 3
```

El `id` de la cuenta sale de `GET http://localhost:8081/api/usuarios`.

| Opción | Significado |
|---|---|
| `--usuario <id>` | (obligatoria) cuenta a la que pertenece el reloj |
| `--servidor <url>` | API base, por defecto `http://localhost:8081/api` |
| `--auto <seg>` | sincroniza sola cada `<seg>` segundos |
| `--sin-reloj` | arranca con el reloj retirado |

Teclas (en una terminal interactiva): `s` botón, `p` poner/retirar reloj, `q` apagar.
En terminales sin soporte de teclado (p. ej. Git Bash sin `winpty`) usar `--auto`.

## Pruebas

```bash
dart analyze
dart test
```

Las pruebas usan un hardware y un backend falsos: cubren el arranque, el botón
por flanco, el reloj retirado, la recuperación tras una caída del servidor y el
flujo completo de actualización.

## Con la seguridad del servidor activa (Práctica 10)

El firmware no es una persona: se identifica con la **clave del dispositivo**. La persona vincula el reloj
desde la app (pestaña Dispositivo → «Vincular reloj»), que muestra la clave una sola vez, y se arranca así:

```bash
dart run bin/vitasync_firmware.dart --usuario <id> --clave <clave> --auto 3
```

Con `--clave` el firmware no pregunta su estado ni se conecta solo (eso es de la persona dueña): solo envía
lecturas, consulta órdenes de actualización y reporta la versión. Si el servidor responde 401, la clave ya no
vale (se volvió a vincular el reloj) y hay que usar la nueva.
