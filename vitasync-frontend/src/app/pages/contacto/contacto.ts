import { Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ReactiveFormsModule, FormBuilder, Validators } from '@angular/forms';

/**
 * Página de Contacto. Incluye:
 * - #10 Formulario de contacto (validación reactiva, sin backend real).
 * - #8 Datos de contacto.
 * - #12 Mapa de ubicación (Google Maps embebido, sin API key).
 * - #9 Redes sociales (reforzadas aquí también).
 */
@Component({
  selector: 'app-contacto',
  imports: [CommonModule, ReactiveFormsModule],
  templateUrl: './contacto.html',
  styleUrl: './contacto.css',
})
export class Contacto {
  private fb = inject(FormBuilder);

  enviado = false;

  formulario = this.fb.group({
    nombre: ['', [Validators.required, Validators.minLength(2)]],
    email: ['', [Validators.required, Validators.email]],
    motivo: ['demo', [Validators.required]],
    mensaje: ['', [Validators.required, Validators.minLength(10)]],
  });

  /** Devuelve true si el control tiene un error y ya fue tocado. */
  tieneError(control: string): boolean {
    const c = this.formulario.get(control);
    return !!c && c.invalid && (c.dirty || c.touched);
  }

  enviar(): void {
    if (this.formulario.invalid) {
      this.formulario.markAllAsTouched();
      return;
    }
    // Sin backend real: aquí se simula el envío (en producción, POST a la API).
    console.log('Formulario de contacto enviado:', this.formulario.value);
    this.enviado = true;
    this.formulario.reset({ motivo: 'demo' });
  }
}
