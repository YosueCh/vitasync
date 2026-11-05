package com.vitasync.backend.metas;

import com.vitasync.backend.blackbox.RepositoriosEnMemoria;
import com.vitasync.backend.seguridad.ControlDeAcceso;
import com.vitasync.backend.seguridad.Identidad;
import com.vitasync.backend.seguridad.VerificadorToken;
import com.vitasync.backend.smartwatch.controller.SmartwatchController;
import com.vitasync.backend.smartwatch.service.SmartwatchService;
import com.vitasync.backend.usuarios.dto.CrearUsuarioDTO;
import com.vitasync.backend.usuarios.service.UsuarioService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Práctica 9 dentro de VitaSync: metas compartidas entre la paciente y su médico, con control de versión.
 * Controlador, servicio y filtro de seguridad REALES; solo el repositorio es en memoria.
 */
class MetasTest {

    private static final Map<String, Identidad> TOKENS = Map.of(
            "token-ana", new Identidad("uid-ana", "paciente"),
            "token-beto", new Identidad("uid-beto", "paciente"),
            "token-doc", new Identidad("uid-doc", "medico"));

    private MockMvc mvc;
    private MetasService metas;
    private UsuarioService usuarios;
    private String cuentaAna;

    @BeforeEach
    void preparar() {
        metas = new MetasService(Optional.of(new RepositoriosEnMemoria.Metas()));
        usuarios = new UsuarioService(Optional.of(new RepositoriosEnMemoria.Usuarios()), List.of(metas));
        SmartwatchService reloj = new SmartwatchService(Optional.of(new RepositoriosEnMemoria.Dispositivos()));
        SmartwatchController ctrlReloj = new SmartwatchController(reloj);
        ctrlReloj.setMetas(metas);
        VerificadorToken verificador = t -> Optional.ofNullable(TOKENS.get(t));
        mvc = MockMvcBuilders.standaloneSetup(new MetasController(metas), ctrlReloj)
                .addFilters(new ControlDeAcceso(verificador, usuarios, reloj))
                .build();
        cuentaAna = usuarios.crear(new CrearUsuarioDTO("Ana Pérez", "ana", List.of()), "uid-ana").id();
        usuarios.crear(new CrearUsuarioDTO("Beto Ruiz", "beto", List.of()), "uid-beto");
    }

    private ResultActions leer(String token) throws Exception {
        return mvc.perform(get("/api/metas?usuarioId=" + cuentaAna).header("Authorization", "Bearer " + token));
    }

