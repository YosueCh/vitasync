package com.vitasync.backend.usuarios.service;

import com.vitasync.backend.usuarios.dto.LoginResultadoDTO;
import com.vitasync.backend.usuarios.model.Usuario;
import com.vitasync.backend.usuarios.repository.UsuarioRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class PinServiceTest {

    /** Reloj que se puede adelantar para probar el bloqueo sin esperar. */
    private static class RelojMutable extends Clock {
        private Instant ahora = Instant.parse("2026-10-19T12:00:00Z");

        void avanzar(Duration d) {
            ahora = ahora.plus(d);
        }

        @Override
        public ZoneOffset getZone() {
            return ZoneOffset.UTC;
        }

        @Override
        public Clock withZone(java.time.ZoneId zone) {
            return this;
        }

        @Override
        public Instant instant() {
            return ahora;
        }
    }

    private UsuarioRepository repo;
    private Usuario usuario;
    private RelojMutable reloj;
    private PinService service;

    @BeforeEach
    void preparar() {
        repo = mock(UsuarioRepository.class);
        usuario = new Usuario();
        usuario.setId("u1");
        usuario.setHabilitado(true);
        when(repo.buscarPorId("u1")).thenReturn(usuario);
        reloj = new RelojMutable();
        service = new PinService(Optional.of(repo), reloj);
    }

    @Test
    void registrar_guardaSaltYHashNuncaElPin() {
        service.registrar("u1", "1234");

        assertThat(usuario.getPinSalt()).hasSize(32); // 16 bytes en hex
        assertThat(usuario.getPinHash()).hasSize(64); // SHA-256 en hex
        assertThat(usuario.getPinHash()).isEqualTo(PinService.hash(usuario.getPinSalt(), "1234"));
        assertThat(usuario.getPinHash()).doesNotContain("1234");
    }

    @Test
    void dosCuentasConElMismoPin_tienenHashDistinto() {
        Usuario otro = new Usuario();
        otro.setId("u2");
        otro.setHabilitado(true);
        when(repo.buscarPorId("u2")).thenReturn(otro);

        service.registrar("u1", "1234");
        service.registrar("u2", "1234");

        assertThat(usuario.getPinSalt()).isNotEqualTo(otro.getPinSalt());
        assertThat(usuario.getPinHash()).isNotEqualTo(otro.getPinHash());
    }

    @Test
    void registrar_conUnPinQueYaExiste_seRechaza() {
        service.registrar("u1", "1234");
        assertThatThrownBy(() -> service.registrar("u1", "9999"))
                .isInstanceOf(PinService.PinYaRegistradoException.class);
    }

    @Test
    void elPinDebeTenerExactamenteCuatroDigitos() {
        for (String malo : new String[]{null, "", "123", "12345", "12a4", "1 34"}) {
            assertThatThrownBy(() -> service.registrar("u1", malo))
                    .isInstanceOf(PinService.PinInvalidoException.class);
            assertThatThrownBy(() -> service.verificar("u1", malo))
                    .isInstanceOf(PinService.PinInvalidoException.class);
        }
    }

    @Test
    void verificar_conElPinCorrecto_entra() {
        service.registrar("u1", "1234");
        LoginResultadoDTO r = service.verificar("u1", "1234");

        assertThat(r.exito()).isTrue();
        assertThat(usuario.getUltimoInicioSesion()).isEqualTo("2026-10-19T12:00:00Z");
    }

    @Test
    void verificar_conPinIncorrecto_avisaCuantosIntentosQuedan() {
        service.registrar("u1", "1234");
        LoginResultadoDTO r = service.verificar("u1", "0000");

        assertThat(r.exito()).isFalse();
        assertThat(r.mensaje()).contains("4 intentos");
    }

    @Test
    void verificar_sinPinRegistrado_seAvisa() {
        assertThatThrownBy(() -> service.verificar("u1", "1234"))
                .isInstanceOf(PinService.PinNoRegistradoException.class);
    }

    @Test
    void verificar_cuentaDeshabilitada_seRechazaAunConPinCorrecto() {
        service.registrar("u1", "1234");
        usuario.setHabilitado(false);

        assertThat(service.verificar("u1", "1234").exito()).isFalse();
    }

    @Test
    void cincoFallosSeguidos_bloqueanLaCuenta() {
        service.registrar("u1", "1234");
        for (int i = 0; i < 4; i++) {
            assertThat(service.verificar("u1", "0000").exito()).isFalse();
        }

        assertThatThrownBy(() -> service.verificar("u1", "0000"))
                .isInstanceOf(PinService.CuentaBloqueadaException.class);
        // Bloqueada, ni el PIN correcto entra.
        assertThatThrownBy(() -> service.verificar("u1", "1234"))
                .isInstanceOf(PinService.CuentaBloqueadaException.class);
    }

    @Test
    void despuesDeCincoMinutos_elBloqueoTermina() {
        service.registrar("u1", "1234");
        for (int i = 0; i < 4; i++) service.verificar("u1", "0000");
        assertThatThrownBy(() -> service.verificar("u1", "0000"))
                .isInstanceOf(PinService.CuentaBloqueadaException.class);

        reloj.avanzar(Duration.ofMinutes(5).plusSeconds(1));

        assertThat(service.verificar("u1", "1234").exito()).isTrue();
    }

    @Test
    void unAciertoReiniciaLaCuentaDeFallos() {
        service.registrar("u1", "1234");
        for (int i = 0; i < 4; i++) service.verificar("u1", "0000");
        assertThat(service.verificar("u1", "1234").exito()).isTrue();

        // Con la cuenta reiniciada, otros 4 fallos no bloquean.
        for (int i = 0; i < 4; i++) {
            assertThat(service.verificar("u1", "0000").exito()).isFalse();
        }
    }

    @Test
    void cuentaInexistente_seInforma() {
        when(repo.buscarPorId("nadie")).thenReturn(null);
        assertThatThrownBy(() -> service.verificar("nadie", "1234"))
                .isInstanceOf(UsuarioService.UsuarioNoEncontradoException.class);
    }
}
