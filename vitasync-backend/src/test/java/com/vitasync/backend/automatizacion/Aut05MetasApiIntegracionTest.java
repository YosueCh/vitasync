package com.vitasync.backend.automatizacion;

import com.vitasync.backend.blackbox.RepositoriosEnMemoria;
import com.vitasync.backend.metas.MetasController;
import com.vitasync.backend.metas.MetasCuentaDTO;
import com.vitasync.backend.metas.MetasRepository;
import com.vitasync.backend.metas.MetasService;
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

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.function.UnaryOperator;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * PRÁCTICAS 13 y 14 · AUT-05 · Pruebas de INTEGRACIÓN de la API de metas: filtro de seguridad REAL + controlador REAL + servicio
 * REAL + repositorio (en memoria). Comprueba el código HTTP y el JSON de cada situación, que no se filtren detalles internos y
 * que, con peticiones simultáneas con la misma versión, gane exactamente una.
 */
class Aut05MetasApiIntegracionTest {

    private static final Map<String, Identidad> TOKENS = Map.of(
            "token-ana", new Identidad("uid-ana", "paciente"),
            "token-beto", new Identidad("uid-beto", "paciente"));

    private MockMvc mvc;
    private String cuentaAna;
    private RepositoriosEnMemoria.Metas repo;
    private volatile RuntimeException fallo; // permite simular una falla del repositorio

    private ResultActions guardar(String token, String cuenta, String json) throws Exception {
        var req = put("/api/metas?usuarioId=" + cuenta).contentType(MediaType.APPLICATION_JSON).content(json);
        if (token != null) req.header("Authorization", "Bearer " + token);
        return mvc.perform(req);
    }

    @BeforeEach
    void preparar() {
        fallo = null;
        repo = new RepositoriosEnMemoria.Metas() {
            @Override
            public synchronized MetasCuentaDTO actualizar(String cuentaId, Long versionEsperada, UnaryOperator<MetasCuentaDTO> cambio) {
                if (fallo != null) throw fallo;
                return super.actualizar(cuentaId, versionEsperada, cambio);
            }
        };
        MetasService metas = new MetasService(Optional.of(repo));
        UsuarioService usuarios = new UsuarioService(Optional.of(new RepositoriosEnMemoria.Usuarios()), List.of(metas));
        SmartwatchService reloj = new SmartwatchService(Optional.of(new RepositoriosEnMemoria.Dispositivos()));
        VerificadorToken verificador = t -> Optional.ofNullable(TOKENS.get(t));
        mvc = MockMvcBuilders.standaloneSetup(new MetasController(metas)).setControllerAdvice(new com.vitasync.backend.config.ManejadorDeErrores()).addFilters(new ControlDeAcceso(verificador, usuarios, reloj)).build();
        cuentaAna = usuarios.crear(new CrearUsuarioDTO("Ana Pérez", "ana", List.of()), "uid-ana").id();
        usuarios.crear(new CrearUsuarioDTO("Beto Ruiz", "beto", List.of()), "uid-beto");
    }

    @Test
    void put200_guardaYDevuelveLasMetasConLaVersionNueva() throws Exception {
        guardar("token-ana", cuentaAna, "{\"metaPasos\":9000,\"version\":0}").andExpect(status().isOk())
                .andExpect(jsonPath("$.metaPasos").value(9000)).andExpect(jsonPath("$.version").value(1));
        mvc.perform(get("/api/metas?usuarioId=" + cuentaAna).header("Authorization", "Bearer token-ana"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.metaPasos").value(9000));
    }

    @Test
    void put400_datoInvalido_traeUnMensajeUtilEnJson() throws Exception {
        guardar("token-ana", cuentaAna, "{\"metaPasos\":5}").andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("La meta de pasos debe estar entre 1000 y 50000."));
        guardar("token-ana", cuentaAna, "{}").andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("Indica al menos una meta para cambiar."));
    }

    @Test
    void put401_sinToken_yTokenInvalido() throws Exception {
        guardar(null, cuentaAna, "{\"metaPasos\":9000}").andExpect(status().isUnauthorized());
        guardar("token-falso", cuentaAna, "{\"metaPasos\":9000}").andExpect(status().isUnauthorized());
    }

    @Test
    void put403_laCuentaEsDeOtraPersona_yNoSeGuardaNada() throws Exception {
        guardar("token-beto", cuentaAna, "{\"metaPasos\":9000}").andExpect(status().isForbidden());
        assertThat(repo.obtener(cuentaAna)).as("no se escribió nada").isEmpty();
    }

    @Test
    void idDeCuentaMalformado_es400_noUn500() throws Exception {
        guardar("token-ana", "../../etc", "{\"metaPasos\":9000}").andExpect(status().isBadRequest());
    }

    @Test
    void put409_conflictoDeVersion_traeCodigoYLasMetasActuales() throws Exception {
        guardar("token-ana", cuentaAna, "{\"metaPasos\":12000,\"version\":0}").andExpect(status().isOk());
        guardar("token-ana", cuentaAna, "{\"metaPasos\":7000,\"version\":0}").andExpect(status().isConflict())
                .andExpect(jsonPath("$.codigo").value("CONFLICTO_DE_VERSION")).andExpect(jsonPath("$.actual.metaPasos").value(12000));
    }

    @Test
    void put409_contencionAgotada_respondeOCUPADO_noUn500() throws Exception {
        // Defecto P12-02: bajo contención Firestore agotaba los reintentos y la API contestaba 500.
        fallo = new MetasRepository.MetasOcupadasException(new RuntimeException("ABORTED"));
        guardar("token-ana", cuentaAna, "{\"metaPasos\":9000}").andExpect(status().isConflict())
                .andExpect(jsonPath("$.codigo").value("OCUPADO")).andExpect(jsonPath("$.error").value(org.hamcrest.Matchers.containsString("Inténtalo de nuevo")));
    }

    @Test
    void errorInesperado_es500_conMensajeGenerico_sinPilaNiDetallesInternos() throws Exception {
        fallo = new IllegalStateException("clave-secreta-interna jdbc://host");
        var r = guardar("token-ana", cuentaAna, "{\"metaPasos\":9000}").andExpect(status().isInternalServerError()).andReturn().getResponse();
        assertThat(r.getContentAsString()).contains("error").doesNotContain("clave-secreta").doesNotContain("jdbc").doesNotContain("at com.");
    }

    @Test
    void diezPeticionesSimultaneasConLaMismaVersion_ganaExactamenteUna() throws Exception {
        ExecutorService pool = Executors.newFixedThreadPool(10);
        CountDownLatch salida = new CountDownLatch(1);
        List<Future<Integer>> codigos = new ArrayList<>();
        for (int i = 0; i < 10; i++) {
            int valor = 6000 + i;
            codigos.add(pool.submit(() -> {
                salida.await();
                return guardar("token-ana", cuentaAna, "{\"metaPasos\":" + valor + ",\"version\":0}").andReturn().getResponse().getStatus();
            }));
        }
        salida.countDown();
        int ok = 0, conflictos = 0;
        for (Future<Integer> f : codigos) {
            int c = f.get(15, TimeUnit.SECONDS);
            if (c == 200) ok++;
            else if (c == 409) conflictos++;
        }
        pool.shutdown();

        assertThat(ok).isEqualTo(1);
        assertThat(conflictos).isEqualTo(9);
        assertThat(repo.obtener(cuentaAna).orElseThrow().version()).isEqualTo(1);
    }
}
