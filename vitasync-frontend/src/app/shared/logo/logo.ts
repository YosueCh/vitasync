import { Component, Input } from '@angular/core';

/**
 * Marca de VitaSync (#4 "Logotipo" del checklist): un anillo —que evoca
 * la esfera del smartwatch— atravesado por una línea de pulso cardiaco.
 * Se usa tanto en el navbar como en el footer.
 */
@Component({
  selector: 'app-logo',
  imports: [],
  templateUrl: './logo.html',
  styleUrl: './logo.css',
})
export class Logo {
  /** Color del trazo; permite usar la versión clara sobre fondo oscuro. */
  @Input() variant: 'dark' | 'light' = 'dark';
}
