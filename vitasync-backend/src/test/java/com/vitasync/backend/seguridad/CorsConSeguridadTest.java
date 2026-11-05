package com.vitasync.backend.seguridad;

import com.vitasync.backend.blackbox.RepositoriosEnMemoria;
import com.vitasync.backend.config.CorsConfig;
import com.vitasync.backend.smartwatch.controller.SmartwatchController;
import com.vitasync.backend.smartwatch.service.SmartwatchService;
import com.vitasync.backend.usuarios.service.UsuarioService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.options;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * El sitio web (Angular, otro origen) tiene que poder LEER el 401 y el 403 del control de acceso: sin cabeceras CORS
 * el navegador los entrega como error de red y el sitio no se entera de que la sesión venció. Estas pruebas usan el
 * mismo filtro de CORS y el mismo orden que la aplicación (CORS antes que el control de acceso).
 */
class CorsConSeguridadTest {

    private MockMvc mvc;

    @BeforeEach
    void preparar() {
        SmartwatchService reloj = new SmartwatchService(Optional.of(new RepositoriosEnMemoria.Dispositivos()));
        UsuarioService usuarios = new UsuarioService(Optional.of(new RepositoriosEnMemoria.Usuarios()), List.of());
        VerificadorToken verificador = t -> Optional.ofNullable(Map.of("token-ana", new Identidad("uid-ana", "paciente")).get(t));
        mvc = MockMvcBuilders.standaloneSetup(new SmartwatchController(reloj))
                .addFilters(CorsConfig.nuevoFiltro(), new ControlDeAcceso(verificador, usuarios, reloj))
                .build();
    }

    @Test
    void el401LlevaLasCabecerasCors_paraQueElSitioLoLea() throws Exception {
        mvc.perform(get("/api/smartwatch/status?usuarioId=x").header("Origin", "http://localhost:4200"))
                .andExpect(status().isUnauthorized())
                .andExpect(header().string("Access-Control-Allow-Origin", "http://localhost:4200"));
    }

    @Test
    void el403LlevaLasCabecerasCors() throws Exception {
        mvc.perform(get("/api/smartwatch/status?usuarioId=ajena").header("Origin", "http://localhost:4200")
                        .header("Authorization", "Bearer token-ana"))
                .andExpect(status().isForbidden())
                .andExpect(header().string("Access-Control-Allow-Origin", "http://localhost:4200"));
    }

    @Test
    void laPeticionPreviaDelNavegadorConAuthorizationSeAcepta() throws Exception {
        mvc.perform(options("/api/usuarios").header("Origin", "http://localhost:4200")
                        .header("Access-Control-Request-Method", "GET")
                        .header("Access-Control-Request-Headers", "authorization"))
                .andExpect(status().isOk())
                .andExpect(header().string("Access-Control-Allow-Origin", "http://localhost:4200"))
                .andExpect(header().string("Access-Control-Allow-Headers", "authorization"));
    }

    @Test
    void unOrigenAjenoNoRecibeCabecerasCors() throws Exception {
        mvc.perform(get("/api/smartwatch/status?usuarioId=x").header("Origin", "https://sitio-malicioso.example"))
                .andExpect(status().isForbidden()) // el filtro de CORS rechaza el origen no permitido
                .andExpect(header().doesNotExist("Access-Control-Allow-Origin"));
    }
}
