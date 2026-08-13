import { Component, OnInit, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';

/**
 * Pop up promocional (Práctica 1-2: "posibilidad de pop ups").
 * Aparece una sola vez por sesión, unos segundos después de cargar
 * el sitio, e invita a agendar una demo o dejar el correo.
 * No depende de localStorage: vive en memoria mientras dure la sesión,
 * tal como exige el entorno de Artifacts (aunque aquí es un proyecto
 * real, se mantiene la misma práctica simple a propósito).
 */
@Component({
  selector: 'app-promo-modal',
  imports: [CommonModule, FormsModule, RouterLink],
  templateUrl: './promo-modal.html',
  styleUrl: './promo-modal.css',
})
export class PromoModal implements OnInit {
  abierto = signal(false);
  enviado = signal(false);
  correo = '';

  ngOnInit(): void {
    // Se muestra una sola vez, 4 segundos después de entrar al sitio.
    setTimeout(() => this.abierto.set(true), 4000);
  }

  cerrar(): void {
    this.abierto.set(false);
  }

  enviarCorreo(): void {
    if (!this.correo || !this.correo.includes('@')) return;
    // Sin backend real: se simula el registro del correo (ver Práctica 5-6
    // para el patrón de conexión real a una API).
    console.log('Pop up: correo registrado para seguimiento:', this.correo);
    this.enviado.set(true);
    setTimeout(() => this.cerrar(), 1800);
  }
}
