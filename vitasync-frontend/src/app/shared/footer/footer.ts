import { Component } from '@angular/core';
import { RouterLink } from '@angular/router';
import { Logo } from '../logo/logo';

/**
 * Pie de página: reúne datos de contacto (#8), botones de redes
 * sociales (#9) y enlaces a páginas complementarias (#13).
 */
@Component({
  selector: 'app-footer',
  imports: [RouterLink, Logo],
  templateUrl: './footer.html',
  styleUrl: './footer.css',
})
export class Footer {
  year = new Date().getFullYear();
}
