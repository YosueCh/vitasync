import { Injectable, signal } from '@angular/core';

import { Usuario } from '../models/usuario.model';
import { UsuarioService } from './usuario.service';

const STORAGE_KEY = 'vitasync_usuario_activo_id';

/**
 * Quién está "usando" el sitio ahora mismo. No es un login real (no pide
 * contraseña) — es un selector simple para que las pantallas que
 * dependen de una cuenta (Configuración de Dispositivo, el reloj) sepan
 * de qué usuario son los datos que muestran, en vez de compartir un
 * único dispositivo global entre cualquiera que entre al sitio.
 */
@Injectable({ providedIn: 'root' })
export class UsuarioActivoService {
  readonly usuarios = signal<Usuario[]>([]);
  readonly usuarioActivo = signal<Usuario | null>(null);

  constructor(private usuarioService: UsuarioService) {
    this.usuarioService.listar().subscribe((lista) => {
      this.usuarios.set(lista);
      const guardadoId = localStorage.getItem(STORAGE_KEY);
      const guardado = lista.find((u) => u.id === guardadoId);
      this.usuarioActivo.set(guardado ?? lista[0] ?? null);
    });
  }

  seleccionar(usuario: Usuario): void {
    this.usuarioActivo.set(usuario);
    localStorage.setItem(STORAGE_KEY, usuario.id);
  }
}