    private ResultActions guardar(String token, String json) throws Exception {
        return mvc.perform(put("/api/metas?usuarioId=" + cuentaAna).header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON).content(json));
    }

    @Test
    void sinEditarNunca_sonLasPredeterminadasVersionCero() throws Exception {
        leer("token-ana").andExpect(status().isOk())
                .andExpect(jsonPath("$.metaPasos").value(10000))
                .andExpect(jsonPath("$.metaCalorias").value(600))
                .andExpect(jsonPath("$.metaSueno").value(8.0))
                .andExpect(jsonPath("$.version").value(0));
    }

    @Test
    void guardarConLaVersionCorrecta_subeLaVersion() throws Exception {
        guardar("token-ana", "{\"metaPasos\":8000,\"version\":0}").andExpect(status().isOk())
                .andExpect(jsonPath("$.metaPasos").value(8000))
                .andExpect(jsonPath("$.metaCalorias").value(600))
                .andExpect(jsonPath("$.version").value(1));
        leer("token-ana").andExpect(jsonPath("$.metaPasos").value(8000)).andExpect(jsonPath("$.version").value(1));
    }

    @Test
    void conflicto_medicoYPacienteEditanLaMismaVersion_elSegundoRecibe409ConLoActual() throws Exception {
        // Los dos leyeron la versión 0; el médico guarda primero.
        guardar("token-doc", "{\"metaPasos\":12000,\"version\":0}").andExpect(status().isOk());
        // La paciente guarda con su copia vieja → conflicto, y el cuerpo trae lo que hay en el servidor.
        guardar("token-ana", "{\"metaPasos\":7000,\"version\":0}").andExpect(status().isConflict())
                .andExpect(jsonPath("$.codigo").value("CONFLICTO_DE_VERSION"))
                .andExpect(jsonPath("$.actual.metaPasos").value(12000))
                .andExpect(jsonPath("$.actual.version").value(1))
                .andExpect(jsonPath("$.actual.actualizadaPor").value("Médico"));
        // Nada se perdió ni se pisó.
        leer("token-ana").andExpect(jsonPath("$.metaPasos").value(12000));
    }

    @Test
    void trasElConflicto_reintentarConLaVersionNuevaFunciona() throws Exception {
        guardar("token-doc", "{\"metaPasos\":12000,\"version\":0}").andExpect(status().isOk());
        guardar("token-ana", "{\"metaPasos\":7000,\"version\":1}").andExpect(status().isOk())
                .andExpect(jsonPath("$.version").value(2))
                .andExpect(jsonPath("$.actualizadaPor").value("Paciente"));
    }

    @Test
    void versionAdelantada_tambienSeRechaza() throws Exception {
        guardar("token-ana", "{\"metaPasos\":9000,\"version\":5}").andExpect(status().isConflict());
    }

    @Test
    void sinVersion_seFusionaPorCampos_cadaQuienConservaElCampoDelOtro() throws Exception {
        guardar("token-doc", "{\"metaPasos\":12000}").andExpect(status().isOk());
        guardar("token-ana", "{\"metaSueno\":7.5}").andExpect(status().isOk())
                .andExpect(jsonPath("$.metaPasos").value(12000))
                .andExpect(jsonPath("$.metaSueno").value(7.5))
                .andExpect(jsonPath("$.version").value(2));
    }

    @Test
    void elQuienSaleDelTokenNoDeLoQueDigaLaApp() throws Exception {
        guardar("token-ana", "{\"metaPasos\":9000,\"dispositivo\":\"Soy el Médico\"}").andExpect(status().isOk())
                .andExpect(jsonPath("$.actualizadaPor").value("Paciente"));
    }

    @Test
    void sinSesion_laEtiquetaDelClienteSeRecortaA30() {
        MetasCuentaDTO r = metas.actualizar("c1", new ActualizarMetasDTO(9000, null, null, null, "x".repeat(50)), null);
        assertThat(r.actualizadaPor()).hasSize(30);
        assertThat(metas.actualizar("c1", new ActualizarMetasDTO(9100, null, null, null, " "), null).actualizadaPor())
                .isEqualTo("Sin identificar");
    }

    @Test
    void validaciones_devuelven400() throws Exception {
        guardar("token-ana", "{}").andExpect(status().isBadRequest());
        guardar("token-ana", "{\"metaPasos\":999}").andExpect(status().isBadRequest());
        guardar("token-ana", "{\"metaPasos\":50001}").andExpect(status().isBadRequest());
        guardar("token-ana", "{\"metaCalorias\":99}").andExpect(status().isBadRequest());
        guardar("token-ana", "{\"metaCalorias\":5001}").andExpect(status().isBadRequest());
        guardar("token-ana", "{\"metaSueno\":3.9}").andExpect(status().isBadRequest());
        guardar("token-ana", "{\"metaSueno\":12.1}").andExpect(status().isBadRequest());
        guardar("token-ana", "{\"metaPasos\":9000,\"version\":-1}").andExpect(status().isBadRequest());
        leer("token-ana").andExpect(jsonPath("$.version").value(0));
    }

    @Test
    void limitesExactos_sonValidos() throws Exception {
        guardar("token-ana", "{\"metaPasos\":1000,\"metaCalorias\":5000,\"metaSueno\":4.0}").andExpect(status().isOk());
        guardar("token-ana", "{\"metaPasos\":50000,\"metaCalorias\":100,\"metaSueno\":12.0}").andExpect(status().isOk());
    }

    // ------------------------------------------------------------ control de acceso

    @Test
    void sinToken_401() throws Exception {
        mvc.perform(get("/api/metas?usuarioId=" + cuentaAna)).andExpect(status().isUnauthorized());
    }

    @Test
    void otraPaciente_403_yNoPuedeLeerNiCambiar() throws Exception {
        leer("token-beto").andExpect(status().isForbidden());
        guardar("token-beto", "{\"metaPasos\":9000}").andExpect(status().isForbidden());
        leer("token-ana").andExpect(jsonPath("$.version").value(0));
    }

    @Test
    void medicoPuedeVerYCambiarLasMetasDeUnPaciente() throws Exception {
        leer("token-doc").andExpect(status().isOk());
        guardar("token-doc", "{\"metaCalorias\":700}").andExpect(status().isOk());
    }

    @Test
    void medicoNoPuedeUsarOtrasRutasDelPaciente() throws Exception {
        mvc.perform(get("/api/smartwatch/status?usuarioId=" + cuentaAna).header("Authorization", "Bearer token-doc"))
                .andExpect(status().isForbidden());
    }

    // ------------------------------------------------------------ integraciones

    @Test
    void elRelojRecibeLasMetasDeLaCuentaAlSincronizar() throws Exception {
        guardar("token-doc", "{\"metaPasos\":12000,\"metaCalorias\":750,\"metaSueno\":7.0}").andExpect(status().isOk());
        mvc.perform(post("/api/smartwatch/sync?usuarioId=" + cuentaAna).header("Authorization", "Bearer token-ana")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"pasos\":100,\"frecuenciaCardiaca\":70,\"calorias\":10,\"horasSueno\":7}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.metaPasos").value(12000))
                .andExpect(jsonPath("$.metaCalorias").value(750))
                .andExpect(jsonPath("$.metaSueñoHoras").value(7.0));
    }

    @Test
    void alEliminarLaCuenta_seBorranSusMetas() throws Exception {
        guardar("token-ana", "{\"metaPasos\":9000}").andExpect(status().isOk());
        usuarios.eliminar(cuentaAna);
        assertThat(metas.obtener(cuentaAna)).isEqualTo(MetasCuentaDTO.PREDETERMINADAS);
    }
}
