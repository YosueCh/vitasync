import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable, of } from 'rxjs';
import { Document } from 'flexsearch';
import { INDICE_BUSQUEDA, DocumentoBuscable } from '../core/search-index';
import { AUTH_CONFIG } from '../core/auth.config';

export interface ResultadoBusqueda {
  id: string;
  titulo: string;
  contenido: string;
  ruta: string;
  fragmento?: string;
  categoria: string;
}

/**
 * Servicio de búsqueda del sitio.
 *
 * Sigue el MISMO patrón dual ya usado en `smartwatch.service.ts`
 * (Prácticas 5-6): una bandera `MODO_LOCAL` decide si la búsqueda se
 * resuelve con un índice en memoria (FlexSearch, útil para demos sin
 * backend) o llamando a la API real `/api/search`, respaldada por
 * Elasticsearch en Spring Boot.
 *
 * Backend: carpeta hermana `../vitasync-backend/` (Maven, Spring Boot).
 * Guía paso a paso en `../vitasync-backend/docs-elasticsearch/GUIA_ELASTICSEARCH.md`.
 *
 * IMPORTANTE: cambia `MODO_LOCAL` a `false` una vez que tengas
 * Elasticsearch + el backend de Spring Boot corriendo en tu máquina.
 */
@Injectable({ providedIn: 'root' })
export class SearchService {
  /** true = busca en el índice local (FlexSearch); false = busca en /api/search (Elasticsearch real). */
  private readonly MODO_LOCAL = false;
  private readonly API = `${AUTH_CONFIG.api}/search`;

  /** Índice FlexSearch construido una sola vez al iniciar el servicio. */
  private indice = new Document<any, false, false>({
    document: {
      id: 'id',
      index: ['titulo', 'contenido'],
      store: ['titulo', 'contenido', 'ruta', 'fragmento', 'categoria'],
    },
    tokenize: 'forward', // permite coincidencias por prefijo mientras el usuario escribe
  });

  constructor(private http: HttpClient) {
    for (const doc of INDICE_BUSQUEDA) {
      this.indice.add(doc as any);
    }
  }

  /**
   * Busca contenido del sitio. Devuelve un Observable en ambos modos
   * para que el componente no necesite saber cuál está activo.
   */
  buscar(query: string): Observable<ResultadoBusqueda[]> {
    const q = query.trim();
    if (!q) return of([]);

    if (!this.MODO_LOCAL) {
      // Modo real: pega contra el backend respaldado por Elasticsearch.
      return this.http.get<ResultadoBusqueda[]>(`${this.API}?q=${encodeURIComponent(q)}`);
    }

    // Modo local: FlexSearch, índice invertido en memoria (mismo concepto
    // que Elasticsearch, ejecutándose en el navegador sin servidor).
    const resultados = this.indice.search(q, { merge: true, enrich: true, limit: 8 }) as any[];
    const mapeados: ResultadoBusqueda[] = resultados.map((r) => ({
      id: r.id as string,
      titulo: r.doc.titulo,
      contenido: r.doc.contenido,
      ruta: r.doc.ruta,
      fragmento: r.doc.fragmento,
      categoria: r.doc.categoria,
    }));
    return of(mapeados);
  }
}
