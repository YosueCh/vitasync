package com.vitasync.backend.whitebox;

import com.vitasync.backend.blackbox.RepositoriosEnMemoria;
import com.vitasync.backend.config.CorsConfig;
import com.vitasync.backend.config.ManejadorDeErrores;
import com.vitasync.backend.contactos.ContactoController;
import com.vitasync.backend.contactos.ContactoService;
import com.vitasync.backend.seguridad.ControlDeAcceso;
import com.vitasync.backend.seguridad.Identidad;
import com.vitasync.backend.seguridad.IdentificadorValido;
import com.vitasync.backend.seguridad.VerificadorToken;
import com.vitasync.backend.smartwatch.service.SmartwatchService;
import com.vitasync.backend.usuarios.dto.CrearUsuarioDTO;
import com.vitasync.backend.usuarios.service.UsuarioService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * PRÁCTICA 11 · Fase 3 · Pruebas de caja blanca de los errores HTTP.
 *
 * Cubre las ramas de {@link ManejadorDeErrores}, {@link IdentificadorValido} y del filtro de acceso que la matriz HTTP
 * contra el servidor real marcó como defectos: pila de Java en las respuestas (WB-HALLAZGO-5), 500 con ids que
 * Firestore rechaza (WB-HALLAZGO-4) y forma de error distinta según quién lo emite (WB-HALLAZGO-6).
 */
class ErroresHttpWhiteBoxTest {

    /** Controlador de laboratorio que lanza a propósito cada tipo de excepción. */
    @RestController
    static class Provocador {
        @GetMapping("/api/prueba/inesperada")
        String inesperada() {
            throw new IllegalStateException("clase interna X con datos de /ruta/secreta");
        }

        @GetMapping("/api/prueba/argumento")
        String argumento() {
            throw new IllegalArgumentException("Path should point to a Document, but got a/b");
        }
    }

    private static final Map<String, Identidad> TOKENS = Map.of("token-ana", new Identidad("uid-ana", "paciente"));

    private MockMvc mvc;
    private String cuentaAna;

    @BeforeEach
    void preparar() {
        var contactos = new ContactoService(Optional.of(new RepositoriosEnMemoria.Contactos()));
        var reloj = new SmartwatchService(Optional.of(new RepositoriosEnMemoria.Dispositivos()));
        var usuarios = new UsuarioService(Optional.of(new RepositoriosEnMemoria.Usuarios()), List.of(contactos));
        VerificadorToken verificador = t -> Optional.ofNullable(TOKENS.get(t));
        mvc = MockMvcBuilders.standaloneSetup(new ContactoController(contactos), new Provocador())
                .setControllerAdvice(new ManejadorDeErrores())
                .addFilters(CorsConfig.nuevoFiltro(), new ControlDeAcceso(verificador, usuarios, reloj))
                .build();
        cuentaAna = usuarios.crear(new CrearUsuarioDTO("Ana Pérez", "ana", List.of()), "uid-ana").id();
    }

    // ---------------------------------------------------------------- IdentificadorValido (decisión compuesta, valores límite)

    @ParameterizedTest(name = "«{0}» es válido")
    @ValueSource(strings = {"a", "A", "9", "_", "-", "uid-ana", "ca44a852-0a9b-4e32-86e4-1db4a82f4e08", "x_y-Z_9",
            "_a", "a_", "__a", "a__", "___"})
    void identificadoresValidos(String id) {
        assertThat(IdentificadorValido.esValido(id)).isTrue();
    }

    @ParameterizedTest(name = "«{0}» NO es válido")
    @ValueSource(strings = {"", " ", "a/b", "a b", "a.b", "a\\b", "ñ", "id%20x", "a?b=c", "<script>", "__reservado__", "__x__", "____"})
    void identificadoresInvalidos(String id) {
        assertThat(IdentificadorValido.esValido(id)).isFalse();
    }

    @Test
    void identificadorNulo_noEsValido() {
        assertThat(IdentificadorValido.esValido(null)).isFalse();
    }

    @ParameterizedTest(name = "{0} caracteres → {1}")
    @CsvSource({"1,true", "63,true", "64,true", "65,false", "2000,false"})
    void longitudDelIdentificador_valoresLimite(int largo, boolean esperado) {
        assertThat(IdentificadorValido.esValido("a".repeat(largo))).isEqualTo(esperado);
    }

    // ---------------------------------------------------------------- Filtro de acceso: id inválido → 400, no 500 (HALLAZGO-4)

