package com.vitasync.backend.usuarios.service;

import com.vitasync.backend.blackbox.RepositoriosEnMemoria;
import com.vitasync.backend.chat.ChatService;
import com.vitasync.backend.firmware.FirmwareService;
import com.vitasync.backend.smartwatch.dto.MetricasDTO;
import com.vitasync.backend.smartwatch.service.SmartwatchService;
import com.vitasync.backend.usuarios.dto.CrearUsuarioDTO;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/** D-04 de la Práctica 8: al eliminar una cuenta no deben quedar huérfanos su reloj, sus lecturas ni su chat. */
class EliminarCuentaTest {

    private RepositoriosEnMemoria.Dispositivos dispositivos;
    private RepositoriosEnMemoria.Historial historial;
    private SmartwatchService smartwatch;
    private ChatService chat;
    private FirmwareService firmware;
    private UsuarioService usuarios;
    private String ana;
    private String beto;

    @BeforeEach
    void preparar() {
        dispositivos = new RepositoriosEnMemoria.Dispositivos();
        historial = new RepositoriosEnMemoria.Historial();
        smartwatch = new SmartwatchService(Optional.of(dispositivos), Optional.of(historial));
        chat = new ChatService();
        firmware = new FirmwareService(Optional.of(dispositivos));
        usuarios = new UsuarioService(Optional.of(new RepositoriosEnMemoria.Usuarios()), List.of(smartwatch, chat, firmware));
        ana = usuarios.crear(new CrearUsuarioDTO("Ana Pérez", "ana", List.of())).id();
        beto = usuarios.crear(new CrearUsuarioDTO("Beto Ruiz", "beto", List.of())).id();
        for (String cuenta : List.of(ana, beto)) {
            smartwatch.conectar(cuenta);
            smartwatch.sincronizar(cuenta, new MetricasDTO(1000, 50, 7.0, 70, 80, Instant.now()));
            chat.enviar(cuenta, "PACIENTE", "hola desde " + cuenta);
            firmware.solicitar(cuenta);
        }
    }

    @Test
    void antesDeEliminar_laCuentaTieneTodosSusDatos() {
        assertThat(dispositivos.buscarPorUsuario(ana)).isNotNull();
        assertThat(smartwatch.historial(ana, 10)).hasSize(1);
        assertThat(smartwatch.metricas(ana)).isPresent();
        assertThat(chat.consultar(ana, 0).mensajes()).hasSize(1);
        assertThat(firmware.ordenPendiente(ana)).isPresent();
    }

    @Test
    void eliminarUnaCuenta_borraSuRelojSusLecturasSuChatYSuOrden() {
        usuarios.eliminar(ana);

        assertThat(dispositivos.buscarPorUsuario(ana)).as("reloj").isNull();
        assertThat(smartwatch.historial(ana, 10)).as("historial").isEmpty();
        assertThat(smartwatch.metricas(ana)).as("última lectura").isEmpty();
        assertThat(chat.consultar(ana, 0).mensajes()).as("chat").isEmpty();
        assertThat(firmware.ordenPendiente(ana)).as("orden de firmware").isEmpty();
        assertThatThrownBy(() -> usuarios.obtener(ana)).isInstanceOf(UsuarioService.UsuarioNoEncontradoException.class);
    }

    @Test
    void eliminarUnaCuenta_noTocaLosDatosDeOtra() {
        usuarios.eliminar(ana);

        assertThat(dispositivos.buscarPorUsuario(beto)).isNotNull();
        assertThat(smartwatch.historial(beto, 10)).hasSize(1);
        assertThat(smartwatch.metricas(beto)).isPresent();
        assertThat(chat.consultar(beto, 0).mensajes()).hasSize(1);
        assertThat(firmware.ordenPendiente(beto)).isPresent();
        assertThat(usuarios.obtener(beto).username()).isEqualTo("beto");
    }

    @Test
    void deshabilitar_noBorraNada_soloEliminarEsPermanente() {
        usuarios.deshabilitar(ana);

        assertThat(dispositivos.buscarPorUsuario(ana)).isNotNull();
        assertThat(smartwatch.historial(ana, 10)).hasSize(1);
        assertThat(chat.consultar(ana, 0).mensajes()).hasSize(1);
    }

    @Test
    void siLaLimpiezaFalla_laCuentaSigueExistiendo_yNoSeVuelveHuerfana() {
        LimpiezaDeCuenta quePeta = id -> { throw new IllegalStateException("Firestore caído"); };
        UsuarioService fragil = new UsuarioService(Optional.of(new RepositoriosEnMemoria.Usuarios()), List.of(quePeta));
        String cuenta = fragil.crear(new CrearUsuarioDTO("Carla Díaz", "carla", List.of())).id();

        assertThatThrownBy(() -> fragil.eliminar(cuenta)).isInstanceOf(IllegalStateException.class);

        assertThat(fragil.obtener(cuenta).username()).as("la cuenta sigue ahí para reintentar").isEqualTo("carla");
    }

    @Test
    void eliminarUnaCuentaInexistente_dice404_noInventaNada() {
        assertThatThrownBy(() -> usuarios.eliminar("no-existe"))
                .isInstanceOf(UsuarioService.UsuarioNoEncontradoException.class);
    }
}
