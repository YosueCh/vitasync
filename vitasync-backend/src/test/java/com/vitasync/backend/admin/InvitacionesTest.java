package com.vitasync.backend.admin;

import com.vitasync.backend.admin.InvitacionRepository.Invitacion;
import com.vitasync.backend.blackbox.RepositoriosEnMemoria;
import com.vitasync.backend.seguridad.ControlDeAcceso;
import com.vitasync.backend.seguridad.Identidad;
import com.vitasync.backend.seguridad.VerificadorToken;
import com.vitasync.backend.smartwatch.service.SmartwatchService;
import com.vitasync.backend.usuarios.service.UsuarioService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** Invitaciones de un solo uso con rol (Práctica 7 dentro de VitaSync). Servicio, controlador y filtro reales. */
class InvitacionesTest {

    private static final Map<String, Identidad> TOKENS = Map.of(
            "token-admin", new Identidad("uid-admin", "admin"),
            "token-ana", new Identidad("uid-ana", "paciente"),
            "token-beto", new Identidad("uid-beto", "paciente"));

    private MockMvc mvc;
    private RepositoriosEnMemoria.Roles roles;
    private RepositoriosEnMemoria.Invitaciones repo;
    private InvitacionesService service;
    private final AtomicLong ahora = new AtomicLong(1_000_000_000_000L);

    @BeforeEach
    void preparar() {
        roles = new RepositoriosEnMemoria.Roles().agregar("uid-admin", "admin@x.mx", "admin")
                .agregar("uid-ana", "ana@x.mx", "paciente").agregar("uid-beto", "beto@x.mx", "paciente");
        repo = new RepositoriosEnMemoria.Invitaciones();
        Clock reloj = new Clock() {
            public java.time.ZoneId getZone() {
                return ZoneOffset.UTC;
            }

            public Clock withZone(java.time.ZoneId z) {
                return this;
            }

            public Instant instant() {
                return Instant.ofEpochMilli(ahora.get());
            }
        };
        service = new InvitacionesService(Optional.of(repo), Optional.of(roles), reloj);
        VerificadorToken verificador = t -> Optional.ofNullable(TOKENS.get(t));
        mvc = MockMvcBuilders.standaloneSetup(new InvitacionesController(service))
                .addFilters(new ControlDeAcceso(verificador, new UsuarioService(Optional.of(new RepositoriosEnMemoria.Usuarios()), List.of()),
                        new SmartwatchService(Optional.of(new RepositoriosEnMemoria.Dispositivos()))))
                .build();
    }

