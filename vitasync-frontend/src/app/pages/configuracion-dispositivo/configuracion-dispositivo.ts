import { Component, effect, NgZone, OnDestroy, signal } from '@angular/core';
import { CommonModule, DatePipe } from '@angular/common';
import Swal, { SweetAlertOptions } from 'sweetalert2';

import { SmartwatchService } from '../../services/smartwatch.service';
import { UsuarioActivoService } from '../../services/usuario-activo.service';
import { Dispositivo, EstadoConexion, Metas, Metricas } from '../../models/smartwatch.model';

interface TarjetaMetrica {
  etiqueta: string;
  valor: string;
  icono: string;
  color: string;
}

const INTERVALO_SONDEO_MS = 3000;

/**
 * Pantalla "Configuración de Dispositivo": empareja y sincroniza el
 * smartwatch VitaSync desde el navegador.
 *
 * El estado se guarda en signals (no en propiedades sueltas) porque este
 * proyecto corre sin zone.js: un cambio que llega desde fuera de un
 * evento de clic (aquí, el sondeo periódico al servidor) no dispara por
 * sí solo una nueva detección de cambios a menos que se lea a través de
 * un signal en la plantilla.
 */
@Component({
  selector: 'app-configuracion-dispositivo',
  imports: [CommonModule, DatePipe],
  templateUrl: './configuracion-dispositivo.html',
  styleUrl: './configuracion-dispositivo.css',
})
export class ConfiguracionDispositivo implements OnDestroy {
  estado = signal<EstadoConexion>('DESCONECTADO');
  mensajeEstado = signal('Sin dispositivo conectado');
  dispositivo = signal<Dispositivo | null>(null);
  metricas = signal<Metricas | null>(null);
  cargando = false;

  private sondeo: ReturnType<typeof setInterval> | null = null;

  constructor(
    private smartwatch: SmartwatchService,
    private zone: NgZone,
    public usuarioActivo: UsuarioActivoService,
  ) {
    // Cada vez que cambia el usuario activo (al elegir otro en el selector,
    // o en cuanto termina de cargar por primera vez), se limpia lo que
    // había en pantalla y se piden los datos de ESE usuario — para que no
    // se vea por un instante el dispositivo del usuario anterior.
    effect(() => {
      const u = this.usuarioActivo.usuarioActivo();
      if (!u) return;
      this.dispositivo.set(null);
      this.metricas.set(null);
      this.estado.set('DESCONECTADO');
      this.mensajeEstado.set('Sin dispositivo conectado');
      this.refrescarEstado();
    });

    // Sondeo periódico: si el reloj sincroniza por su cuenta mientras esta
    // pantalla está abierta, el dato nuevo aparece solo en unos segundos,
    // sin que haya que refrescar la página a mano.
    this.sondeo = setInterval(() => this.sondear(), INTERVALO_SONDEO_MS);
  }

  ngOnDestroy(): void {
    if (this.sondeo) clearInterval(this.sondeo);
  }

  private sondear(): void {
    if (this.cargando || this.estado() !== 'CONECTADO') return;
    this.smartwatch.obtenerMetricas().subscribe((m) => this.metricas.set(m));
  }

  cambiarUsuario(id: string): void {
    const u = this.usuarioActivo.usuarios().find((x) => x.id === id);
    if (u) this.usuarioActivo.seleccionar(u);
  }

  /**
   * SweetAlert2 anima/mueve el DOM fuera del conocimiento de Angular; si
   * se llama dentro de la zona, esa animación puede disparar un ciclo de
   * detección de cambios que pisa al que ya está en curso (NG0100:
   * ExpressionChangedAfterItHasBeenCheckedError). Ejecutarlo fuera de la
   * zona evita el conflicto sin perder la notificación visual.
   */
  private notificar(opciones: SweetAlertOptions): void {
    this.zone.runOutsideAngular(() => Swal.fire(opciones));
  }

  claseEstado(): string {
    const mapa: Record<EstadoConexion, string> = {
      DESCONECTADO: 'estado--gris',
      CONECTANDO: 'estado--azul',
      CONECTADO: 'estado--verde',
      SINCRONIZANDO: 'estado--azul',
      ERROR: 'estado--rojo',
    };
    return mapa[this.estado()];
  }

  tarjetasMetricas(m: Metricas): TarjetaMetrica[] {
    return [
      { etiqueta: 'Pasos', valor: m.pasos.toLocaleString(), icono: 'directions_walk', color: 'metrica--verde' },
      { etiqueta: 'Calorías', valor: `${m.calorias} kcal`, icono: 'local_fire_department', color: 'metrica--naranja' },
      { etiqueta: 'Sueño', valor: `${m.sueñoHoras} h`, icono: 'bedtime', color: 'metrica--indigo' },
      { etiqueta: 'Ritmo', valor: `${m.frecuenciaCardiaca} bpm`, icono: 'favorite', color: 'metrica--rojo' },
    ];
  }

  onConectar(): void {
    this.cargando = true;
    this.estado.set('CONECTANDO');
    this.mensajeEstado.set('Buscando dispositivo...');
    this.smartwatch.conectarDispositivo().subscribe({
      next: (resp) => {
        this.dispositivo.set(resp.dispositivo);
        this.estado.set('CONECTADO');
        this.mensajeEstado.set(resp.mensaje);
        this.cargando = false;
        this.notificar({
          icon: 'success',
          title: '¡Dispositivo conectado!',
          text: `${resp.dispositivo?.nombre ?? 'Smartwatch'} emparejado correctamente.`,
          timer: 2200,
          showConfirmButton: false,
        });
      },
      error: () => this.manejarError('No se pudo conectar el smartwatch.'),
    });
  }

  onSincronizar(): void {
    this.cargando = true;
    this.estado.set('SINCRONIZANDO');
    this.mensajeEstado.set('Sincronizando datos...');
    this.smartwatch.sincronizarDatos().subscribe({
      next: (metas: Metas) => {
        this.estado.set('CONECTADO');
        this.mensajeEstado.set('Datos actualizados');
        this.cargando = false;
        const d = this.dispositivo();
        if (d) this.dispositivo.set({ ...d, ultimaSync: new Date().toISOString() });
        this.smartwatch.obtenerMetricas().subscribe((m) => this.metricas.set(m));
        this.notificar({
          toast: true,
          position: 'top-end',
          icon: 'success',
          title: 'Sincronización completada',
          text: metas.notificaciones[0] ?? undefined,
          timer: 2200,
          showConfirmButton: false,
        });
      },
      error: () => this.manejarError('Falló la sincronización de datos.'),
    });
  }

  private refrescarEstado(): void {
    this.smartwatch.obtenerEstado().subscribe((resp) => {
      this.estado.set(resp.estado);
      this.mensajeEstado.set(resp.mensaje);
      this.dispositivo.set(resp.dispositivo);
      if (resp.dispositivo) {
        this.smartwatch.obtenerMetricas().subscribe((m) => this.metricas.set(m));
      }
    });
  }

  private manejarError(mensaje: string): void {
    this.estado.set('ERROR');
    this.mensajeEstado.set(mensaje);
    this.cargando = false;
    this.notificar({ icon: 'error', title: 'Error', text: mensaje });
  }
}
