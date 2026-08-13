import { Component, ElementRef, HostListener, signal, ViewChild } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';
import { FormsModule } from '@angular/forms';
import { Subject } from 'rxjs';
import { debounceTime, distinctUntilChanged, switchMap } from 'rxjs/operators';
import { ResultadoBusqueda, SearchService } from '../../services/search.service';

/**
 * Buscador del sitio (Práctica 3-4, punto 2): permite encontrar
 * contenido de cualquier página sin salir del sitio. Se abre como un
 * overlay desde el ícono de lupa del navbar, muestra resultados en
 * vivo (con debounce) y navega con Angular Router al hacer clic —
 * es decir, todo ocurre dentro de la misma SPA.
 */
@Component({
  selector: 'app-search-box',
  imports: [CommonModule, FormsModule],
  templateUrl: './search-box.html',
  styleUrl: './search-box.css',
})
export class SearchBox {
  @ViewChild('campoBusqueda') campoBusqueda!: ElementRef<HTMLInputElement>;

  abierto = signal(false);
  query = '';
  resultados = signal<ResultadoBusqueda[]>([]);
  buscando = signal(false);

  /** Subject que alimenta el pipeline de búsqueda con debounce. */
  private query$ = new Subject<string>();

  constructor(private search: SearchService, private router: Router) {
    this.query$
      .pipe(
        debounceTime(180),           // espera a que el usuario deje de teclear
        distinctUntilChanged(),
        switchMap((q) => {
          this.buscando.set(true);
          return this.search.buscar(q);
        })
      )
      .subscribe((res) => {
        this.resultados.set(res);
        this.buscando.set(false);
      });
  }

  abrir(): void {
    this.abierto.set(true);
    // Espera al siguiente ciclo para que el input ya exista en el DOM.
    setTimeout(() => this.campoBusqueda?.nativeElement.focus(), 50);
  }

  cerrar(): void {
    this.abierto.set(false);
    this.query = '';
    this.resultados.set([]);
  }

  onInput(valor: string): void {
    this.query = valor;
    this.query$.next(valor);
  }

  irAResultado(r: ResultadoBusqueda): void {
    this.cerrar();
    this.router.navigate([r.ruta], r.fragmento ? { fragment: r.fragmento } : {});
  }

  /** Atajo de teclado: Escape cierra el buscador. */
  @HostListener('document:keydown.escape')
  onEscape(): void {
    if (this.abierto()) this.cerrar();
  }
}
