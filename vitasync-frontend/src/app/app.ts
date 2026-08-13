import { Component } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { AnnouncementBar } from './shared/announcement-bar/announcement-bar';
import { Navbar } from './shared/navbar/navbar';
import { Footer } from './shared/footer/footer';
import { PromoModal } from './shared/promo-modal/promo-modal';

/**
 * Componente raíz: banner de anuncio (#banner digital), menú de
 * navegación, contenido de la página activa, pie de página y el
 * pop up promocional (se monta una sola vez, vive sobre toda la app).
 */
@Component({
  selector: 'app-root',
  imports: [RouterOutlet, AnnouncementBar, Navbar, Footer, PromoModal],
  templateUrl: './app.html',
  styleUrl: './app.css',
})
export class App {}
