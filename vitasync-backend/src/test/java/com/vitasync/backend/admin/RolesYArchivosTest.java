package com.vitasync.backend.admin;

import com.vitasync.backend.blackbox.RepositoriosEnMemoria;
import com.vitasync.backend.chat.ChatController;
import com.vitasync.backend.chat.ChatService;
import com.vitasync.backend.seguridad.ControlDeAcceso;
import com.vitasync.backend.seguridad.Identidad;
import com.vitasync.backend.seguridad.VerificadorToken;
import com.vitasync.backend.smartwatch.service.SmartwatchService;
import com.vitasync.backend.usuarios.dto.CrearUsuarioDTO;
import com.vitasync.backend.usuarios.service.UsuarioService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Práctica 7 dentro de VitaSync: roles asignados en lote por el administrador y archivos en el chat.
 * Controladores, servicios y filtro de seguridad REALES; solo el almacén de roles es en memoria.
 */
class RolesYArchivosTest {

    private static final Map<String, Identidad> TOKENS = Map.of(
            "token-admin", new Identidad("uid-admin", "admin"),
            "token-ana", new Identidad("uid-ana", "paciente"),
            "token-beto", new Identidad("uid-beto", "paciente"),
            "token-doc", new Identidad("uid-doc", "medico"));

    private static final byte[] PNG = {(byte) 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0};
    private static final byte[] PDF = "%PDF-1.4\n%fin".getBytes(StandardCharsets.US_ASCII);

    private MockMvc mvc;
    private RepositoriosEnMemoria.Roles roles;
    private String cuentaAna;

    @BeforeEach
    void preparar() {
        roles = new RepositoriosEnMemoria.Roles()
                .agregar("uid-admin", "admin@x.mx", "admin").agregar("uid-ana", "ana@x.mx", "paciente")
                .agregar("uid-beto", "beto@x.mx", "paciente").agregar("uid-doc", "doc@x.mx", "paciente");
        ChatService chat = new ChatService();
        UsuarioService usuarios = new UsuarioService(Optional.of(new RepositoriosEnMemoria.Usuarios()), List.of(chat));
        VerificadorToken verificador = t -> Optional.ofNullable(TOKENS.get(t));
        mvc = MockMvcBuilders.standaloneSetup(new RolesController(new RolesService(Optional.of(roles))), new ChatController(chat))
                .addFilters(new ControlDeAcceso(verificador, usuarios,
                        new SmartwatchService(Optional.of(new RepositoriosEnMemoria.Dispositivos()))))
                .build();
        cuentaAna = usuarios.crear(new CrearUsuarioDTO("Ana Pérez", "ana", List.of()), "uid-ana").id();
    }

    // ------------------------------------------------------------ roles

