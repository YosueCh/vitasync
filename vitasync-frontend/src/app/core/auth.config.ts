/**
 * Dónde está Firebase Authentication y el backend (Práctica 10 en el sitio web). Por omisión apunta al EMULADOR local
 * de Authentication (puerto 9099) y al backend en el puerto 8081, igual que la app móvil.
 *
 * Se pueden cambiar SIN recompilar definiendo antes de cargar la app (por ejemplo en un <script> de index.html):
 *   window.VITASYNC_API       = 'https://mi-backend.example.com/api'
 *   window.VITASYNC_AUTH_BASE = 'https://identitytoolkit.googleapis.com'
 *   window.VITASYNC_API_KEY   = '<Clave de API web del proyecto de Firebase>'   (no es secreta)
 */
interface Ajustes {
  VITASYNC_API?: string;
  VITASYNC_AUTH_BASE?: string;
  VITASYNC_API_KEY?: string;
}
const w = globalThis as unknown as Ajustes;

export const AUTH_CONFIG = {
  base: w.VITASYNC_AUTH_BASE ?? 'http://localhost:9099/identitytoolkit.googleapis.com',
  apiKey: w.VITASYNC_API_KEY ?? 'clave-local',
  /** URL del backend. Las peticiones a ella llevan el token de la persona (las demás, no). */
  api: w.VITASYNC_API ?? 'http://localhost:8081/api',
};
