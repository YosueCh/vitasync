package com.vitasync.backend.contactos;

import com.vitasync.backend.blackbox.RepositoriosEnMemoria;
import com.vitasync.backend.seguridad.ControlDeAcceso;
import com.vitasync.backend.seguridad.Identidad;
import com.vitasync.backend.seguridad.VerificadorToken;
import com.vitasync.backend.usuarios.dto.CrearUsuarioDTO;
import com.vitasync.backend.usuarios.service.UsuarioService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Contactos de emergencia (Actividad 1 dentro de VitaSync): validación en el servidor, límites, borrado y control
 * de acceso. Se prueba el controlador, el servicio y el filtro de seguridad REALES; solo el repositorio es en memoria.
 */
class ContactosTest {

    private static final Map<String, Identidad> TOKENS = Map.of(
            "token-ana", new Identidad("uid-ana", "paciente"),
            "token-beto", new Identidad("uid-beto", "paciente"));

    private MockMvc mvc;
    private ContactoService contactos;
    private UsuarioService usuarios;
    private String cuentaAna;
    private String cuentaBeto;

    @BeforeEach
    void preparar() {
        contactos = new ContactoService(Optional.of(new RepositoriosEnMemoria.Contactos()));
        usuarios = new UsuarioService(Optional.of(new RepositoriosEnMemoria.Usuarios()), List.of(contactos));
        VerificadorToken verificador = t -> Optional.ofNullable(TOKENS.get(t));
        mvc = MockMvcBuilders.standaloneSetup(new ContactoController(contactos))
                .addFilters(new ControlDeAcceso(verificador, usuarios,
                        new com.vitasync.backend.smartwatch.service.SmartwatchService(Optional.of(new RepositoriosEnMemoria.Dispositivos()))))
                .build();
        cuentaAna = usuarios.crear(new CrearUsuarioDTO("Ana Pérez", "ana", List.of()), "uid-ana").id();
        cuentaBeto = usuarios.crear(new CrearUsuarioDTO("Beto Ruiz", "beto", List.of()), "uid-beto").id();
    }

    private static String cuerpo(String nombre, String telefono, String relacion) {
        return "{\"nombre\":\"" + nombre + "\",\"telefono\":\"" + telefono + "\",\"relacion\":\"" + relacion + "\"}";
    }