    private ResultActions asignar(String token, String json) throws Exception {
        return mvc.perform(put("/api/admin/roles").header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON).content(json));
    }

    @Test
    void elAdministradorAsignaVariosRolesDeUnSoloEnvio() throws Exception {
        asignar("token-admin", "{\"cambios\":[{\"uid\":\"uid-doc\",\"rol\":\"medico\"},{\"uid\":\"uid-beto\",\"rol\":\"medico\"}]}")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(2))
                .andExpect(jsonPath("$[0].rol").value("medico"));
        assertThat(roles.buscar("uid-doc").get().rol()).isEqualTo("medico");
        assertThat(roles.buscar("uid-beto").get().rol()).isEqualTo("medico");
        assertThat(roles.buscar("uid-ana").get().rol()).isEqualTo("paciente");
    }

    @Test
    void elAdministradorVeQuienExisteYSuRol() throws Exception {
        mvc.perform(get("/api/admin/personas").header("Authorization", "Bearer token-admin"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.length()").value(4))
                .andExpect(jsonPath("$[0].uid").value("uid-admin")).andExpect(jsonPath("$[0].rol").value("admin"));
    }

    @Test
    void pacienteYMedico_noPuedenAsignarRoles_403() throws Exception {
        String lote = "{\"cambios\":[{\"uid\":\"uid-beto\",\"rol\":\"medico\"}]}";
        asignar("token-ana", lote).andExpect(status().isForbidden());
        asignar("token-doc", lote).andExpect(status().isForbidden());
        mvc.perform(get("/api/admin/personas").header("Authorization", "Bearer token-ana")).andExpect(status().isForbidden());
        assertThat(roles.buscar("uid-beto").get().rol()).isEqualTo("paciente");
    }

    @Test
    void sinSesion_401() throws Exception {
        mvc.perform(put("/api/admin/roles").contentType(MediaType.APPLICATION_JSON).content("{}")).andExpect(status().isUnauthorized());
    }

    @Test
    void siUnCambioNoCumple_noSeAplicaNingunoDelLote() throws Exception {
        asignar("token-admin", "{\"cambios\":[{\"uid\":\"uid-ana\",\"rol\":\"medico\"},{\"uid\":\"uid-nadie\",\"rol\":\"medico\"}]}")
                .andExpect(status().isBadRequest());
        assertThat(roles.buscar("uid-ana").get().rol()).isEqualTo("paciente");
    }

    @Test
    void reglasDelLote_400() throws Exception {
        asignar("token-admin", "{\"cambios\":[]}").andExpect(status().isBadRequest());
        asignar("token-admin", "{}").andExpect(status().isBadRequest());
        asignar("token-admin", "{\"cambios\":[{\"uid\":\"uid-ana\",\"rol\":\"admin\"}]}").andExpect(status().isBadRequest());
        asignar("token-admin", "{\"cambios\":[{\"uid\":\"uid-ana\",\"rol\":\"dios\"}]}").andExpect(status().isBadRequest());
        asignar("token-admin", "{\"cambios\":[{\"uid\":\"uid-ana\",\"rol\":\"medico\"},{\"uid\":\"uid-ana\",\"rol\":\"paciente\"}]}")
                .andExpect(status().isBadRequest());
        asignar("token-admin", "{\"cambios\":[{\"uid\":\"uid-admin\",\"rol\":\"paciente\"}]}").andExpect(status().isBadRequest());
        assertThat(roles.buscar("uid-admin").get().rol()).isEqualTo("admin");
    }

    @Test
    void loteMuyGrande_400() throws Exception {
        StringBuilder sb = new StringBuilder("{\"cambios\":[");
        for (int i = 0; i <= RolesService.MAX_LOTE; i++) sb.append(i > 0 ? "," : "").append("{\"uid\":\"u").append(i).append("\",\"rol\":\"medico\"}");
        asignar("token-admin", sb.append("]}").toString()).andExpect(status().isBadRequest());
    }

    @Test
    void sinGestor_503() throws Exception {
        MockMvc sin = MockMvcBuilders.standaloneSetup(new RolesController(new RolesService(Optional.empty()))).build();
        sin.perform(get("/api/admin/personas")).andExpect(status().isServiceUnavailable());
    }

    // ------------------------------------------------------------ archivos del chat

    private static String json(String emisor, String nombre, String tipo, byte[] bytes) {
        return "{\"emisor\":\"" + emisor + "\",\"nombre\":\"" + nombre + "\",\"tipo\":\"" + tipo
                + "\",\"contenidoBase64\":\"" + Base64.getEncoder().encodeToString(bytes) + "\"}";
    }

    private ResultActions subir(String token, String cuerpo) throws Exception {
        return mvc.perform(post("/api/chat/" + cuentaAna + "/archivos").header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON).content(cuerpo));
    }

    @Test
    void enviarUnArchivo_apareceEnLaConversacionYSeDescargaIgual() throws Exception {
        subir("token-ana", json("PACIENTE", "análisis.pdf", "application/pdf", PDF)).andExpect(status().isOk())
                .andExpect(jsonPath("$.archivo.nombre").value("análisis.pdf"))
                .andExpect(jsonPath("$.archivo.tipo").value("application/pdf"))
                .andExpect(jsonPath("$.archivo.tamano").value(PDF.length));
        mvc.perform(get("/api/chat/" + cuentaAna + "/mensajes?desde=0").header("Authorization", "Bearer token-doc"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.mensajes[0].archivo.nombre").value("análisis.pdf"));
        mvc.perform(get("/api/chat/" + cuentaAna + "/archivos/1").header("Authorization", "Bearer token-doc"))
                .andExpect(status().isOk()).andExpect(content().bytes(PDF))
                .andExpect(header().string("X-Content-Type-Options", "nosniff"))
                .andExpect(header().string("Content-Disposition", org.hamcrest.Matchers.startsWith("attachment")));
    }

    @Test
    void imagenYTextoSonValidos() throws Exception {
        subir("token-ana", json("PACIENTE", "foto.png", "image/png", PNG)).andExpect(status().isOk());
        subir("token-doc", json("MEDICO", "nota.txt", "text/plain", "Tomar agua ñ".getBytes(StandardCharsets.UTF_8))).andExpect(status().isOk());
    }

    @Test
    void tipoNoPermitido_400() throws Exception {
        subir("token-ana", json("PACIENTE", "virus.exe", "application/x-msdownload", new byte[]{'M', 'Z', 1, 2})).andExpect(status().isBadRequest());
        subir("token-ana", json("PACIENTE", "pagina.html", "text/html", "<script>1</script>".getBytes())).andExpect(status().isBadRequest());
    }

    @Test
    void elContenidoDebeSerDelTipoDeclarado_400() throws Exception {
        // Un ejecutable disfrazado de PNG, un PDF que no lo es y un «texto» con bytes nulos.
        subir("token-ana", json("PACIENTE", "falso.png", "image/png", new byte[]{'M', 'Z', 0, 0, 0, 0, 0, 0, 0, 0})).andExpect(status().isBadRequest());
        subir("token-ana", json("PACIENTE", "falso.pdf", "application/pdf", "hola mundo".getBytes())).andExpect(status().isBadRequest());
        subir("token-ana", json("PACIENTE", "falso.txt", "text/plain", new byte[]{'a', 0, 'b'})).andExpect(status().isBadRequest());
    }

    @Test
    void tamanoVacioYBase64Invalido_400() throws Exception {
        byte[] grande = new byte[ChatService.MAX_ARCHIVO_BYTES + 1];
        System.arraycopy(PDF, 0, grande, 0, PDF.length);
        subir("token-ana", json("PACIENTE", "grande.pdf", "application/pdf", grande)).andExpect(status().isBadRequest());
        subir("token-ana", json("PACIENTE", "vacio.pdf", "application/pdf", new byte[0])).andExpect(status().isBadRequest());
        subir("token-ana", "{\"emisor\":\"PACIENTE\",\"nombre\":\"a.pdf\",\"tipo\":\"application/pdf\",\"contenidoBase64\":\"%%%\"}")
                .andExpect(status().isBadRequest());
    }

    @Test
    void elNombreSeLimpia_sinCarpetasNiSimbolosPeligrosos() throws Exception {
        subir("token-ana", json("PACIENTE", "..\\\\..\\\\carpeta/<img>informe?.pdf", "application/pdf", PDF)).andExpect(status().isOk())
                .andExpect(jsonPath("$.archivo.nombre").value("_img_informe_.pdf"));
        subir("token-ana", json("PACIENTE", "..", "application/pdf", PDF)).andExpect(status().isBadRequest());
    }

    @Test
    void elCupoDeLaConversacionSeRespeta_409() throws Exception {
        for (int i = 0; i < ChatService.MAX_ARCHIVOS; i++) {
            subir("token-ana", json("PACIENTE", "f" + i + ".pdf", "application/pdf", PDF)).andExpect(status().isOk());
        }
        subir("token-ana", json("PACIENTE", "uno-mas.pdf", "application/pdf", PDF)).andExpect(status().isConflict());
    }

    @Test
    void archivoDeOtraCuenta_403_yInexistente_404() throws Exception {
        subir("token-ana", json("PACIENTE", "a.pdf", "application/pdf", PDF)).andExpect(status().isOk());
        mvc.perform(get("/api/chat/" + cuentaAna + "/archivos/1").header("Authorization", "Bearer token-beto")).andExpect(status().isForbidden());
        subir("token-beto", json("PACIENTE", "b.pdf", "application/pdf", PDF)).andExpect(status().isForbidden());
        mvc.perform(get("/api/chat/" + cuentaAna + "/archivos/99").header("Authorization", "Bearer token-ana")).andExpect(status().isNotFound());
    }

    @Test
    void alCerrarElChat_losArchivosSeBorran() throws Exception {
        subir("token-ana", json("PACIENTE", "a.pdf", "application/pdf", PDF)).andExpect(status().isOk());
        mvc.perform(post("/api/chat/" + cuentaAna + "/cerrar").header("Authorization", "Bearer token-ana")).andExpect(status().isOk());
        mvc.perform(get("/api/chat/" + cuentaAna + "/archivos/1").header("Authorization", "Bearer token-ana")).andExpect(status().isNotFound());
    }

    @Test
    void unMensajeDeTexto_sigueSinArchivo() throws Exception {
        mvc.perform(post("/api/chat/" + cuentaAna + "/mensajes").header("Authorization", "Bearer token-ana")
                        .contentType(MediaType.APPLICATION_JSON).content("{\"emisor\":\"PACIENTE\",\"texto\":\"hola\"}"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.archivo").doesNotExist());
    }
}
