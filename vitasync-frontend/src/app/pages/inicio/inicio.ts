import { AfterViewInit, Component, ElementRef, ViewChild } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { RouterLink } from '@angular/router';

/**
 * Página de Inicio. Contiene el hero (con el "bisel" animado que
 * imita la esfera del smartwatch VitaSync), el bloque de
 * características (#caracteristicas) y el de estadísticas
 * (#estadisticas, elemento #14 "Herramientas para estadísticas").
 */
@Component({
  selector: 'app-inicio',
  imports: [RouterLink, DecimalPipe],
  templateUrl: './inicio.html',
  styleUrl: './inicio.css',
})
export class Inicio implements AfterViewInit {
  @ViewChild('pasosEl') pasosEl!: ElementRef<HTMLElement>;

  /** Meta usada para dibujar el arco del anillo de progreso. */
  readonly metaPasos = 10000;
  readonly pasosActuales = 8450;

  ngAfterViewInit(): void {
    const prefiereMenosMovimiento =
      window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    if (prefiereMenosMovimiento) {
      this.pasosEl.nativeElement.textContent = this.pasosActuales.toLocaleString();
      return;
    }
    this.animarConteo(this.pasosEl.nativeElement, this.pasosActuales, 1100);
  }

  /** Animación simple de conteo ascendente (momento de carga orquestado). */
  private animarConteo(el: HTMLElement, valorFinal: number, duracionMs: number): void {
    const inicio = performance.now();
    const paso = (ahora: number) => {
      const progreso = Math.min((ahora - inicio) / duracionMs, 1);
      const valorActual = Math.round(progreso * valorFinal);
      el.textContent = valorActual.toLocaleString();
      if (progreso < 1) requestAnimationFrame(paso);
    };
    requestAnimationFrame(paso);
  }
}
