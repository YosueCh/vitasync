import { Component, inject } from '@angular/core';
import { Router, RouterLink, RouterLinkActive } from '@angular/router';
import { AuthService } from '../../core/auth.service';
import { Logo } from '../logo/logo';
import { SearchBox } from '../search-box/search-box';

/**
 * Menú de navegación (#5 "Menús" del checklist). Usa RouterLink para
 * que la navegación entre páginas internas (#3) ocurra sin recargar
 * el navegador. Incluye un botón de menú móvil con CSS puro (checkbox
 * oculto), sin dependencias adicionales, y el buscador del sitio
 * (Práctica 3-4).
 */
@Component({
  selector: 'app-navbar',
  imports: [RouterLink, RouterLinkActive, Logo, SearchBox],
  templateUrl: './navbar.html',
  styleUrl: './navbar.css',
})
export class Navbar {
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  readonly sesion = this.auth.sesion;

  salir(): void {
    this.auth.cerrarSesion();
    void this.router.navigateByUrl('/');
  }
}
