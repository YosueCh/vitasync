import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { BehaviorSubject, Observable, of } from 'rxjs';
import { delay, tap } from 'rxjs/operators';
import {
  Dispositivo,
  EstadoConexion,
  EstadoRespuesta,
  Metas,
  Metricas,
} from '../models/smartwatch.model';
import { UsuarioActivoService } from './usuario-activo.service';
import { AUTH_CONFIG } from '../core/auth.config';

/**
 * Servicio que enlaza la pantalla "Configuración de Dispositivo" con el
 * smartwatch (Práctica 5-6). Sigue el MISMO patrón dual que
 * `search.service.ts`: una bandera `SIMULAR` decide si se responde con
 * datos simulados en memoria (para probar la pantalla sin backend) o
 * llamando a la API real `vitasync-backend` (`/api/smartwatch/*`,
 * respaldada por Cloud Firestore — ver FirebaseConfig en el backend).
 *
 * IMPORTANTE: cambia `SIMULAR` a `false` una vez que tengas el backend
 * corriendo con `serviceAccountKey.json` configurado.
 */
@Injectable({ providedIn: 'root' })
export class SmartwatchService {
  private readonly SIMULAR = false;
  private readonly API = `${AUTH_CONFIG.api}/smartwatch`;

  private estado$ = new BehaviorSubject<EstadoConexion>('DESCONECTADO');
  private dispositivoActual: Dispositivo | null = null;

  constructor(
    private http: HttpClient,
    private usuarioActivo: UsuarioActivoService,
  ) {}

  get estadoStream(): Observable<EstadoConexion> {
    return this.estado$.asObservable();
  }

  /** ID del usuario activo, para que cada cuenta tenga su propio dispositivo/métricas. */
  private get usuarioId(): string {
    const u = this.usuarioActivo.usuarioActivo();
    if (!u) throw new Error('No hay un usuario activo seleccionado todavía.');
    return u.id;
  }

  /** Botón "Conectar Smartwatch". */
  conectarDispositivo(): Observable<EstadoRespuesta> {
    if (!this.SIMULAR) {
      return this.http
        .post<EstadoRespuesta>(`${this.API}/connect?usuarioId=${this.usuarioId}`, {})
        .pipe(tap((r) => this.estado$.next(r.estado)));
    }

    const dispositivo: Dispositivo = {
      id: 'VS-WATCH-001',
      nombre: 'VitaSync Watch R1',
      modelo: 'Wearable redondo genérico',
      bateria: 87,
      firmware: 'v2.3.1',
      ultimaSync: null,
    };
    this.dispositivoActual = dispositivo;
    return of<EstadoRespuesta>({
      estado: 'CONECTADO',
      dispositivo,
      mensaje: 'Dispositivo conectado correctamente',
    }).pipe(
      delay(1200), // simula el handshake BLE
      tap((r) => this.estado$.next(r.estado)),
    );
  }

  /** Botón "Sincronizar". */
  sincronizarDatos(): Observable<Metas> {
    if (!this.SIMULAR) {
      return this.http
        .post<Metas>(`${this.API}/sync?usuarioId=${this.usuarioId}`, {})
        .pipe(tap(() => this.estado$.next('CONECTADO')));
    }

    this.estado$.next('SINCRONIZANDO');
    const metas: Metas = {
      metaPasos: 10000,
      metaCalorias: 600,
      metaSueñoHoras: 8.0,
      notificaciones: ['¡Vas por buen camino!', 'Recuerda hidratarte'],
      recordatorios: ['Mover a las 18:00', 'Dormir antes de las 23:30'],
    };
    if (this.dispositivoActual) {
      this.dispositivoActual.ultimaSync = new Date().toISOString();
      this.dispositivoActual.bateria = this.rand(40, 95);
    }
    return of(metas).pipe(
      delay(1500),
      tap(() => this.estado$.next('CONECTADO')),
    );
  }

  /** Consulta el estado actual sin disparar acciones. */
  obtenerEstado(): Observable<EstadoRespuesta> {
    if (!this.SIMULAR) {
      return this.http.get<EstadoRespuesta>(`${this.API}/status?usuarioId=${this.usuarioId}`);
    }
    return of<EstadoRespuesta>({
      estado: this.dispositivoActual ? 'CONECTADO' : 'DESCONECTADO',
      dispositivo: this.dispositivoActual,
      mensaje: this.dispositivoActual ? 'Dispositivo activo' : 'Sin dispositivo conectado',
    }).pipe(delay(250));
  }

  /** Últimas métricas capturadas (para la tarjeta de métricas). */
  obtenerMetricas(): Observable<Metricas> {
    if (!this.SIMULAR) {
      return this.http.get<Metricas>(`${this.API}/metrics?usuarioId=${this.usuarioId}`);
    }
    const metricas: Metricas = {
      pasos: this.rand(4000, 12000),
      calorias: this.rand(250, 800),
      sueñoHoras: +(this.rand(50, 90) / 10).toFixed(1),
      frecuenciaCardiaca: this.rand(62, 95),
      bateria: this.dispositivoActual?.bateria ?? this.rand(40, 95),
      timestamp: new Date().toISOString(),
    };
    return of(metricas).pipe(delay(250));
  }

  private rand(min: number, max: number): number {
    return Math.floor(Math.random() * (max - min + 1)) + min;
  }
}
