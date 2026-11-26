/* Service worker de VitaSync (rúbrica C3: funcionamiento sin conexión).
 *
 * El service worker que genera Flutter 3.35 ya no guarda la app para usarla sin red, así que se reemplaza por este:
 *  · INSTALACIÓN: guarda el «cascarón» (página, motor de Flutter, manifiesto, íconos).
 *  · ARCHIVOS ESTÁTICOS de la propia app (canvaskit, assets, fuentes locales) y las tipografías de Google: primero el caché y, si no
 *    están, la red; lo que se descarga se guarda para la próxima vez. Así, después de UNA visita completa en línea, la app abre sin red.
 *  · NAVEGACIÓN: red primero (para recibir versiones nuevas) y, si no hay red, la página guardada.
 *  · DATOS DE SALUD (la API del backend y Firebase): NUNCA se guardan aquí ni se interceptan. Son siempre del servidor; sin red la app
 *    muestra su propia caché local marcada como «no confirmada» y deja los mensajes del chat como pendientes.
 */
const VERSION = 'vitasync-v2';
const CACHE = `vitasync-cascaron-${VERSION}`;
const CASCARON = ['./', 'index.html', 'flutter_bootstrap.js', 'flutter.js', 'main.dart.js', 'manifest.json', 'favicon.png',
  'icons/Icon-192.png', 'icons/Icon-512.png', 'icons/Icon-maskable-192.png', 'icons/Icon-maskable-512.png'];
const ORIGENES_EXTERNOS_PERMITIDOS = ['fonts.gstatic.com', 'fonts.googleapis.com'];

self.addEventListener('install', (evento) => {
  evento.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    // Uno por uno: si falta algún archivo opcional no se cae toda la instalación.
    await Promise.all(CASCARON.map((ruta) => cache.add(new Request(ruta, { cache: 'reload' })).catch(() => {})));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', (evento) => {
  evento.waitUntil((async () => {
    for (const nombre of await caches.keys()) {
      if (nombre.startsWith('vitasync-cascaron-') && nombre !== CACHE) await caches.delete(nombre);
    }
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (evento) => {
  const peticion = evento.request;
  if (peticion.method !== 'GET') return;
  const url = new URL(peticion.url);
  const mismoOrigen = url.origin === self.location.origin;
  if (!mismoOrigen && !ORIGENES_EXTERNOS_PERMITIDOS.includes(url.hostname)) return; // backend, Firebase, etc.: sin tocar
  if (mismoOrigen && !url.pathname.startsWith(new URL(self.registration.scope).pathname)) return; // solo lo que cuelga de /movil/

  if (peticion.mode === 'navigate') {
    evento.respondWith((async () => {
      try {
        const respuesta = await fetch(peticion);
        const cache = await caches.open(CACHE);
        cache.put('index.html', respuesta.clone());
        return respuesta;
      } catch {
        return (await caches.match('index.html')) || (await caches.match('./')) || Response.error();
      }
    })());
    return;
  }

  evento.respondWith((async () => {
    const guardado = await caches.match(peticion, { ignoreSearch: true });
    if (guardado) return guardado;
    try {
      const respuesta = await fetch(peticion);
      if (respuesta && (respuesta.ok || respuesta.type === 'opaque')) {
        const cache = await caches.open(CACHE);
        cache.put(peticion, respuesta.clone());
      }
      return respuesta;
    } catch {
      return Response.error();
    }
  })());
});
