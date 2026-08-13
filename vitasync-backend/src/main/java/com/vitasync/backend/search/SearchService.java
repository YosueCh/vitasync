package com.vitasync.backend.search;

import co.elastic.clients.elasticsearch._types.query_dsl.Query;
import org.springframework.data.elasticsearch.client.elc.NativeQuery;
import org.springframework.data.elasticsearch.core.ElasticsearchOperations;
import org.springframework.data.elasticsearch.core.SearchHit;
import org.springframework.data.elasticsearch.core.SearchHits;
import org.springframework.stereotype.Service;

import java.util.List;

/**
 * Resuelve /api/search contra el indice "vitasync-content" de Elasticsearch.
 * Es el reemplazo real del modo local (FlexSearch) que usa el Angular
 * mientras SearchService.MODO_LOCAL = true (ver search.service.ts).
 */
@Service
public class SearchService {

    private static final int LIMITE_RESULTADOS = 8;

    private final ElasticsearchOperations operations;

    public SearchService(ElasticsearchOperations operations) {
        this.operations = operations;
    }

    public List<SearchResultDTO> buscar(String texto) {
        if (texto == null || texto.isBlank()) {
            return List.of();
        }

        // multi_match con boost en el titulo y tolerancia a errores de tecleo
        // (fuzziness AUTO), igual de flexible que la busqueda "forward" de
        // FlexSearch que usa el frontend en modo local.
        Query consulta = Query.of(q -> q.multiMatch(m -> m
                .fields("titulo^2", "contenido")
                .query(texto)
                .fuzziness("AUTO")
        ));

        NativeQuery query = NativeQuery.builder()
                .withQuery(consulta)
                .withMaxResults(LIMITE_RESULTADOS)
                .build();

        SearchHits<SearchDocument> hits = operations.search(query, SearchDocument.class);

        return hits.getSearchHits().stream()
                .map(SearchHit::getContent)
                .map(SearchResultDTO::from)
                .toList();
    }
}
