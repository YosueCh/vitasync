package com.vitasync.backend.smartwatch.service;

import com.vitasync.backend.smartwatch.dto.MetasDTO;
import com.vitasync.backend.smartwatch.dto.MetricasDTO;
import com.vitasync.backend.smartwatch.repository.DispositivoRepository;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * Prueba de regresión para un bug real encontrado durante las pruebas en
 * vivo: el botón "Sincronizar" de la web manda un cuerpo vacío ({}), que
 * Jackson deserializa como un MetricasDTO válido con todo en cero (no como
 * null). Antes de la corrección, eso guardaba una lectura en cero en vez de
 * generar datos nuevos — ver SmartwatchService.sincronizar().
 */
class SmartwatchServiceTest {

    @Test
    void sincronizarSinLecturaReal_generaMetricasNuevasEnVezDeCeros() {
        DispositivoRepository repo = mock(DispositivoRepository.class);
        when(repo.buscarPorUsuario("u1")).thenReturn(null);
        SmartwatchService service = new SmartwatchService(Optional.of(repo));

        // Simula el body vacío ({}): timestamp null, no un objeto null.
        MetricasDTO vacio = new MetricasDTO(0, 0, 0.0, 0, 0, null);

        MetasDTO resultado = service.sincronizar("u1", vacio);
        assertThat(resultado).isNotNull();

        MetricasDTO guardado = service.metricas("u1");
        assertThat(guardado.timestamp()).isNotNull();
        assertThat(guardado.pasos()).isGreaterThan(0);
    }

    @Test
    void sincronizarConLecturaReal_guardaExactamenteEsaLectura() {
        DispositivoRepository repo = mock(DispositivoRepository.class);
        when(repo.buscarPorUsuario("u2")).thenReturn(null);
        SmartwatchService service = new SmartwatchService(Optional.of(repo));

        MetricasDTO real = new MetricasDTO(9999, 500, 7.5, 70, 80, Instant.now());
        service.sincronizar("u2", real);

        assertThat(service.metricas("u2").pasos()).isEqualTo(9999);
    }

    @Test
    void metricas_deUsuariosDistintos_quedanSeparadas() {
        DispositivoRepository repo = mock(DispositivoRepository.class);
        SmartwatchService service = new SmartwatchService(Optional.of(repo));

        service.sincronizar("alumno1", new MetricasDTO(1111, 111, 1.1, 60, 50, Instant.now()));
        service.sincronizar("alumno2", new MetricasDTO(2222, 222, 2.2, 70, 60, Instant.now()));

        assertThat(service.metricas("alumno1").pasos()).isEqualTo(1111);
        assertThat(service.metricas("alumno2").pasos()).isEqualTo(2222);
    }
}
