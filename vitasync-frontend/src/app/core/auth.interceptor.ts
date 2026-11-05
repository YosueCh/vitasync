import { HttpErrorResponse, HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { catchError, throwError } from 'rxjs';

import { AUTH_CONFIG } from './auth.config';
import { AuthService } from './auth.service';

/**
 * Manda el token de la persona SOLO al backend de VitaSync (nunca a otros sitios) y, si el backend responde 401
 * (sesión vencida o inválida), cierra la sesión y lleva a la pantalla de acceso.
 */
export const authInterceptor: HttpInterceptorFn = (req, next) => {
  if (!req.url.startsWith(AUTH_CONFIG.api)) return next(req);
  const auth = inject(AuthService);
  const router = inject(Router);
  const token = auth.token();
  const conToken = token ? req.clone({ setHeaders: { Authorization: `Bearer ${token}` } }) : req;
  return next(conToken).pipe(
    catchError((e) => {
      if (e instanceof HttpErrorResponse && e.status === 401) {
        auth.cerrarSesion();
        void router.navigate(['/acceso'], { queryParams: { vencida: 1 } });
      }
      return throwError(() => e);
    }),
  );
};

/** Las páginas que usan datos de la persona (dashboard, dispositivo, usuarios) exigen sesión. */
export const authGuard: CanActivateFn = (_ruta, estado) => {
  const auth = inject(AuthService);
  if (auth.token()) return true;
  return inject(Router).createUrlTree(['/acceso'], { queryParams: { volver: estado.url } });
};
