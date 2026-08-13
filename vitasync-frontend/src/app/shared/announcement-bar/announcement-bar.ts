import { Component, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';

/**
 * Banner digital de anuncio, fijo en la parte superior del sitio
 * (Práctica 1-2: "posibilidad de banners digitales"). Es descartable:
 * el usuario puede cerrarlo y no vuelve a aparecer durante la sesión.
 */
@Component({
  selector: 'app-announcement-bar',
  imports: [CommonModule, RouterLink],
  templateUrl: './announcement-bar.html',
  styleUrl: './announcement-bar.css',
})
export class AnnouncementBar {
  /** signal: estado reactivo nativo de Angular para mostrar/ocultar el banner. */
  visible = signal(true);

  cerrar(): void {
    this.visible.set(false);
  }
}
