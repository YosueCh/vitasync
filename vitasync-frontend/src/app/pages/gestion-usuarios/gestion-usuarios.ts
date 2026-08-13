import { Component, OnInit } from '@angular/core';
import { CommonModule, DatePipe } from '@angular/common';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import Swal from 'sweetalert2';

import { UsuarioService } from '../../services/usuario.service';
import { Usuario } from '../../models/usuario.model';

/**
 * Pantalla "Gestión de Usuarios" — Práctica 13 reinterpretada como
 * feature real de VitaSync: crear cuentas, habilitar/deshabilitar
 * (reversible, conserva datos) vs eliminar (permanente), y probar el
 * efecto real de cada estado con "Probar inicio de sesión".
 */
@Component({
  selector: 'app-gestion-usuarios',
  imports: [CommonModule, DatePipe, ReactiveFormsModule],
  templateUrl: './gestion-usuarios.html',
  styleUrl: './gestion-usuarios.css',
})
export class GestionUsuarios implements OnInit {
  usuarios: Usuario[] = [];
  cargando = true;
  procesando = new Set<string>();

  private fb = new FormBuilder();
  formulario = this.fb.group({
    nombreCompleto: ['', [Validators.required, Validators.minLength(2)]],
    username: ['', [Validators.required, Validators.pattern(/^[a-z0-9_.-]+$/i)]],
    grupo: ['alumnos', [Validators.required]],
  });

  constructor(private usuarioService: UsuarioService) {}

  ngOnInit(): void {
    this.refrescar();
  }

  refrescar(): void {
    this.cargando = true;
    this.usuarioService.listar().subscribe((lista) => {
      this.usuarios = lista;
      this.cargando = false;
    });
  }

  tieneError(control: string): boolean {
    const c = this.formulario.get(control);
    return !!c && c.invalid && (c.dirty || c.touched);
  }

  crear(): void {
    if (this.formulario.invalid) {
      this.formulario.markAllAsTouched();
      return;
    }
    const { nombreCompleto, username, grupo } = this.formulario.getRawValue();
    this.usuarioService
      .crear({ nombreCompleto: nombreCompleto!, username: username!, grupos: [grupo!] })
      .subscribe(() => {
        this.formulario.reset({ grupo: 'alumnos' });
        this.refrescar();
      });
  }

  toggleHabilitado(u: Usuario): void {
    this.procesando.add(u.id);
    const accion = u.habilitado
      ? this.usuarioService.deshabilitar(u.id)
      : this.usuarioService.habilitar(u.id);
    accion.subscribe(() => {
      this.procesando.delete(u.id);
      this.refrescar();
    });
  }

  eliminar(u: Usuario): void {
    Swal.fire({
      icon: 'warning',
      title: `¿Eliminar a ${u.nombreCompleto}?`,
      text: 'Esta acción es permanente: a diferencia de deshabilitar, no se puede revertir y se pierde toda su información.',
      showCancelButton: true,
      confirmButtonText: 'Eliminar',
      cancelButtonText: 'Cancelar',
      confirmButtonColor: '#FF6B6B',
    }).then((r) => {
      if (!r.isConfirmed) return;
      this.usuarioService.eliminar(u.id).subscribe(() => this.refrescar());
    });
  }

  probarLogin(u: Usuario): void {
    this.usuarioService.simularLogin(u.id).subscribe((res) => {
      Swal.fire({
        icon: res.exito ? 'success' : 'error',
        title: res.exito ? 'Inicio de sesión exitoso' : 'Inicio de sesión rechazado',
        text: res.mensaje,
      });
      if (res.exito) this.refrescar();
    });
  }
}
