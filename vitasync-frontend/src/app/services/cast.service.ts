import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable, of } from 'rxjs';
import { delay } from 'rxjs/operators';

import { CastSession } from '../models/cast.model';

const LOCALSTORAGE_KEY = 'vitasync_cast_sessions';
const VIGENCIA_MIN = 5;

/**
 * Enlace con Smart TV (Práctica 9-10). Sigue el mismo patrón dual que el
 * resto de servicios (`SIMULAR` decide entre datos locales o la API real
 * `/api/cast`), con una diferencia importante: el punto de esta feature
 * es precisamente coordinar DOS pestañas/dispositivos distintos (el
 * "emisor" y la "TV"), así que el modo simulado usa `localStorage` en
 * vez de un simple campo en memoria — de lo contrario, abrir la pantalla
 * de TV en otra pestaña vería un servicio completamente vacío, porque
 * cada pestaña arranca su propia instancia de Angular.
 *
 * IMPORTANTE: cambia `SIMULAR` a `false` una vez que tengas el backend
 * corriendo con `serviceAccountKey.json` configurado.
 */
@Injectable({ providedIn: 'root' })
export class CastService {
  private readonly SIMULAR = false;
  private readonly API = 'http://localhost:8081/api/cast';

  constructor(private http: HttpClient) {}

  generar(): Observable<CastSession> {
    if (!this.SIMULAR) {
      return this.http.post<CastSession>(`${this.API}/generar`, {});
    }
    const codigo = Math.floor(Math.random() * 1_000_000).toString().padStart(6, '0');
    const ahora = new Date();
    const sesion: CastSession = {
      codigo,
      estado: 'ESPERANDO_TV',
      creadoEn: ahora.toISOString(),
      expiraEn: new Date(ahora.getTime() + VIGENCIA_MIN * 60_000).toISOString(),
      emparejadoEn: null,
    };
    this.guardarLocal(sesion);
    return of(sesion).pipe(delay(200));
  }

  emparejar(codigo: string): Observable<CastSession> {
    if (!this.SIMULAR) {
      return this.http.post<CastSession>(`${this.API}/emparejar/${codigo}`, {});
    }
    const sesion = this.leerLocal(codigo);
    if (!sesion) return this.error('No existe una sesión de enlace con ese código.');
    if (this.expirada(sesion)) return this.error('El código expiró. Genera uno nuevo desde el dashboard.');
    sesion.estado = 'EMPAREJADO';
    sesion.emparejadoEn = new Date().toISOString();
    this.guardarLocal(sesion);
    return of(sesion).pipe(delay(200));
  }

  estado(codigo: string): Observable<CastSession> {
    if (!this.SIMULAR) {
      return this.http.get<CastSession>(`${this.API}/estado/${codigo}`);
    }
    const sesion = this.leerLocal(codigo);
    if (!sesion) return this.error('No existe una sesión de enlace con ese código.');
    if (this.expirada(sesion) && sesion.estado !== 'EMPAREJADO') {
      sesion.estado = 'EXPIRADO';
      this.guardarLocal(sesion);
    }
    return of(sesion).pipe(delay(150));
  }

  private expirada(s: CastSession): boolean {
    return new Date(s.expiraEn).getTime() < Date.now();
  }

  private error(mensaje: string): Observable<never> {
    return new Observable((sub) => sub.error({ error: { error: mensaje } }));
  }

  private leerTodas(): Record<string, CastSession> {
    try {
      return JSON.parse(localStorage.getItem(LOCALSTORAGE_KEY) ?? '{}');
    } catch {
      return {};
    }
  }

  private leerLocal(codigo: string): CastSession | null {
    return this.leerTodas()[codigo] ?? null;
  }

  private guardarLocal(sesion: CastSession): void {
    const todas = this.leerTodas();
    todas[sesion.codigo] = sesion;
    localStorage.setItem(LOCALSTORAGE_KEY, JSON.stringify(todas));
  }
}
