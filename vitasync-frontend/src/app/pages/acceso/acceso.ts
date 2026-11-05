import { Component, inject, signal } from '@angular/core';
import { ActivatedRoute, Router } from '@angular/router';

import { AuthService } from '../../core/auth.service';

/**
 * Acceso con correo y contraseña (Práctica 10 en el sitio web). Entrar o crear una cuenta; al terminar lleva a la
 * página que la persona quería abrir (o al dashboard).
 */
@Component({
  selector: 'app-acceso',
  templateUrl: './acceso.html',
  styleUrl: './acceso.css',
})
export class Acceso {
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  private readonly ruta = inject(ActivatedRoute);

  readonly correo = signal('');
  readonly clave = signal('');
  readonly error = signal<string | null>(null);
  readonly trabajando = signal(false);
  readonly sesion = this.auth.sesion;
  readonly vencida = this.ruta.snapshot.queryParamMap.get('vencida') === '1';

  escribir(campo: 'correo' | 'clave', evento: Event): void {
    (campo === 'correo' ? this.correo : this.clave).set((evento.target as HTMLInputElement).value);
    this.error.set(null);
  }

  entrar(evento?: Event): void {
    evento?.preventDefault();
    this.enviar(this.auth.iniciarSesion(this.correo().trim(), this.clave()));
  }

  crear(): void {
    this.enviar(this.auth.registrarse(this.correo().trim(), this.clave()));
  }

  salir(): void {
    this.auth.cerrarSesion();
    this.clave.set('');
  }

  private enviar(operacion: ReturnType<AuthService['iniciarSesion']>): void {
    if (!this.correo().trim() || !this.clave()) {
      this.error.set('Escribe tu correo y tu contraseña.');
      return;
    }
    this.trabajando.set(true);
    this.error.set(null);
    operacion.subscribe({
      next: () => {
        this.trabajando.set(false);
        this.clave.set('');
        const destino = this.ruta.snapshot.queryParamMap.get('volver');
        // Solo rutas internas (nunca un enlace a otro sitio).
        void this.router.navigateByUrl(destino && destino.startsWith('/') && !destino.startsWith('//') ? destino : '/dashboard');
      },
      error: (e: Error) => {
        this.trabajando.set(false);
        this.error.set(e.message);
      },
    });
  }
}
