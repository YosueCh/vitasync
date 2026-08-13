package com.vitasync.backend.search;

/**
 * Forma exacta que espera la interfaz ResultadoBusqueda de
 * src/app/services/search.service.ts en el frontend Angular.
 */
public record SearchResultDTO(
        String id,
        String titulo,
        String contenido,
        String ruta,
        String fragmento,
        String categoria
) {
    static SearchResultDTO from(SearchDocument doc) {
        return new SearchResultDTO(
                doc.getId(),
                doc.getTitulo(),
                doc.getContenido(),
                doc.getRuta(),
                doc.getFragmento(),
                doc.getCategoria()
        );
    }
}
