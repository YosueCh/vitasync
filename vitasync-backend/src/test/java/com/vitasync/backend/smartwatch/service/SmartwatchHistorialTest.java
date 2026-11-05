package com.vitasync.backend.smartwatch.service;

import com.vitasync.backend.smartwatch.dto.MetricasDTO;
import com.vitasync.backend.smartwatch.repository.DispositivoRepository;
import com.vitasync.backend.smartwatch.repository.HistorialMetricasRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Historial de lecturas del smartwatch en la base de datos: las cards de la
 * app móvil muestran la última lectura y, al tocarlas, este historial.
 */
class SmartwatchHistorialTest {

    private HistorialMetricasRepository historial;
    private SmartwatchService service;

    @BeforeEach
    void preparar() {
        historial = mock(HistorialMetricasRepository.class);
        service = new SmartwatchService(Optional.of(mock(DispositivoRepository.class)), Optional.of(historial));
    }

    private static MetricasDTO lectura(int pasos) {
        return new MetricasDTO(pasos, 300, 7.0, 70, 80, Instant.now());
    }

    @Test
    void sincronizar_guardaLaLecturaEnElHistorialDeLaBaseDeDatos() {
        MetricasDTO real = lectura(5000);

        service.sincronizar("u1", real);

        verify(historial).guardar("u1", real);
    }

    @Test
    void sincronizarSinLecturaReal_guardaEnHistorialLaLecturaGenerada() {
        service.sincronizar("u1", new MetricasDTO(0, 0, 0.0, 0, 0, null));

        MetricasDTO enMemoria = service.metricas("u1").orElseThrow();
        verify(historial).guardar("u1", enMemoria);
    }

    @Test
    void siFallaElHistorial_laSincronizacionContinua() {
        doThrow(new IllegalStateException("Firestore caído")).when(historial).guardar(anyString(), any());

        MetricasDTO real = lectura(1234);
        service.sincronizar("u1", real);

        assertThat(service.metricas("u1").orElseThrow().pasos()).isEqualTo(1234);
    }

    @Test
    void historial_devuelveLasLecturasGuardadasMasRecientesPrimero() {
        List<MetricasDTO> guardadas = List.of(lectura(3), lectura(2), lectura(1));
        when(historial.ultimas("u1", 30)).thenReturn(guardadas);

        assertThat(service.historial("u1", 30)).containsExactlyElementsOf(guardadas);
    }

    @Test
    void historial_acotaElLimitePedido() {
        when(historial.ultimas(anyString(), anyInt())).thenReturn(List.of());

        service.historial("u1", 99999);
        service.historial("u1", 0);

        verify(historial).ultimas("u1", SmartwatchService.LIMITE_MAXIMO_HISTORIAL);
        verify(historial).ultimas("u1", 1);
    }

    @Test
    void metricas_sinLecturaEnMemoria_usaLaUltimaGuardadaEnLaBaseDeDatos() {
        // p. ej. el servidor se reinició: las cards no deben mostrar datos inventados
        when(historial.ultimas("u1", 1)).thenReturn(List.of(lectura(8888)));

        assertThat(service.metricas("u1").orElseThrow().pasos()).isEqualTo(8888);
    }

    @Test
    void metricas_sinNingunaLectura_noInventaDatos() {
        // D-05 de la Práctica 8: una cuenta sin lecturas ya no recibe valores de ejemplo como si fueran reales
        when(historial.ultimas(eq("nuevo"), anyInt())).thenReturn(List.of());

        assertThat(service.metricas("nuevo")).isEmpty();
    }

    @Test
    void sinBaseDeHistorial_elHistorialEstaVacioYNoSeIntentaGuardar() {
        SmartwatchService sinHistorial = new SmartwatchService(Optional.of(mock(DispositivoRepository.class)));

        sinHistorial.sincronizar("u1", lectura(10));

        assertThat(sinHistorial.historial("u1", 30)).isEmpty();
        verify(historial, never()).guardar(anyString(), any());
    }
}
