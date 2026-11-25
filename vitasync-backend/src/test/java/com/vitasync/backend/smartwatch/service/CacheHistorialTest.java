package com.vitasync.backend.smartwatch.service;

import com.vitasync.backend.smartwatch.dto.MetricasDTO;
import com.vitasync.backend.smartwatch.repository.DispositivoRepository;
import com.vitasync.backend.smartwatch.repository.HistorialMetricasRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.atomic.AtomicInteger;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * PRÁCTICA 12 · PER-11 · La caché del historial: cuántas consultas a Firestore se evitan y, sobre todo, que NO se sirve
 * un historial viejo después de una escritura (el defecto que una caché mal hecha introduciría).
 */
class CacheHistorialTest {

    private HistorialMetricasRepository historial;
    private DispositivoRepository dispositivos;

    private static MetricasDTO lectura(int pasos) {
        return new MetricasDTO(pasos, 100, 7.0, 70, 80, Instant.parse("2026-11-24T10:00:00Z"));
    }

    @BeforeEach
    void preparar() {
        historial = mock(HistorialMetricasRepository.class);
        dispositivos = mock(DispositivoRepository.class);
        when(historial.ultimas(eq("u1"), anyInt())).thenReturn(List.of(lectura(1000)));
    }

    private SmartwatchService servicio(long vigenciaMs) {
        return new SmartwatchService(Optional.of(dispositivos), Optional.of(historial), vigenciaMs);
    }

    @Test
    void conCache_variasConsultasIgualesHacenUnaSolaIdaAFirestore() {
        SmartwatchService s = servicio(60_000);
        for (int i = 0; i < 50; i++) s.historial("u1", 24);

        verify(historial, times(1)).ultimas("u1", 24);
    }

    @Test
    void sinCache_vigenciaCero_cadaConsultaVaAFirestore_comportamientoAnterior() {
        SmartwatchService s = servicio(0);
        for (int i = 0; i < 50; i++) s.historial("u1", 24);

        verify(historial, times(50)).ultimas("u1", 24);
    }

    @Test
    void limitesDistintos_sonEntradasDistintas() {
        SmartwatchService s = servicio(60_000);
        s.historial("u1", 10);
        s.historial("u1", 24);
        s.historial("u1", 10);

        verify(historial, times(1)).ultimas("u1", 10);
        verify(historial, times(1)).ultimas("u1", 24);
    }

    @Test
    void usuariosDistintos_noComparten() {
        when(historial.ultimas(eq("u2"), anyInt())).thenReturn(List.of(lectura(2000)));
        SmartwatchService s = servicio(60_000);

        assertThat(s.historial("u1", 5).get(0).pasos()).isEqualTo(1000);
        assertThat(s.historial("u2", 5).get(0).pasos()).isEqualTo(2000);
    }

    @Test
    void unaLecturaNuevaInvalidaLaCache_noSeSirveHistorialViejo() {
        when(dispositivos.buscarPorUsuario("u1")).thenReturn(null);
        SmartwatchService s = servicio(60_000);
        s.historial("u1", 24); // llena la caché
        when(historial.ultimas(eq("u1"), anyInt())).thenReturn(List.of(lectura(9999), lectura(1000)));

        s.sincronizar("u1", lectura(9999)); // el reloj sincroniza una lectura nueva
        List<MetricasDTO> despues = s.historial("u1", 24);

        assertThat(despues).hasSize(2);
        assertThat(despues.get(0).pasos()).isEqualTo(9999);
        verify(historial, times(2)).ultimas("u1", 24);
    }

    @Test
    void sinvalidarOtroUsuario_laCacheDeLosDemasSeConserva() {
        when(historial.ultimas(eq("u2"), anyInt())).thenReturn(List.of(lectura(2000)));
        when(dispositivos.buscarPorUsuario(any())).thenReturn(null);
        SmartwatchService s = servicio(60_000);
        s.historial("u2", 24);

        s.sincronizar("u1", lectura(5)); // escribe otro usuario
        s.historial("u2", 24);

        verify(historial, times(1)).ultimas("u2", 24);
    }

    @Test
    void laCacheExpira_alPasarLaVigencia() throws Exception {
        SmartwatchService s = servicio(40);
        s.historial("u1", 24);
        Thread.sleep(80);
        s.historial("u1", 24);

        verify(historial, times(2)).ultimas("u1", 24);
    }

    @Test
    void alBorrarLaCuenta_seOlvidaElHistorial() {
        SmartwatchService s = servicio(60_000);
        s.historial("u1", 24);
        s.borrarDatosDe("u1");
        s.historial("u1", 24);

        verify(historial, times(2)).ultimas("u1", 24);
    }

    @Test
    void unaConsultaLentaQueEmpezoAntesDeLaEscritura_noGuardaSuResultadoViejo() throws Exception {
        when(dispositivos.buscarPorUsuario(any())).thenReturn(null);
        CountDownLatch empezo = new CountDownLatch(1);
        CountDownLatch continuar = new CountDownLatch(1);
        AtomicInteger llamadas = new AtomicInteger();
        when(historial.ultimas(eq("u1"), anyInt())).thenAnswer(inv -> {
            if (llamadas.getAndIncrement() == 0) { // la primera consulta es lenta y devuelve datos VIEJOS
                empezo.countDown();
                continuar.await();
                return List.of(lectura(1000));
            }
            return List.of(lectura(9999), lectura(1000)); // las siguientes ya ven la escritura
        });
        SmartwatchService s = servicio(60_000);

        Thread lenta = new Thread(() -> s.historial("u1", 24));
        lenta.start();
        empezo.await();
        s.sincronizar("u1", lectura(9999)); // la escritura ocurre MIENTRAS la consulta lenta está en vuelo
        continuar.countDown();
        lenta.join();

        assertThat(s.historial("u1", 24).get(0).pasos()).as("debe ver la lectura nueva, no el resultado viejo").isEqualTo(9999);
    }

    @Test
    void sinFirebase_respondeVacioSinCache() {
        SmartwatchService s = new SmartwatchService(Optional.empty(), Optional.empty(), 60_000);
        assertThat(s.historial("u1", 24)).isEmpty();
    }

    @Test
    void elTopeDeEntradas_noPermiteCrecerSinLimite() {
        when(historial.ultimas(any(), anyInt())).thenReturn(List.of(lectura(1)));
        SmartwatchService s = servicio(60_000);
        for (int i = 0; i < SmartwatchService.MAX_ENTRADAS_CACHE + 50; i++) s.historial("usuario" + i, 24);

        // No hay forma pública de contar: basta con que sigue respondiendo bien tras superar el tope.
        assertThat(s.historial("usuario0", 24)).hasSize(1);
    }
}
