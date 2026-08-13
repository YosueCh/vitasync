# flutter-stats-widget

Micro-frontend en Flutter Web: renderiza `StatsWidget` (métricas de
productividad con anillo de progreso) y se incrusta por `<iframe>` en el
dashboard de `vitasync-frontend` (Angular). Ver Prácticas 7-8.

Vive **dentro** de `vitasync-frontend/` a propósito: es un proyecto
Flutter aparte (pubspec propio, se compila por separado), pero
conceptualmente es parte del sitio web, no una app independiente — por
eso no está al mismo nivel que `vitasync-backend/` o `vitasync_wear/`.

## Probarlo de forma aislada

```bash
flutter pub get
flutter run -d chrome --web-port 5000
```

Abre `http://localhost:5000/?pending=5&progress=3&completed=12` para ver el
widget con datos de ejemplo.

## Compilarlo e incrustarlo en el dashboard Angular

```bash
flutter build web --release --base-href /flutter_stats/
```

El `--base-href /flutter_stats/` es obligatorio: como este widget se sirve
desde una subcarpeta (`/flutter_stats/...`) y no desde la raíz del sitio,
sin ese flag el `index.html` generado busca `main.dart.js` y los assets en
`/` en vez de `/flutter_stats/`, y el iframe queda en blanco (404
silencioso en la consola del navegador).

Copia el contenido de `build/web/` a la carpeta de assets estáticos del
frontend Angular, en `flutter_stats/` (ahora un solo nivel arriba, ya
que este proyecto vive dentro de `vitasync-frontend/`):

```bash
# Windows (PowerShell), desde vitasync-frontend/flutter-stats-widget/
Copy-Item -Recurse -Force build\web\* ..\public\flutter_stats\
```

Con `ng serve` corriendo, el widget queda disponible en
`http://localhost:4200/flutter_stats/index.html` y es exactamente lo que
consume el `<iframe>` de la página `/dashboard` en Angular
(`src/app/pages/dashboard`).

## Parámetros que acepta

| Query param | Significado |
|---|---|
| `pending` | Número de tareas pendientes |
| `progress` | Número de tareas en progreso |
| `completed` | Número de tareas completadas |

Ejemplo: `flutter_stats/index.html?pending=5&progress=3&completed=12`.
