package com.vitasync.backend.search;

import org.junit.jupiter.api.Test;
import org.springframework.data.elasticsearch.core.ElasticsearchOperations;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Elasticsearch es opcional: si no está encendido el backend NO debe caerse al arrancar (era lo que impedía
 * ejecutar el servidor completo contra Firebase), y el buscador del servidor responde 503 con un mensaje claro.
 */
class ElasticsearchOpcionalTest {

    @Test
    void alArrancarSinElasticsearch_laSiembraNoTumbaLaAplicacion() {
        SearchDocumentRepository repo = mock(SearchDocumentRepository.class);
        when(repo.count()).thenThrow(new RuntimeException("Connection refused"));
        assertThatCode(() -> new SearchIndexSeeder(repo).run()).doesNotThrowAnyException();
    }

    @Test
    void conElasticsearch_sigueSembrandoElIndiceVacio() {
        SearchDocumentRepository repo = mock(SearchDocumentRepository.class);
        when(repo.count()).thenReturn(0L);
        new SearchIndexSeeder(repo).run();
        org.mockito.Mockito.verify(repo).saveAll(any());
    }

    @Test
    void sinElInterruptor_noHayServicio_yElBuscadorResponde503() throws Exception {
        MockMvc mvc = MockMvcBuilders.standaloneSetup(new SearchController(java.util.Optional.empty())).build();
        mvc.perform(get("/api/search?q=sueno")).andExpect(status().isServiceUnavailable());
    }

    @Test
    void elBuscadorSinElasticsearch_responde503ConUnMensaje() throws Exception {
        ElasticsearchOperations operaciones = mock(ElasticsearchOperations.class);
        when(operaciones.search(any(org.springframework.data.elasticsearch.core.query.Query.class), any(Class.class)))
                .thenThrow(new RuntimeException("Connection refused"));
        MockMvc mvc = MockMvcBuilders.standaloneSetup(new SearchController(java.util.Optional.of(new SearchService(operaciones)))).build();
        mvc.perform(get("/api/search?q=sueno")).andExpect(status().isServiceUnavailable())
                .andExpect(jsonPath("$.error").value(org.hamcrest.Matchers.containsString("Elasticsearch")));
    }
}