    @ParameterizedTest(name = "usuarioId «{0}» → 400")
    @ValueSource(strings = {"a%2Fb", "__reservado__", "a%20b", "%3Cscript%3E"})
    void idInvalidoEnLaUrl_da400_yNoLlegaALaBaseDeDatos(String id) throws Exception {
        mvc.perform(get("/api/contactos?usuarioId=" + id).header("Authorization", "Bearer token-ana"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("Identificador de cuenta inválido."));
    }

    @Test
    void idDe2000Caracteres_da400() throws Exception {
        mvc.perform(get("/api/contactos?usuarioId=" + "x".repeat(2000)).header("Authorization", "Bearer token-ana"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void sinToken_sigueSiendo401_antesQueLaValidacionDelId() throws Exception {
        // Orden de las comprobaciones: autenticación (401) → validación del id (400) → autorización (403).
        mvc.perform(get("/api/contactos?usuarioId=a%2Fb")).andExpect(status().isUnauthorized());
    }

    @Test
    void idValidoPeroAjeno_sigueSiendo403_noConfundirConElIdInvalido() throws Exception {
        mvc.perform(get("/api/contactos?usuarioId=cuenta-de-otra-persona").header("Authorization", "Bearer token-ana"))
                .andExpect(status().isForbidden());
    }

    // ---------------------------------------------------------------- ManejadorDeErrores: forma única, sin pila (HALLAZGOS 5 y 6)

    @Test
    void excepcionNoPrevista_da500ConMensajeGenerico_sinPilaNiDetalleInterno() throws Exception {
        String cuerpo = mvc.perform(get("/api/prueba/inesperada"))
                .andExpect(status().isInternalServerError())
                .andExpect(jsonPath("$.error").value("Ocurrió un error en el servidor. Inténtalo de nuevo más tarde."))
                .andReturn().getResponse().getContentAsString(java.nio.charset.StandardCharsets.UTF_8);
        assertThat(cuerpo).doesNotContain("trace", "IllegalStateException", "clase interna", "/ruta/secreta", "at com.vitasync");
        assertThat(cuerpo).isEqualTo("{\"error\":\"Ocurrió un error en el servidor. Inténtalo de nuevo más tarde.\"}");
    }

    @Test
    void argumentoInvalido_da400SinRepetirElMensajeInternoDeFirestore() throws Exception {
        String cuerpo = mvc.perform(get("/api/prueba/argumento"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("La petición no es válida."))
                .andReturn().getResponse().getContentAsString(java.nio.charset.StandardCharsets.UTF_8);
        assertThat(cuerpo).doesNotContain("Path should point", "a/b");
    }

    @Test
    void jsonMalFormado_da400ConLaMismaForma() throws Exception {
        String cuerpo = mvc.perform(post("/api/contactos?usuarioId=" + cuentaAna).header("Authorization", "Bearer token-ana")
                        .contentType(MediaType.APPLICATION_JSON).content("esto no es json"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("La petición no es válida."))
                .andReturn().getResponse().getContentAsString(java.nio.charset.StandardCharsets.UTF_8);
        assertThat(cuerpo).doesNotContain("trace", "HttpMessageNotReadableException", "Unexpected character");
    }

    @Test
    void faltaUnParametroObligatorio_da400() throws Exception {
        mvc.perform(get("/api/contactos").header("Authorization", "Bearer token-ana"))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.error").exists());
    }

    @Test
    void metodoNoPermitido_da405() throws Exception {
        mvc.perform(patch("/api/contactos?usuarioId=" + cuentaAna).header("Authorization", "Bearer token-ana"))
                .andExpect(status().isMethodNotAllowed())
                .andExpect(jsonPath("$.error").value("Ese método no está permitido en esta ruta."));
    }

    @Test
    void tipoDeContenidoNoSoportado_da415() throws Exception {
        mvc.perform(post("/api/contactos?usuarioId=" + cuentaAna).header("Authorization", "Bearer token-ana")
                        .contentType(MediaType.TEXT_PLAIN).content("hola"))
                .andExpect(status().isUnsupportedMediaType())
                .andExpect(jsonPath("$.error").value("El tipo de contenido no es compatible."));
    }

    @ParameterizedTest(name = "estado {0} → mensaje en español")
    @CsvSource({"400,La petición no es válida.", "404,No existe ese recurso.", "405,Ese método no está permitido en esta ruta.",
            "406,No se puede responder en el formato pedido.", "415,El tipo de contenido no es compatible.",
            "500,Ocurrió un error en el servidor. Inténtalo de nuevo más tarde.", "503,El servicio no está disponible por ahora.",
            "418,No se pudo completar la petición."})
    void mensajesPorEstado(int estado, String esperado) throws Exception {
        var metodo = ManejadorDeErrores.class.getDeclaredMethod("mensaje", int.class);
        metodo.setAccessible(true);
        assertThat(metodo.invoke(null, estado)).isEqualTo(esperado);
    }

    // ---------------------------------------------------------------- Códigos de éxito: 201 al crear, 204 al eliminar

    @Test
    void crear_da201ConElRecursoCreado() throws Exception {
        mvc.perform(post("/api/contactos?usuarioId=" + cuentaAna).header("Authorization", "Bearer token-ana")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nombre\":\"Mamá\",\"telefono\":\"4421234567\",\"relacion\":\"Familiar\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id").isNotEmpty())
                .andExpect(jsonPath("$.telefono").value("4421234567"));
    }

    @Test
    void eliminar_da204SinCuerpo_yLaSegundaVezDa404() throws Exception {
        String id = mvc.perform(post("/api/contactos?usuarioId=" + cuentaAna).header("Authorization", "Bearer token-ana")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nombre\":\"Mamá\",\"telefono\":\"4421234567\",\"relacion\":\"Familiar\"}"))
                .andReturn().getResponse().getContentAsString().replaceAll(".*\"id\":\"([^\"]+)\".*", "$1");
        mvc.perform(delete("/api/contactos/" + id + "?usuarioId=" + cuentaAna).header("Authorization", "Bearer token-ana"))
                .andExpect(status().isNoContent()).andExpect(content().string(""));
        mvc.perform(delete("/api/contactos/" + id + "?usuarioId=" + cuentaAna).header("Authorization", "Bearer token-ana"))
                .andExpect(status().isNotFound());
    }
}
