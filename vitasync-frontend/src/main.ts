import { bootstrapApplication } from '@angular/platform-browser';
import { appConfig } from './app/app.config';
import { App } from './app/app';
import { CLAVE_ESCRITORIO, RUTA_VISTA_MOVIL, debeIrALaVistaMovil, pideEscritorio } from './app/core/vista-movil';

// Propuesta (Parcial 3): los teléfonos reciben la vista móvil (PWA en /movil/); «?escritorio=1» muestra el sitio completo.
try {
  if (pideEscritorio(location.search)) sessionStorage.setItem(CLAVE_ESCRITORIO, '1');
} catch {
  /* sin almacenamiento de sesión (modo privado estricto): solo vale para esta carga */
}
const irAMovil = debeIrALaVistaMovil({
  agente: navigator.userAgent,
  ruta: location.pathname,
  consulta: location.search,
  escritorioGuardado: (() => {
    try {
      return sessionStorage.getItem(CLAVE_ESCRITORIO) === '1';
    } catch {
      return false;
    }
  })(),
});

if (irAMovil) {
  location.replace(RUTA_VISTA_MOVIL + location.hash);
} else {
  bootstrapApplication(App, appConfig).catch((err) => console.error(err));
}
