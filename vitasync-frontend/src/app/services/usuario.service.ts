import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable, of } from 'rxjs';
import { delay } from 'rxjs/operators';

import { CrearUsuario, LoginResultado, Usuario } from '../models/usuario.model';

/**
 * Administración de cuentas de usuario (Práctica 13, reinterpretada como
 * feature real de VitaSync en vez de comandos de Windows). Sigue el
 * mismo patrón dual que `smartwatch.service.ts` y `search.service.ts`:
 * `SIMULAR` decide entre datos en memoria (para probar sin backend) o
 * la API real `/api/usuarios` (Spring Boot + Firestore).
 *
 * IMPORTANTE: cambia `SIMULAR` a `false` una vez que tengas el backend
 * corriendo con `serviceAccountKey.json` configurado (ver README de
 * vitasync-backend).
 */
@Injectable({ providedIn: 'root' })
export class UsuarioService {
  private readonly SIMULAR = false;
  private readonly API = 'http://localhost:8081/api/usuarios';

  /** Semilla igual a la que usa el backend (UsuarioSeeder), para que la demo sin backend luzca igual. */
  private usuarios: Usuario[] = [
    this.nuevo('Alumno Uno', 'alumno1', ['alumnos']),
    this.nuevo('Alumno Dos', 'alumno2', ['alumnos']),
    this.nuevo('Invitado', 'invitado', ['invitados']),
  ];

  constructor(private http: HttpClient) {}

  listar(): Observable<Usuario[]> {
    if (!this.SIMULAR) {
      return this.http.get<Usuario[]>(this.API);
    }
    return of([...this.usuarios]).pipe(delay(200));
  }

  crear(datos: CrearUsuario): Observable<Usuario> {
    if (!this.SIMULAR) {
      return this.http.post<Usuario>(this.API, datos);
    }
    const u = this.nuevo(datos.nombreCompleto, datos.username, datos.grupos);
    this.usuarios = [...this.usuarios, u];
    return of(u).pipe(delay(200));
  }

  habilitar(id: string): Observable<Usuario> {
    if (!this.SIMULAR) {
      return this.http.patch<Usuario>(`${this.API}/${id}/habilitar`, {});
    }
    return this.cambiarEstado(id, true);
  }

  deshabilitar(id: string): Observable<Usuario> {
    if (!this.SIMULAR) {
      return this.http.patch<Usuario>(`${this.API}/${id}/deshabilitar`, {});
    }
    return this.cambiarEstado(id, false);
  }

  eliminar(id: string): Observable<void> {
    if (!this.SIMULAR) {
      return this.http.delete<void>(`${this.API}/${id}`);
    }
    this.usuarios = this.usuarios.filter((u) => u.id !== id);
    return of(undefined).pipe(delay(150));
  }

  simularLogin(id: string): Observable<LoginResultado> {
    if (!this.SIMULAR) {
      return this.http.post<LoginResultado>(`${this.API}/${id}/login`, {});
    }
    const u = this.usuarios.find((x) => x.id === id);
    if (!u) return of({ exito: false, mensaje: 'Usuario no encontrado.' });
    if (!u.habilitado) {
      return of({
        exito: false,
        mensaje: 'La cuenta está deshabilitada. No es posible iniciar sesión.',
      }).pipe(delay(200));
    }
    u.ultimoInicioSesion = new Date().toISOString();
    const aviso = u.requiereCambioPassword ? ' (se requiere cambio de contraseña)' : '';
    return of({ exito: true, mensaje: `Inicio de sesión correcto${aviso}.` }).pipe(delay(200));
  }

  private cambiarEstado(id: string, habilitado: boolean): Observable<Usuario> {
    const u = this.usuarios.find((x) => x.id === id);
    if (u) u.habilitado = habilitado;
    return of(u as Usuario).pipe(delay(150));
  }

  private nuevo(nombreCompleto: string, username: string, grupos: string[]): Usuario {
    return {
      id: crypto.randomUUID(),
      nombreCompleto,
      username,
      grupos,
      habilitado: true,
      requiereCambioPassword: true,
      fechaCreacion: new Date().toISOString(),
      ultimoInicioSesion: null,
    };
  }
}
