import { Component } from '@angular/core';
import { DomSanitizer, SafeResourceUrl } from '@angular/platform-browser';
import { RouterLink } from '@angular/router';

/**
 * Dashboard de tareas híbrido (Práctica 7-8): el host Angular controla el
 * estado de las tareas y lo transfiere al micro-frontend Flutter Web
 * (flutter-stats-widget/StatsWidget) mediante Query Parameters en la URL
 * del <iframe>, siguiendo el patrón documentado en la práctica.
 *
 * El iframe apunta a `/flutter_stats/index.html`, que existe una vez que
 * se compila flutter-stats-widget (`flutter build web`) y se copia su
 * salida a `vitasync-frontend/public/flutter_stats/` (ver README de
 * flutter-stats-widget). Mientras ese paso no se haya hecho, el iframe
 * simplemente se ve vacío: el resto del dashboard (contador de tareas,
 * botones) funciona igual.
 */
@Component({
  selector: 'app-dashboard',
  imports: [RouterLink],
  templateUrl: './dashboard.html',
  styleUrl: './dashboard.css',
})
export class Dashboard {
  pendientes = 5;
  enProgreso = 3;
  completadas = 12;

  constructor(private sanitizer: DomSanitizer) {}

  completarTarea(): void {
    if (this.enProgreso > 0) this.enProgreso--;
    this.completadas++;
  }

  agregarTarea(): void {
    this.pendientes++;
  }

  iniciarTarea(): void {
    if (this.pendientes > 0) {
      this.pendientes--;
      this.enProgreso++;
    }
  }

  /** URL del widget Flutter Web, recalculada cada vez que cambia el estado. */
  get flutterStatsUrl(): SafeResourceUrl {
    const url =
      `/flutter_stats/index.html?pending=${this.pendientes}` +
      `&progress=${this.enProgreso}&completed=${this.completadas}`;
    return this.sanitizer.bypassSecurityTrustResourceUrl(url);
  }
}
