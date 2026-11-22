package com.vitasync.backend.whitebox;

import com.vitasync.backend.admin.InvitacionesController;
import com.vitasync.backend.admin.InvitacionesService;
import com.vitasync.backend.admin.RolesController;
import com.vitasync.backend.admin.RolesService;
import com.vitasync.backend.config.ManejadorDeErrores;
import com.vitasync.backend.contactos.ContactoController;
import com.vitasync.backend.contactos.ContactoService;
import com.vitasync.backend.firmware.FirmwareController;
import com.vitasync.backend.firmware.FirmwareService;
import com.vitasync.backend.metas.MetasController;
import com.vitasync.backend.metas.MetasService;
import com.vitasync.backend.seguridad.ControlDeAcceso;
import com.vitasync.backend.seguridad.Identidad;
import com.vitasync.backend.smartwatch.controller.SmartwatchController;
import com.vitasync.backend.smartwatch.service.SmartwatchService;
import com.vitasync.backend.usuarios.controller.UsuarioController;
import com.vitasync.backend.usuarios.service.PinService;
import com.vitasync.backend.usuarios.service.UsuarioService;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.util.Optional;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * PRÁCTICA 11 · Fase 3 · Rama «el servicio no está disponible» de CADA controlador (decisión isDisponible() == false).
 *
 * Sin credenciales de Firebase todos los servicios se construyen con Optional.empty(). Un controlador bien hecho
 * contesta 503 con {"error": ...}; si se le olvida la comprobación, la excepción sube y el cliente ve un 500.
 */
class ControladoresSinFirebaseWhiteBoxTest {

    private final MockMvc mvc;

    ControladoresSinFirebaseWhiteBoxTest() {
        var usuarios = new UsuarioService(Optional.empty());
        mvc = MockMvcBuilders.standaloneSetup(
                        new UsuarioController(usuarios, new PinService(Optional.empty())),
                        new ContactoController(new ContactoService(Optional.empty())),
                        new MetasController(new MetasService(Optional.empty())),
                        new InvitacionesController(new InvitacionesService(Optional.empty(), Optional.empty())),
                        new RolesController(new RolesService(Optional.empty())),
                        new SmartwatchController(new SmartwatchService(Optional.empty())),
                        new FirmwareController(new FirmwareService(Optional.empty())))
                .setControllerAdvice(new ManejadorDeErrores())
                .build();
    }

    private static MockHttpServletRequestBuilder conCuerpo(MockHttpServletRequestBuilder b, String json) {
        return b.contentType(MediaType.APPLICATION_JSON).content(json);
    }

    @ParameterizedTest(name = "{0} {1} → 503")
    @CsvSource({
            "GET,/api/contactos?usuarioId=u1",
            "DELETE,/api/contactos/c1?usuarioId=u1",
            "GET,/api/metas?usuarioId=u1",
            "GET,/api/admin/invitaciones",
            "GET,/api/admin/personas",
            "GET,/api/smartwatch/status?usuarioId=u1",
            "POST,/api/smartwatch/connect?usuarioId=u1",
            "GET,/api/smartwatch/metrics?usuarioId=u1",
            "GET,/api/smartwatch/historial?usuarioId=u1",
            "GET,/api/firmware/estado?usuarioId=u1",
            "POST,/api/firmware/solicitar?usuarioId=u1",
            "POST,/api/firmware/aplicar?usuarioId=u1&version=v2",
            "GET,/api/usuarios/u1",
            "PATCH,/api/usuarios/u1/habilitar",
            "PATCH,/api/usuarios/u1/deshabilitar",
            "DELETE,/api/usuarios/u1",
            "POST,/api/usuarios/u1/login"})
    void sinFirebase_responde503ConUnMensaje(String metodo, String ruta) throws Exception {
        MockHttpServletRequestBuilder b = switch (metodo) {
            case "GET" -> get(ruta);
            case "POST" -> post(ruta);
            case "PATCH" -> patch(ruta);
            case "DELETE" -> delete(ruta);
            default -> throw new IllegalArgumentException(metodo);
        };
        mvc.perform(b).andExpect(status().isServiceUnavailable()).andExpect(jsonPath("$.error").isNotEmpty());
    }

    @Test
    void firmwareOrden_sinFirebase_responde503_noUn500() throws Exception {
        // HALLAZGO-7: este endpoint no comprobaba isDisponible() y la excepción llegaba al cliente como 500.
        mvc.perform(get("/api/firmware/orden?usuarioId=u1")).andExpect(status().isServiceUnavailable());
    }

    @Test
    void cuerpoDeEscrituraSinFirebase_tambienDa503() throws Exception {
        mvc.perform(conCuerpo(post("/api/contactos?usuarioId=u1"), "{\"nombre\":\"Ana\",\"telefono\":\"4421234567\",\"relacion\":\"Otro\"}"))
                .andExpect(status().isServiceUnavailable());
        mvc.perform(conCuerpo(put("/api/metas?usuarioId=u1"), "{\"metaPasos\":9000}")).andExpect(status().isServiceUnavailable());
        mvc.perform(conCuerpo(post("/api/admin/invitaciones"), "{\"rol\":\"medico\"}")).andExpect(status().isServiceUnavailable());
        mvc.perform(conCuerpo(put("/api/admin/roles"), "{\"cambios\":[]}")).andExpect(status().isServiceUnavailable());
        mvc.perform(conCuerpo(post("/api/usuarios"), "{\"nombreCompleto\":\"Ana\",\"username\":\"ana\",\"grupos\":[]}"))
                .andExpect(status().isServiceUnavailable());
        mvc.perform(conCuerpo(post("/api/usuarios/u1/pin"), "{\"pin\":\"1234\"}")).andExpect(status().isServiceUnavailable());
        mvc.perform(conCuerpo(post("/api/usuarios/u1/pin/verificar"), "{\"pin\":\"1234\"}")).andExpect(status().isServiceUnavailable());
        mvc.perform(conCuerpo(post("/api/smartwatch/sync?usuarioId=u1"), "{}")).andExpect(status().isServiceUnavailable());
    }

    @Test
    void canjearInvitacion_sinSesionDa401_ySinFirebaseDa503() throws Exception {
        // Rama del controlador: quien == null → 401 antes de mirar la disponibilidad.
        mvc.perform(conCuerpo(post("/api/invitaciones/canjear"), "{\"codigo\":\"ABCDEFGH\"}")).andExpect(status().isUnauthorized());
        mvc.perform(conCuerpo(post("/api/invitaciones/canjear"), "{\"codigo\":\"ABCDEFGH\"}")
                        .requestAttr(ControlDeAcceso.ATRIBUTO, new Identidad("uid-ana", "paciente")))
                .andExpect(status().isServiceUnavailable());
    }

    @Test
    void firmwareUltima_noNecesitaFirebase_yResponde200() throws Exception {
        mvc.perform(get("/api/firmware/ultima")).andExpect(status().isOk()).andExpect(jsonPath("$.version").isNotEmpty());
    }
}
