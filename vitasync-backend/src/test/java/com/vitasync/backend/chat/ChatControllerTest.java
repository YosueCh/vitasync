package com.vitasync.backend.chat;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** Contrato HTTP del chat: lo que la app móvil envía y recibe por la URL del backend. */
class ChatControllerTest {

    private MockMvc mvc;

    @BeforeEach
    void preparar() {
        mvc = MockMvcBuilders.standaloneSetup(new ChatController(new ChatService())).build();
    }

    private void enviar(String emisor, String texto) throws Exception {
        mvc.perform(post("/api/chat/ana1/mensajes")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"emisor\":\"" + emisor + "\",\"texto\":\"" + texto + "\"}"))
                .andExpect(status().isOk());
    }

    @Test
    void enviarYConsultar_devuelveElMensajeConSuEmisor() throws Exception {
        enviar("MEDICO", "Buenos días");

        mvc.perform(get("/api/chat/ana1/mensajes?desde=0"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.cerrado").value(false))
                .andExpect(jsonPath("$.mensajes.length()").value(1))
                .andExpect(jsonPath("$.mensajes[0].id").value(1))
                .andExpect(jsonPath("$.mensajes[0].emisor").value("MEDICO"))
                .andExpect(jsonPath("$.mensajes[0].texto").value("Buenos días"))
                .andExpect(jsonPath("$.mensajes[0].hora").isNotEmpty());
    }

    @Test
    void consultarConDesde_noRepiteMensajesYaLeidos() throws Exception {
        enviar("MEDICO", "uno");
        enviar("PACIENTE", "dos");

        mvc.perform(get("/api/chat/ana1/mensajes?desde=1"))
                .andExpect(jsonPath("$.mensajes.length()").value(1))
                .andExpect(jsonPath("$.mensajes[0].texto").value("dos"));
    }

    @Test
    void mensajeVacio_devuelve400ConMensajeParaElUsuario() throws Exception {
        mvc.perform(post("/api/chat/ana1/mensajes")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"emisor\":\"MEDICO\",\"texto\":\"   \"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("El mensaje no puede estar vacío."));
    }

    @Test
    void alCerrarElPaciente_seBorraTodoYElMedicoRecibe409() throws Exception {
        enviar("MEDICO", "hola");
        enviar("PACIENTE", "hola doctor");

        mvc.perform(post("/api/chat/ana1/cerrar")).andExpect(status().isOk());

        mvc.perform(get("/api/chat/ana1/mensajes?desde=0"))
                .andExpect(jsonPath("$.cerrado").value(true))
                .andExpect(jsonPath("$.mensajes.length()").value(0));
        mvc.perform(post("/api/chat/ana1/mensajes")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"emisor\":\"MEDICO\",\"texto\":\"¿sigue ahí?\"}"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.error").value("El paciente cerró el chat."));
    }

    @Test
    void abrirDespuesDeCerrar_permiteConversarDeNuevo() throws Exception {
        enviar("MEDICO", "hola");
        mvc.perform(post("/api/chat/ana1/cerrar")).andExpect(status().isOk());
        mvc.perform(post("/api/chat/ana1/abrir")).andExpect(status().isOk());

        enviar("PACIENTE", "chat nuevo");

        mvc.perform(get("/api/chat/ana1/mensajes?desde=1"))
                .andExpect(jsonPath("$.cerrado").value(false))
                .andExpect(jsonPath("$.mensajes[0].texto").value("chat nuevo"));
    }
}
