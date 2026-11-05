import { ApplicationConfig, provideBrowserGlobalErrorListeners } from '@angular/core';
import { provideRouter, withInMemoryScrolling } from '@angular/router';
import { provideHttpClient, withInterceptors } from '@angular/common/http';

import { routes } from './app.routes';
import { authInterceptor } from './core/auth.interceptor';

export const appConfig: ApplicationConfig = {
  providers: [
    provideBrowserGlobalErrorListeners(),
    // El interceptor manda el token de la persona al backend y atiende el 401 (sesión vencida).
    provideHttpClient(withInterceptors([authInterceptor])),
    // anchorScrolling: permite que los enlaces con [fragment] (p.ej.
    // "Características", "Estadísticas" del navbar) desplacen la
    // vista hasta la sección correspondiente dentro de Inicio.
    provideRouter(
      routes,
      withInMemoryScrolling({ anchorScrolling: 'enabled', scrollPositionRestoration: 'enabled' })
    ),
  ],
};
