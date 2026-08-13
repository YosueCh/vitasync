import { Component, OnDestroy, signal } from '@angular/core';
import { CommonModule } from '@angular/common';

import { CastService } from '../../services/cast.service';
import { CastSession, EstadoCast } from '../../models/cast.model';

/**
 * Pantalla "Enlazar Smart TV" (Práctica 9-10): genera un código de 6
 * dígitos, como Chromecast/AirPlay, y hace polling al backend hasta que
 * la TV (ver `smart-tv-pantalla`) lo confirma. El navegador nunca habla
 * directo con la TV — ambos pasan por `vitasync-backend`.
 *
 * El estado se guarda en `signal()` (no en propiedades planas): este
 * proyecto corre sin zone.js, así que una propiedad normal reasignada
 * dentro de un `setInterval` no dispara una nueva detección de cambios
 * — Angular nunca se entera del cambio aunque el dato sea correcto. Los
 * signals sí notifican a Angular sin importar de dónde venga la
 * escritura, que es precisamente el mecanismo pensado para apps sin
 * zone.js.
 */
@Component({
  selector: 'app-smart-tv',
  imports: [CommonModule],
  templateUrl: './smart-tv.html',
  styleUrl: './smart-tv.css',
})
export class SmartTv implements OnDestroy {
  sesion = signal<CastSession | null>(null);
  cargando = signal(false);
  error = signal<string | null>(null);

  private intervalo: ReturnType<typeof setInterval> | null = null;

  constructor(private cast: CastService) {}

  generarCodigo(): void {
    this.cargando.set(true);
    this.error.set(null);
    this.detenerPolling();
    this.cast.generar().subscribe({
      next: (s) => {
        this.sesion.set(s);
        this.cargando.set(false);
        this.iniciarPolling();
      },
      error: () => {
        this.cargando.set(false);
        this.error.set('No se pudo generar el código.');
      },
    });
  }

  claseEstado(estado: EstadoCast): string {
    const mapa: Record<EstadoCast, string> = {
      ESPERANDO_TV: 'estado--azul',
      EMPAREJADO: 'estado--verde',
      EXPIRADO: 'estado--rojo',
    };
    return mapa[estado];
  }

  private iniciarPolling(): void {
    this.intervalo = setInterval(() => {
      const actual = this.sesion();
      if (!actual) return;
      this.cast.estado(actual.codigo).subscribe({
        next: (s) => {
          this.sesion.set(s);
          if (s.estado !== 'ESPERANDO_TV') this.detenerPolling();
        },
        error: () => this.detenerPolling(),
      });
    }, 2000);
  }

  private detenerPolling(): void {
    if (this.intervalo) {
      clearInterval(this.intervalo);
      this.intervalo = null;
    }
  }

  ngOnDestroy(): void {
    this.detenerPolling();
  }
}