    private org.springframework.test.web.servlet.ResultActions crear(String cuenta, String token, String json) throws Exception {
        return mvc.perform(post("/api/contactos?usuarioId=" + cuenta).header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON).content(json));
    }

    // ------------------------------------------------------------ capturar, guardar y consultar

    @Test
    void crearYConsultar_seGuardaConTelefonoNormalizado() throws Exception {
        crear(cuentaAna, "token-ana", cuerpo("Mamá", "(442) 123-4567", "Familiar"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").isNotEmpty())
                .andExpect(jsonPath("$.telefono").value("4421234567"))
                .andExpect(jsonPath("$.relacion").value("Familiar"));

        mvc.perform(get("/api/contactos?usuarioId=" + cuentaAna).header("Authorization", "Bearer token-ana"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(1))
                .andExpect(jsonPath("$[0].nombre").value("Mamá"));
    }

    @Test
    void telefonoConMasYLadaInternacional_esValido() throws Exception {
        crear(cuentaAna, "token-ana", cuerpo("Dra. López", "+52 442 765 4321", "Médico"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.telefono").value("+524427654321"));
    }

    @Test
    void sinRelacion_quedaComoOtro() throws Exception {
        crear(cuentaAna, "token-ana", "{\"nombre\":\"Vecino\",\"telefono\":\"4421112233\"}")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.relacion").value("Otro"));
    }

    @Test
    void listarSinContactos_devuelveListaVacia_noError() throws Exception {
        mvc.perform(get("/api/contactos?usuarioId=" + cuentaAna).header("Authorization", "Bearer token-ana"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(0));
    }

    // ------------------------------------------------------------ validación en el servidor

    @Test
    void datosInvalidos_400_yNoSeGuardaNada() throws Exception {
        String larga = "x".repeat(31);
        for (String json : new String[]{
                cuerpo("", "4421234567", "Familiar"),                    // nombre vacío
                cuerpo("A", "4421234567", "Familiar"),                   // nombre de 1 letra
                cuerpo("Mamá", "", "Familiar"),                          // sin teléfono
                cuerpo("Mamá", "442123", "Familiar"),                    // muy corto
                cuerpo("Mamá", "4421234567890123", "Familiar"),          // muy largo
                cuerpo("Mamá", "442-ABC-4567", "Familiar"),              // con letras
                cuerpo("Mamá", "4421234567", larga),                     // relación demasiado larga
                "{}"}) {
            crear(cuentaAna, "token-ana", json).andExpect(status().isBadRequest()).andExpect(jsonPath("$.error").isNotEmpty());
        }
        assertThat(contactos.listar(cuentaAna)).isEmpty();
    }

    @Test
    void telefonoRepetido_409_aunqueCambieElFormato() throws Exception {
        crear(cuentaAna, "token-ana", cuerpo("Mamá", "442 123 4567", "Familiar")).andExpect(status().isOk());

        crear(cuentaAna, "token-ana", cuerpo("Otra mamá", "(442)123-4567", "Familiar"))
                .andExpect(status().isConflict()).andExpect(jsonPath("$.error").isNotEmpty());

        assertThat(contactos.listar(cuentaAna)).hasSize(1);
    }

    @Test
    void mismoTelefonoEnOtraCuenta_noEsRepetido() throws Exception {
        crear(cuentaAna, "token-ana", cuerpo("Mamá", "4421234567", "Familiar")).andExpect(status().isOk());
        crear(cuentaBeto, "token-beto", cuerpo("Mamá", "4421234567", "Familiar")).andExpect(status().isOk());
    }

    @Test
    void maximoDeCincoContactos_elSextoSeRechaza() throws Exception {
        for (int i = 0; i < ContactoService.MAX_POR_CUENTA; i++) {
            crear(cuentaAna, "token-ana", cuerpo("Contacto " + i, "44211122" + (10 + i), "Otro")).andExpect(status().isOk());
        }

        crear(cuentaAna, "token-ana", cuerpo("De más", "4429998877", "Otro"))
                .andExpect(status().isConflict()).andExpect(jsonPath("$.error").value(org.hamcrest.Matchers.containsString("5")));

        assertThat(contactos.listar(cuentaAna)).hasSize(ContactoService.MAX_POR_CUENTA);
    }

    // ------------------------------------------------------------ eliminar

    @Test
    void eliminar_quitaElContacto_yUnoInexistenteDa404() throws Exception {
        String id = contactos.crear(cuentaAna, new CrearContactoDTO("Mamá", "4421234567", "Familiar")).id();

        mvc.perform(delete("/api/contactos/" + id + "?usuarioId=" + cuentaAna).header("Authorization", "Bearer token-ana"))
                .andExpect(status().isOk());
        assertThat(contactos.listar(cuentaAna)).isEmpty();

        mvc.perform(delete("/api/contactos/" + id + "?usuarioId=" + cuentaAna).header("Authorization", "Bearer token-ana"))
                .andExpect(status().isNotFound());
    }

    @Test
    void eliminarLaCuenta_borraTambienSusContactos_sinTocarLosDeOtra() {
        contactos.crear(cuentaAna, new CrearContactoDTO("Mamá", "4421234567", "Familiar"));
        contactos.crear(cuentaBeto, new CrearContactoDTO("Papá", "4427654321", "Familiar"));

        usuarios.eliminar(cuentaAna);

        assertThat(contactos.listar(cuentaAna)).isEmpty();
        assertThat(contactos.listar(cuentaBeto)).hasSize(1);
    }

    // ------------------------------------------------------------ control de acceso

    @Test
    void sinToken_401() throws Exception {
        mvc.perform(get("/api/contactos?usuarioId=" + cuentaAna)).andExpect(status().isUnauthorized());
        mvc.perform(post("/api/contactos?usuarioId=" + cuentaAna).contentType(MediaType.APPLICATION_JSON)
                .content(cuerpo("Mamá", "4421234567", "Familiar"))).andExpect(status().isUnauthorized());
    }

    @Test
    void beto_noPuedeVerCrearNiEliminarContactosDeAna_403() throws Exception {
        String id = contactos.crear(cuentaAna, new CrearContactoDTO("Mamá", "4421234567", "Familiar")).id();

        mvc.perform(get("/api/contactos?usuarioId=" + cuentaAna).header("Authorization", "Bearer token-beto"))
                .andExpect(status().isForbidden());
        crear(cuentaAna, "token-beto", cuerpo("Intruso", "4420000000", "Otro")).andExpect(status().isForbidden());
        mvc.perform(delete("/api/contactos/" + id + "?usuarioId=" + cuentaAna).header("Authorization", "Bearer token-beto"))
                .andExpect(status().isForbidden());

        assertThat(contactos.listar(cuentaAna)).extracting(ContactoDTO::nombre).containsExactly("Mamá");
    }
}
