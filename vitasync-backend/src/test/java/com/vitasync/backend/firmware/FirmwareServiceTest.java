package com.vitasync.backend.firmware;

import com.vitasync.backend.smartwatch.model.Dispositivo;
import com.vitasync.backend.smartwatch.repository.DispositivoRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class FirmwareServiceTest {

    private DispositivoRepository repo;
    private FirmwareService service;
    private Dispositivo dispositivo;

    @BeforeEach
    void preparar() {
        repo = mock(DispositivoRepository.class);
        dispositivo = new Dispositivo();
        dispositivo.setFirmware("v2.3.1");
        when(repo.buscarPorUsuario("u1")).thenReturn(dispositivo);
        service = new FirmwareService(Optional.of(repo));
    }

    @Test
    void conVersionVieja_hayActualizacionYNoHayOrden() {
        EstadoFirmwareDTO e = service.estado("u1");
        assertThat(e.hayActualizacion()).isTrue();
        assertThat(e.ordenPendiente()).isFalse();
    }

    @Test
    void solicitar_dejaOrdenPendienteParaElFirmware() {
        service.solicitar("u1");
        assertThat(service.ordenPendiente("u1")).contains(FirmwareService.ULTIMA.version());
    }

    @Test
    void solicitarConVersionAlDia_noCreaOrden() {
        dispositivo.setFirmware(FirmwareService.ULTIMA.version());
        service.solicitar("u1");
        assertThat(service.ordenPendiente("u1")).isEmpty();
    }

    @Test
    void aplicar_guardaLaVersionYLimpiaLaOrden() {
        service.solicitar("u1");
        EstadoFirmwareDTO e = service.aplicar("u1", "v2.4.0");

        verify(repo).guardar("u1", dispositivo);
        assertThat(dispositivo.getFirmware()).isEqualTo("v2.4.0");
        assertThat(e.ordenPendiente()).isFalse();
        assertThat(e.hayActualizacion()).isFalse();
    }
}
