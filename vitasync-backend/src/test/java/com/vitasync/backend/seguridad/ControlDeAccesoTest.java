package com.vitasync.backend.seguridad;

import com.vitasync.backend.blackbox.RepositoriosEnMemoria;
import com.vitasync.backend.chat.ChatController;
import com.vitasync.backend.chat.ChatService;
import com.vitasync.backend.smartwatch.controller.SmartwatchController;
import com.vitasync.backend.smartwatch.service.SmartwatchService;
import com.vitasync.backend.usuarios.controller.UsuarioController;
import com.vitasync.backend.usuarios.dto.CrearUsuarioDTO;
import com.vitasync.backend.usuarios.dto.UsuarioDTO;
import com.vitasync.backend.usuarios.service.PinService;
import com.vitasync.backend.usuarios.service.UsuarioService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Control de acceso (Práctica 10 aplicada a VitaSync): nadie entra sin token y cada persona toca solo
 * sus cuentas. Se prueba el filtro REAL con los controladores reales; solo el verificador de tokens es
 * un doble (en producción valida tokens de Firebase Authentication).
 */
class ControlDeAccesoTest {

    private static final Map<String, Identidad> TOKENS = Map.of(
            "token-ana", new Identidad("uid-ana", "paciente"),
            "token-beto", new Identidad("uid-beto", "paciente"),
            "token-doctora", new Identidad("uid-doc", "medico"),
            "token-admin", new Identidad("uid-admin", "admin"));

    private MockMvc mvc;
    private UsuarioService usuarios;
    private SmartwatchService smartwatch;
    private String cuentaAna;
    private String cuentaBeto;

    @BeforeEach
    void preparar() {
        var repo = new RepositoriosEnMemoria.Usuarios();
        usuarios = new UsuarioService(Optional.of(repo));
        smartwatch = new SmartwatchService(Optional.of(new RepositoriosEnMemoria.Dispositivos()));
        VerificadorToken verificador = t -> Optional.ofNullable(TOKENS.get(t));
        mvc = MockMvcBuilders
                .standaloneSetup(
                        new UsuarioController(usuarios, new PinService(Optional.of(repo))),
                        new ChatController(new ChatService()),
                        new SmartwatchController(smartwatch))
                .addFilters(new ControlDeAcceso(verificador, usuarios, smartwatch))
                .build();
        cuentaAna = usuarios.crear(new CrearUsuarioDTO("Ana Pérez", "ana", List.of("pacientes")), "uid-ana").id();
        cuentaBeto = usuarios.crear(new CrearUsuarioDTO("Beto Ruiz", "beto", List.of("pacientes")), "uid-beto").id();
    }

    private static String bearer(String token) {
        return "Bearer " + token;
    }

    // ------------------------------------------------------------ autenticación

    @Test
    void sinToken_401() throws Exception {
        mvc.perform(get("/api/usuarios/" + cuentaAna)).andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.error").isNotEmpty());
        mvc.perform(get("/api/usuarios")).andExpect(status().isUnauthorized());
        mvc.perform(get("/api/chat/" + cuentaAna + "/mensajes")).andExpect(status().isUnauthorized());
    }

    @Test
    void tokenInvalido_o_malFormado_401() throws Exception {
        for (String cab : new String[]{"Bearer token-falso", "Bearer ", "Basic token-ana", "token-ana", ""}) {
            mvc.perform(get("/api/usuarios/" + cuentaAna).header("Authorization", cab))
                    .andExpect(status().isUnauthorized());
        }
    }

    @Test
    void firmwareUltima_esPublica() throws Exception {
        // no hay controlador de firmware en este montaje: lo que importa es que el filtro NO responda 401
        int estado = mvc.perform(get("/api/firmware/ultima")).andReturn().getResponse().getStatus();
        assertEquals(404, estado);
    }

    // ------------------------------------------------------------ autorización

