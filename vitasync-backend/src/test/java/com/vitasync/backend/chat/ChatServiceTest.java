package com.vitasync.backend.chat;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class ChatServiceTest {

    private ChatService service;

    @BeforeEach
    void preparar() {
        service = new ChatService();
    }

    @Test
    void enviar_guardaElMensajeConEmisorHoraEIdConsecutivo() {
        MensajeChatDTO a = service.enviar("u1", "medico", "  Hola, ¿cómo se siente?  ");
        MensajeChatDTO b = service.enviar("u1", "PACIENTE", "Mejor, gracias");

        assertThat(a.id()).isEqualTo(1);
        assertThat(a.emisor()).isEqualTo("MEDICO");
        assertThat(a.texto()).isEqualTo("Hola, ¿cómo se siente?");
        assertThat(a.hora()).isNotBlank();
        assertThat(b.id()).isEqualTo(2);
    }

    @Test
    void consultar_devuelveSoloLosMensajesPosterioresAlIdPedido() {
        service.enviar("u1", "MEDICO", "uno");
        service.enviar("u1", "PACIENTE", "dos");
        service.enviar("u1", "MEDICO", "tres");

        ConversacionDTO todos = service.consultar("u1", 0);
        ConversacionDTO nuevos = service.consultar("u1", 2);

        assertThat(todos.mensajes()).extracting(MensajeChatDTO::texto).containsExactly("uno", "dos", "tres");
        assertThat(nuevos.mensajes()).extracting(MensajeChatDTO::texto).containsExactly("tres");
        assertThat(nuevos.cerrado()).isFalse();
    }

    @Test
    void cadaPacienteTieneSuPropiaConversacion() {
        service.enviar("u1", "MEDICO", "para u1");
        service.enviar("u2", "MEDICO", "para u2");

        assertThat(service.consultar("u1", 0).mensajes()).hasSize(1);
        assertThat(service.consultar("u2", 0).mensajes()).hasSize(1);
    }

    @Test
    void mensajeVacioOSoloEspacios_seRechaza() {
        assertThatThrownBy(() -> service.enviar("u1", "MEDICO", "   "))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> service.enviar("u1", "MEDICO", null))
                .isInstanceOf(IllegalArgumentException.class);
        assertThat(service.consultar("u1", 0).mensajes()).isEmpty();
    }

    @Test
    void mensajeMuyLargo_seRechaza() {
        String largo = "a".repeat(ChatService.MAX_TEXTO + 1);
        assertThatThrownBy(() -> service.enviar("u1", "MEDICO", largo))
                .isInstanceOf(IllegalArgumentException.class);
        // el límite exacto sí se acepta
        service.enviar("u1", "MEDICO", "a".repeat(ChatService.MAX_TEXTO));
    }

    @Test
    void emisorDesconocidoOIdInvalido_seRechazan() {
        assertThatThrownBy(() -> service.enviar("u1", "ADMIN", "hola"))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> service.enviar("../x", "MEDICO", "hola"))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> service.consultar("u 1", 0))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void cerrar_borraElHistorialYBloqueaNuevosMensajes() {
        service.enviar("u1", "MEDICO", "hola");
        service.enviar("u1", "PACIENTE", "hola doctor");

        service.cerrar("u1");

        ConversacionDTO c = service.consultar("u1", 0);
        assertThat(c.cerrado()).isTrue();
        assertThat(c.mensajes()).isEmpty();
        assertThatThrownBy(() -> service.enviar("u1", "MEDICO", "¿sigue ahí?"))
                .isInstanceOf(IllegalStateException.class);
    }

    @Test
    void abrirDespuesDeCerrar_permiteChatNuevoSinReiniciarLosIds() {
        service.enviar("u1", "MEDICO", "uno");
        service.enviar("u1", "MEDICO", "dos");
        service.cerrar("u1");

        service.abrir("u1");
        MensajeChatDTO nuevo = service.enviar("u1", "PACIENTE", "chat nuevo");

        // quien ya había leído hasta el id 2 no se pierde el mensaje nuevo
        assertThat(nuevo.id()).isEqualTo(3);
        assertThat(service.consultar("u1", 2).mensajes()).extracting(MensajeChatDTO::texto)
                .containsExactly("chat nuevo");
        assertThat(service.consultar("u1", 0).cerrado()).isFalse();
    }

    @Test
    void historialLleno_seRechazaElMensajeSiguiente() {
        for (int i = 0; i < ChatService.MAX_MENSAJES; i++) {
            service.enviar("u1", "MEDICO", "m" + i);
        }
        assertThatThrownBy(() -> service.enviar("u1", "MEDICO", "uno más"))
                .isInstanceOf(IllegalStateException.class);
    }
}
