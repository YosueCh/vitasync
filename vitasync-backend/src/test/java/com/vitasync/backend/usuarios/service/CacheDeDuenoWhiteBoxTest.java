package com.vitasync.backend.usuarios.service;

import com.vitasync.backend.blackbox.RepositoriosEnMemoria;
import com.vitasync.backend.usuarios.dto.CrearUsuarioDTO;
import com.vitasync.backend.usuarios.model.Usuario;
import org.junit.jupiter.api.Test;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * PRÁCTICA 11 · Fase 5 · Cuello de botella: cada petición autenticada hacía una lectura de Firestore (~90 ms) solo para
 * saber quién es el dueño de la cuenta (WB-HALLAZGO-12). El caché recuerda el dueño un minuto. Ramas probadas:
 * acierto, fallo, caducidad, «no existe» (no se recuerda), eliminación (invalida), tope de memoria.
 */
class CacheDeDuenoWhiteBoxTest {

    /** Cuenta cuántas veces se consulta «de verdad» la base de datos. */
    static class Contador extends RepositoriosEnMemoria.Usuarios {
        final AtomicInteger lecturas = new AtomicInteger();

        @Override
        public Usuario buscarPorId(String id) {
            lecturas.incrementAndGet();
            return super.buscarPorId(id);
        }
    }

    private final AtomicLong ahora = new AtomicLong(1_000_000L);
    private final Clock reloj = new Clock() {
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

    private final Contador repo = new Contador();
    private final UsuarioService servicio = new UsuarioService(Optional.of(repo), List.of(), reloj);

    private String cuenta() {
        return servicio.crear(new CrearUsuarioDTO("Ana Pérez", "ana" + System.nanoTime(), List.of()), "uid-ana").id();
    }

    @Test
    void laPrimeraConsultaVaALaBaseDeDatos_lasSiguientesSeResuelvenEnMemoria() {
        String id = cuenta();
        repo.lecturas.set(0);
        for (int i = 0; i < 20; i++) assertThat(servicio.propietarioDe(id)).contains("uid-ana");
        assertThat(repo.lecturas.get()).as("20 consultas del dueño → lecturas reales de la base de datos").isEqualTo(1);
    }

    @Test
    void alVencerLaVigencia_seVuelveAConsultar() {
        String id = cuenta();
        repo.lecturas.set(0);
        servicio.propietarioDe(id);
        ahora.addAndGet(UsuarioService.VIGENCIA_DUENOS_MS - 1);
        servicio.propietarioDe(id);
        assertThat(repo.lecturas.get()).isEqualTo(1);
        ahora.addAndGet(2); // ya pasó la vigencia
        servicio.propietarioDe(id);
        assertThat(repo.lecturas.get()).isEqualTo(2);
    }

    @Test
    void unaCuentaQueNoExiste_noSeRecuerda_yUnaRecienCreadaSeVeAlInstante() {
        assertThat(servicio.propietarioDe("zz-aun-no-existe")).isEmpty();
        assertThat(servicio.propietarioDe("zz-aun-no-existe")).isEmpty();
        assertThat(repo.lecturas.get()).as("cada consulta de algo inexistente va a la base de datos").isEqualTo(2);
        // Se crea una cuenta con ese id (lo hace el propio servicio con un UUID; aquí se inserta directo)
        Usuario u = new Usuario();
        u.setId("zz-aun-no-existe");
        u.setNombreCompleto("Nueva");
        u.setUsername("nueva");
        u.setGrupos(List.of());
        u.setPropietarioUid("uid-nueva");
        u.setFechaCreacion("2026-11-22T00:00:00Z");
        repo.guardar(u);
        assertThat(servicio.propietarioDe("zz-aun-no-existe")).contains("uid-nueva");
    }

    @Test
    void alEliminarLaCuenta_elCacheSeInvalida_yYaNoTieneDueno() {
        String id = cuenta();
        assertThat(servicio.propietarioDe(id)).contains("uid-ana"); // queda en caché
        servicio.eliminar(id);
        assertThat(servicio.propietarioDe(id)).as("tras eliminar no debe seguir respondiendo desde el caché").isEmpty();
    }

    @Test
    void unaCuentaSinDueno_noSeCachea() {
        String id = servicio.crear(new CrearUsuarioDTO("Sin dueño", "sin.dueno", List.of()), null).id();
        repo.lecturas.set(0);
        assertThat(servicio.propietarioDe(id)).isEmpty();
        assertThat(servicio.propietarioDe(id)).isEmpty();
        assertThat(repo.lecturas.get()).isEqualTo(2);
    }

    @Test
    void cuentasDistintas_tienenSuPropioDueno() {
        String a = servicio.crear(new CrearUsuarioDTO("Ana Pérez", "ana.x", List.of()), "uid-ana").id();
        String b = servicio.crear(new CrearUsuarioDTO("Beto Ruiz", "beto.x", List.of()), "uid-beto").id();
        assertThat(servicio.propietarioDe(a)).contains("uid-ana");
        assertThat(servicio.propietarioDe(b)).contains("uid-beto");
        assertThat(servicio.propietarioDe(a)).contains("uid-ana");
    }

    @Test
    void conLaVigenciaEnCero_elCacheQuedaApagado_yCadaConsultaVaALaBaseDeDatos() {
        var servicioSinCache = new UsuarioService(Optional.of(repo), List.of(), 0L);
        String id = servicioSinCache.crear(new CrearUsuarioDTO("Ana Pérez", "ana.sc", List.of()), "uid-ana").id();
        repo.lecturas.set(0);
        for (int i = 0; i < 5; i++) assertThat(servicioSinCache.propietarioDe(id)).contains("uid-ana");
        assertThat(repo.lecturas.get()).isEqualTo(5);
    }
}
