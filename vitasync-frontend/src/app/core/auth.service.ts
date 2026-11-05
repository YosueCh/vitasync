import { Injectable, inject, signal } from '@angular/core';
import { HttpClient, HttpErrorResponse } from '@angular/common/http';
import { Observable, catchError, map, tap, throwError } from 'rxjs';

import { AUTH_CONFIG } from './auth.config';

/** Persona con la sesión abierta (Firebase Authentication con correo y contraseña). */
export interface Sesion {
  correo: string;
  uid: string;
  /** ID token que viaja al backend en «Authorization: Bearer». */
  token: string;
  /** Instante (ms) en que el token deja de servir. */
  vence: number;
}

interface RespuestaFirebase {
  localId: string;
  email: string;
  idToken: string;
  expiresIn: string;
}

const CLAVE_SESION = 'vitasync_sesion';

/**
 * Inicio de sesión del sitio web (Práctica 10). Usa la API REST de Firebase Authentication, igual que la app móvil,
 * así que no hace falta ninguna librería nueva. La sesión se guarda en sessionStorage (se borra al cerrar la
 * pestaña, no queda en el disco). El backend es quien decide qué puede ver cada persona: aquí solo se obtiene y se
 * manda el token.
 */
@Injectable({ providedIn: 'root' })
export class AuthService {
  private readonly http = inject(HttpClient);

  readonly sesion = signal<Sesion | null>(this.leer());

  iniciarSesion(correo: string, clave: string): Observable<Sesion> {
    return this.pedir('accounts:signInWithPassword', correo, clave);
  }

  registrarse(correo: string, clave: string): Observable<Sesion> {
    return this.pedir('accounts:signUp', correo, clave);
  }

  cerrarSesion(): void {
    this.sesion.set(null);
    try {
      sessionStorage.removeItem(CLAVE_SESION);
    } catch {
      // sin almacenamiento: la sesión solo vivía en memoria
    }
  }

  /** El token vigente, o null si no hay sesión o ya venció (en ese caso la cierra). */
  token(): string | null {
    const s = this.sesion();
    if (!s) return null;
    if (Date.now() >= s.vence) {
      this.cerrarSesion();
      return null;
    }
    return s.token;
  }

  private pedir(operacion: string, correo: string, clave: string): Observable<Sesion> {
    const url = `${AUTH_CONFIG.base}/v1/${operacion}?key=${encodeURIComponent(AUTH_CONFIG.apiKey)}`;
    return this.http.post<RespuestaFirebase>(url, { email: correo, password: clave, returnSecureToken: true }).pipe(
      map((r) => ({
        correo: r.email,
        uid: r.localId,
        token: r.idToken,
        // Se resta un minuto para no mandar un token que venza en el camino.
        vence: Date.now() + Number(r.expiresIn) * 1000 - 60_000,
      })),
      tap((s) => this.guardar(s)),
      catchError((e: HttpErrorResponse) => throwError(() => new Error(this.mensaje(e)))),
    );
  }

  private guardar(s: Sesion): void {
    this.sesion.set(s);
    try {
      sessionStorage.setItem(CLAVE_SESION, JSON.stringify(s));
    } catch {
      // sin almacenamiento: la sesión vive solo en memoria
    }
  }

  private leer(): Sesion | null {
    try {
      const crudo = sessionStorage.getItem(CLAVE_SESION);
      if (!crudo) return null;
      const s = JSON.parse(crudo) as Sesion;
      return s && typeof s.token === 'string' && Date.now() < s.vence ? s : null;
    } catch {
      return null;
    }
  }

  /** Mensaje para la persona; no revela si el correo existe (igual que la app móvil). */
  private mensaje(e: HttpErrorResponse): string {
    if (e.status === 0) return 'No se pudo conectar con el servicio de acceso.';
    const codigo: string = e.error?.error?.message ?? '';
    if (codigo.startsWith('EMAIL_EXISTS')) return 'Ya existe una cuenta con ese correo.';
    if (codigo.startsWith('WEAK_PASSWORD')) return 'La contraseña debe tener al menos 6 caracteres.';
    if (codigo.startsWith('INVALID_EMAIL')) return 'El correo no es válido.';
    if (codigo.startsWith('TOO_MANY_ATTEMPTS')) return 'Demasiados intentos. Espera unos minutos.';
    return 'Correo o contraseña incorrectos.';
  }
}