    @Test
    void elDuenoLeSuCuenta_200() throws Exception {
        mvc.perform(get("/api/usuarios/" + cuentaAna).header("Authorization", bearer("token-ana")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.username").value("ana"));
    }

    @Test
    void ana_noPuedeLeerNiTocarLaCuentaDeBeto_403() throws Exception {
        String ana = bearer("token-ana");
        mvc.perform(get("/api/usuarios/" + cuentaBeto).header("Authorization", ana)).andExpect(status().isForbidden());
        mvc.perform(patch("/api/usuarios/" + cuentaBeto + "/deshabilitar").header("Authorization", ana)).andExpect(status().isForbidden());
        mvc.perform(delete("/api/usuarios/" + cuentaBeto).header("Authorization", ana)).andExpect(status().isForbidden());
        mvc.perform(post("/api/usuarios/" + cuentaBeto + "/pin/verificar").header("Authorization", ana)
                .contentType(MediaType.APPLICATION_JSON).content("{\"pin\":\"1234\"}")).andExpect(status().isForbidden());
        // y de verdad no se tocó nada
        UsuarioDTO beto = usuarios.obtener(cuentaBeto);
        assertTrue(beto.habilitado(), "la cuenta de Beto debe seguir habilitada");
    }

    @Test
    void cuentaInexistente_seResponde403_noRevelaQueNoExiste() throws Exception {
        mvc.perform(get("/api/usuarios/no-existe").header("Authorization", bearer("token-ana"))).andExpect(status().isForbidden());
    }

    @Test
    void chat_soloElDuenoOUnMedico() throws Exception {
        String cuerpo = "{\"emisor\":\"PACIENTE\",\"texto\":\"hola\"}";
        mvc.perform(post("/api/chat/" + cuentaAna + "/mensajes").header("Authorization", bearer("token-ana"))
                .contentType(MediaType.APPLICATION_JSON).content(cuerpo)).andExpect(status().isOk());
        mvc.perform(get("/api/chat/" + cuentaAna + "/mensajes").header("Authorization", bearer("token-beto")))
                .andExpect(status().isForbidden());
        mvc.perform(post("/api/chat/" + cuentaAna + "/cerrar").header("Authorization", bearer("token-beto")))
                .andExpect(status().isForbidden());
        mvc.perform(get("/api/chat/" + cuentaAna + "/mensajes").header("Authorization", bearer("token-doctora")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.mensajes.length()").value(1));
    }

    @Test
    void medico_noPuedeAdministrarCuentas_soloElChat() throws Exception {
        mvc.perform(delete("/api/usuarios/" + cuentaAna).header("Authorization", bearer("token-doctora")))
                .andExpect(status().isForbidden());
    }

    @Test
    void administrador_accedeATodo() throws Exception {
        mvc.perform(get("/api/usuarios/" + cuentaAna).header("Authorization", bearer("token-admin"))).andExpect(status().isOk());
        mvc.perform(get("/api/usuarios").header("Authorization", bearer("token-admin")))
                .andExpect(jsonPath("$.length()").value(2));
    }

    // ------------------------------------------------------------ listar y crear

    @Test
    void listar_devuelveSoloLasCuentasPropias() throws Exception {
        mvc.perform(get("/api/usuarios").header("Authorization", bearer("token-ana")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(1))
                .andExpect(jsonPath("$[0].username").value("ana"));
    }

    @Test
    void crear_asignaComoDuenoAQuienLaCrea_yNoAlQueDiga_elCuerpo() throws Exception {
        // el cuerpo intenta imponer un propietario: se ignora (el DTO ni siquiera tiene ese campo)
        mvc.perform(post("/api/usuarios").header("Authorization", bearer("token-ana"))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nombreCompleto\":\"Ana Dos\",\"username\":\"ana2\",\"grupos\":[],\"propietarioUid\":\"uid-beto\"}"))
                .andExpect(status().isOk());
        assertEquals(List.of("ana", "ana2"), usuarios.listarDe("uid-ana").stream().map(UsuarioDTO::username).sorted().toList());
        assertEquals(1, usuarios.listarDe("uid-beto").size(), "Beto no recibió la cuenta");
    }

    // ------------------------------------------------------------ clave de dispositivo (firmware)

    /** Conecta el reloj de la cuenta con el token de su dueño y devuelve la clave que entrega el servidor. */
    private String conectarReloj(String cuenta, String token) throws Exception {
        String json = mvc.perform(post("/api/smartwatch/connect?usuarioId=" + cuenta).header("Authorization", bearer(token)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.claveDispositivo").isNotEmpty())
                .andReturn().getResponse().getContentAsString();
        java.util.regex.Matcher m = java.util.regex.Pattern.compile("\"claveDispositivo\":\"([0-9a-f]+)\"").matcher(json);
        assertTrue(m.find(), "la respuesta trae la clave");
        return m.group(1);
    }

    @Test
    void firmware_conSuClave_puedeEnviarLecturas() throws Exception {
        String clave = conectarReloj(cuentaAna, "token-ana");
        mvc.perform(post("/api/smartwatch/sync?usuarioId=" + cuentaAna).header("X-Clave-Dispositivo", clave)
                        .contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isOk());
    }

    @Test
    void firmware_claveMala_o_ajena_401() throws Exception {
        String claveAna = conectarReloj(cuentaAna, "token-ana");
        conectarReloj(cuentaBeto, "token-beto");
        for (String clave : new String[]{"clave-inventada", "", claveAna.toUpperCase()}) {
            mvc.perform(post("/api/smartwatch/sync?usuarioId=" + cuentaAna).header("X-Clave-Dispositivo", clave)
                    .contentType(MediaType.APPLICATION_JSON).content("{}")).andExpect(status().isUnauthorized());
        }
        // la clave del reloj de Ana no sirve para la cuenta de Beto
        mvc.perform(post("/api/smartwatch/sync?usuarioId=" + cuentaBeto).header("X-Clave-Dispositivo", claveAna)
                .contentType(MediaType.APPLICATION_JSON).content("{}")).andExpect(status().isUnauthorized());
    }

    @Test
    void laClaveDeDispositivo_noAbreLoQueEsDeLasPersonas() throws Exception {
        String clave = conectarReloj(cuentaAna, "token-ana");
        // métricas, historial, estado y conectar siguen exigiendo token de persona
        mvc.perform(get("/api/smartwatch/metrics?usuarioId=" + cuentaAna).header("X-Clave-Dispositivo", clave))
                .andExpect(status().isUnauthorized());
        mvc.perform(post("/api/smartwatch/connect?usuarioId=" + cuentaAna).header("X-Clave-Dispositivo", clave))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void sync_conTokenDeOtraPersona_403_ySinNada_401() throws Exception {
        conectarReloj(cuentaAna, "token-ana");
        mvc.perform(post("/api/smartwatch/sync?usuarioId=" + cuentaAna).header("Authorization", bearer("token-beto"))
                .contentType(MediaType.APPLICATION_JSON).content("{}")).andExpect(status().isForbidden());
        mvc.perform(post("/api/smartwatch/sync?usuarioId=" + cuentaAna)
                .contentType(MediaType.APPLICATION_JSON).content("{}")).andExpect(status().isUnauthorized());
    }

    @Test
    void volverAConectar_cambiaLaClave_laAnteriorYaNoVale() throws Exception {
        String vieja = conectarReloj(cuentaAna, "token-ana");
        String nueva = conectarReloj(cuentaAna, "token-ana");
        assertTrue(!vieja.equals(nueva), "cada conexión entrega una clave nueva");
        mvc.perform(post("/api/smartwatch/sync?usuarioId=" + cuentaAna).header("X-Clave-Dispositivo", vieja)
                .contentType(MediaType.APPLICATION_JSON).content("{}")).andExpect(status().isUnauthorized());
        mvc.perform(post("/api/smartwatch/sync?usuarioId=" + cuentaAna).header("X-Clave-Dispositivo", nueva)
                .contentType(MediaType.APPLICATION_JSON).content("{}")).andExpect(status().isOk());
    }

    @Test
    void metricas_deUnaCuentaSinLecturas_responde204_yNoDatosInventados() throws Exception {
        mvc.perform(get("/api/smartwatch/metrics?usuarioId=" + cuentaAna).header("Authorization", bearer("token-ana")))
                .andExpect(status().isNoContent());
    }

    @Test
    void metricas_conUnaLecturaReal_laDevuelve() throws Exception {
        String clave = conectarReloj(cuentaAna, "token-ana");
        mvc.perform(post("/api/smartwatch/sync?usuarioId=" + cuentaAna).header("X-Clave-Dispositivo", clave)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"pasos\":777,\"calorias\":1,\"sueñoHoras\":7.0,\"frecuenciaCardiaca\":70,\"bateria\":50,\"timestamp\":\"2026-11-04T10:00:00Z\"}"))
                .andExpect(status().isOk());
        mvc.perform(get("/api/smartwatch/metrics?usuarioId=" + cuentaAna).header("Authorization", bearer("token-ana")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.pasos").value(777));
    }

    @Test
    void elEstado_nuncaVuelveAMostrarLaClave() throws Exception {
        conectarReloj(cuentaAna, "token-ana");
        mvc.perform(get("/api/smartwatch/status?usuarioId=" + cuentaAna).header("Authorization", bearer("token-ana")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.claveDispositivo").doesNotExist());
    }

    // ------------------------------------------------------------ validaciones del servidor (D-01, D-02)

    @Test
    void alta_conDatosVacios_400() throws Exception {
        String ana = bearer("token-ana");
        for (String cuerpo : new String[]{
                "{\"nombreCompleto\":\"\",\"username\":\"\",\"grupos\":[]}",
                "{}",
                "{\"nombreCompleto\":\"Ok Nombre\",\"username\":\"a b\",\"grupos\":[]}",
                "{\"nombreCompleto\":\"x\",\"username\":\"valido1\",\"grupos\":[]}"}) {
            mvc.perform(post("/api/usuarios").header("Authorization", ana).contentType(MediaType.APPLICATION_JSON).content(cuerpo))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").isNotEmpty());
        }
        assertEquals(1, usuarios.listarDe("uid-ana").size(), "no se creó ninguna cuenta nueva");
    }

    @Test
    void alta_conUsuarioRepetido_409_sinImportarMayusculas() throws Exception {
        mvc.perform(post("/api/usuarios").header("Authorization", bearer("token-beto")).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nombreCompleto\":\"Otra Ana\",\"username\":\"ANA\",\"grupos\":[]}"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.error").isNotEmpty());
    }
}
