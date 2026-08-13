import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';

import { CastService } from '../../services/cast.service';

/**
 * Vista "del lado de la TV" (Práctica 9-10): se abre en la Smart TV (o
 * en otra pestaña/dispositivo, para efectos de la demo), recibe el
 * código de 6 dígitos generado en `/smart-tv` y, al validarlo, muestra
 * un espejo simplificado del dashboard pensado para verse a distancia
 * (fuentes grandes, alto contraste).
 */
@Component({
  selector: 'app-smart-tv-pantalla',
  imports: [CommonModule, FormsModule],
  templateUrl: './smart-tv-pantalla.html',
  styleUrl: './smart-tv-pantalla.css',
})
export class SmartTvPantalla {
  codigo = '';
  emparejado = false;
  error: string | null = null;
  cargando = false;

  constructor(private cast: CastService) {}

  conectar(): void {
    if (this.codigo.trim().length !== 6) {
      this.error = 'El código debe tener 6 dígitos.';
      return;
    }
    this.cargando = true;
    this.error = null;
    this.cast.emparejar(this.codigo.trim()).subscribe({
      next: () => {
        this.cargando = false;
        this.emparejado = true;
      },
      error: (e) => {
        this.cargando = false;
        this.error = e?.error?.error ?? 'Código inválido o expirado.';
      },
    });
  }
}
