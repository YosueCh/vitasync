import { Routes } from '@angular/router';
import { Inicio } from './pages/inicio/inicio';
import { Nosotros } from './pages/nosotros/nosotros';
import { Contacto } from './pages/contacto/contacto';
import { Faq } from './pages/faq/faq';
import { Dashboard } from './pages/dashboard/dashboard';
import { ConfiguracionDispositivo } from './pages/configuracion-dispositivo/configuracion-dispositivo';
import { GestionUsuarios } from './pages/gestion-usuarios/gestion-usuarios';
import { SmartTv } from './pages/smart-tv/smart-tv';
import { SmartTvPantalla } from './pages/smart-tv-pantalla/smart-tv-pantalla';
import { Acceso } from './pages/acceso/acceso';
import { authGuard } from './core/auth.interceptor';

/**
 * Rutas del sitio (elemento #3 "Páginas internas" y #13 "Páginas
 * complementarias" del checklist): cada página vive en su propio
 * componente y se navega sin recargar el navegador (SPA).
 */
export const routes: Routes = [
  { path: '', component: Inicio, title: 'VitaSync — Tu salud, sincronizada' },
  { path: 'nosotros', component: Nosotros, title: 'VitaSync — Nosotros' },
  { path: 'acceso', component: Acceso, title: 'VitaSync — Iniciar sesión' },
  // Las páginas con datos de la persona exigen sesión (Práctica 10); el backend vuelve a comprobarlo.
  { path: 'dashboard', component: Dashboard, title: 'VitaSync — Dashboard', canActivate: [authGuard] },
  { path: 'dispositivo', component: ConfiguracionDispositivo, title: 'VitaSync — Configuración de Dispositivo', canActivate: [authGuard] },
  { path: 'usuarios', component: GestionUsuarios, title: 'VitaSync — Gestión de Usuarios', canActivate: [authGuard] },
  { path: 'smart-tv', component: SmartTv, title: 'VitaSync — Enlazar Smart TV' },
  { path: 'smart-tv-pantalla', component: SmartTvPantalla, title: 'VitaSync — Pantalla de TV' },
  { path: 'contacto', component: Contacto, title: 'VitaSync — Contacto' },
  { path: 'faq', component: Faq, title: 'VitaSync — Preguntas frecuentes' },
  { path: '**', redirectTo: '' },
];