    private ResultActions crear(String token, String rol) throws Exception {
        return mvc.perform(post("/api/admin/invitaciones").header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON).content("{\"rol\":\"" + rol + "\"}"));
    }

    private ResultActions canjear(String token, String codigo) throws Exception {
        return mvc.perform(post("/api/invitaciones/canjear").header("Authorization", "Bearer " + token)
                .contentType(MediaType.APPLICATION_JSON).content("{\"codigo\":\"" + codigo + "\"}"));
    }

    @Test
    void elAdministradorCreaUnCodigoDeOchoCaracteresConVigenciaDeSieteDias() throws Exception {
        crear("token-admin", "medico").andExpect(status().isOk())
                .andExpect(jsonPath("$.codigo").value(org.hamcrest.Matchers.matchesPattern("[A-Z2-9]{8}")))
                .andExpect(jsonPath("$.rol").value("medico"))
                .andExpect(jsonPath("$.usadaPor").doesNotExist());
        Invitacion i = repo.listar().get(0);
        assertThat(i.venceEn() - i.creadaEn()).isEqualTo(InvitacionesService.VIGENCIA_MS);
    }

    @Test
    void canjearAsignaElRolYElCodigoQuedaUsado() throws Exception {
        String codigo = service.crear("medico").codigo();
        canjear("token-ana", codigo).andExpect(status().isOk()).andExpect(jsonPath("$.rol").value("medico"));
        assertThat(roles.buscar("uid-ana").get().rol()).isEqualTo("medico");
        assertThat(repo.obtener(codigo).get().usadaPor()).isEqualTo("uid-ana");
    }

    @Test
    void elCodigoSeAceptaEnMinusculasYConEspacios() throws Exception {
        String codigo = service.crear("medico").codigo();
        canjear("token-ana", "  " + codigo.toLowerCase() + " ").andExpect(status().isOk());
    }

    @Test
    void unCodigoSoloSirveUnaVez_409() throws Exception {
        String codigo = service.crear("medico").codigo();
        canjear("token-ana", codigo).andExpect(status().isOk());
        canjear("token-beto", codigo).andExpect(status().isConflict()).andExpect(jsonPath("$.error").value("Ese código ya se usó."));
        assertThat(roles.buscar("uid-beto").get().rol()).isEqualTo("paciente");
    }

    @Test
    void codigoCaducado_409() throws Exception {
        String codigo = service.crear("medico").codigo();
        ahora.addAndGet(InvitacionesService.VIGENCIA_MS + 1);
        canjear("token-ana", codigo).andExpect(status().isConflict()).andExpect(jsonPath("$.error").value("Ese código caducó."));
        assertThat(roles.buscar("uid-ana").get().rol()).isEqualTo("paciente");
    }

    @Test
    void codigoInexistenteOMalFormado() throws Exception {
        canjear("token-ana", "ZZZZZZZZ").andExpect(status().isConflict());
        canjear("token-ana", "corto").andExpect(status().isBadRequest());
        canjear("token-ana", "").andExpect(status().isBadRequest());
    }

    @Test
    void despuesDeCincoFallosSeBloqueaEseUsuario_429_yElBloqueoCaduca() throws Exception {
        for (int i = 0; i < InvitacionesService.MAX_FALLOS; i++) canjear("token-ana", "ZZZZZZZZ").andExpect(status().isConflict());
        String bueno = service.crear("medico").codigo();
        canjear("token-ana", bueno).andExpect(status().isTooManyRequests());
        assertThat(roles.buscar("uid-ana").get().rol()).isEqualTo("paciente");
        // Otra persona no se ve afectada.
        canjear("token-beto", bueno).andExpect(status().isOk());
        // Pasada la ventana, Ana puede volver a intentar.
        ahora.addAndGet(InvitacionesService.VENTANA_FALLOS_MS + 1);
        canjear("token-ana", service.crear("paciente").codigo()).andExpect(status().isOk());
    }

    @Test
    void soloPacienteOMedico_yNuncaAdministrador() throws Exception {
        crear("token-admin", "admin").andExpect(status().isBadRequest());
        crear("token-admin", "dios").andExpect(status().isBadRequest());
        mvc.perform(post("/api/admin/invitaciones").header("Authorization", "Bearer token-admin")
                .contentType(MediaType.APPLICATION_JSON).content("{}")).andExpect(status().isBadRequest());
    }

    @Test
    void unAdministradorNoPuedeCambiarSuRolConUnaInvitacion() throws Exception {
        String codigo = service.crear("paciente").codigo();
        canjear("token-admin", codigo).andExpect(status().isBadRequest());
        assertThat(roles.buscar("uid-admin").get().rol()).isEqualTo("admin");
        assertThat(repo.obtener(codigo).get().usadaPor()).isNull(); // no se gastó el código
    }

    @Test
    void soloElAdministradorCreaYListaInvitaciones_403() throws Exception {
        crear("token-ana", "medico").andExpect(status().isForbidden());
        mvc.perform(get("/api/admin/invitaciones").header("Authorization", "Bearer token-ana")).andExpect(status().isForbidden());
        mvc.perform(get("/api/admin/invitaciones").header("Authorization", "Bearer token-admin")).andExpect(status().isOk());
        assertThat(repo.listar()).isEmpty();
    }

    @Test
    void sinSesion_401() throws Exception {
        mvc.perform(post("/api/invitaciones/canjear").contentType(MediaType.APPLICATION_JSON).content("{\"codigo\":\"ABCDEFGH\"}"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void sinFirebase_503() throws Exception {
        MockMvc sin = MockMvcBuilders.standaloneSetup(new InvitacionesController(
                new InvitacionesService(Optional.empty(), Optional.empty()))).build();
        sin.perform(get("/api/admin/invitaciones")).andExpect(status().isServiceUnavailable());
    }

    @Test
    void dosPersonasConElMismoCodigoAlMismoTiempo_soloUnaLoUsa() throws Exception {
        String codigo = service.crear("medico").codigo();
        AtomicInteger exitos = new AtomicInteger();
        Thread a = new Thread(() -> intentar("uid-ana", codigo, exitos));
        Thread b = new Thread(() -> intentar("uid-beto", codigo, exitos));
        a.start();
        b.start();
        a.join();
        b.join();
        assertThat(exitos.get()).isEqualTo(1);
    }

    private void intentar(String uid, String codigo, AtomicInteger exitos) {
        try {
            service.canjear(uid, codigo);
            exitos.incrementAndGet();
        } catch (RuntimeException ignorado) {
            // la otra persona perdió la carrera
        }
    }
}
