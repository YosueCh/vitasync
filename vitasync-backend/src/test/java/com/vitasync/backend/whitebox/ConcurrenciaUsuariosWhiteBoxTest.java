package com.vitasync.backend.whitebox;

import com.vitasync.backend.blackbox.RepositoriosEnMemoria;
import com.vitasync.backend.usuarios.dto.CrearUsuarioDTO;
import com.vitasync.backend.usuarios.model.Usuario;
import com.vitasync.backend.usuarios.service.UsuarioService;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * PRÁCTICA 11 · Fase 4 · DB-02 Integridad y DB-06 Concurrencia sobre «usuarios».
 *
 * Firestore no tiene una restricción UNIQUE: la unicidad del campo «username» la tiene que garantizar la aplicación.
 * Antes de la corrección, dos altas simultáneas con el mismo usuario pasaban la comprobación (WB-HALLAZGO-9) y quedaban
 * dos cuentas con el mismo usuario. Además la comprobación leía TODA la colección (WB-HALLAZGO-10).
 */
class ConcurrenciaUsuariosWhiteBoxTest {

    /** Repositorio en memoria con la latencia de una consulta de red. */
    static class ConLatencia extends RepositoriosEnMemoria.Usuarios {
        @Override
        public boolean existeUsername(String username) {
            boolean r = super.existeUsername(username);
            dormir(40);
            return r;
        }

        @Override
        public List<Usuario> listarTodos() {
            List<Usuario> r = super.listarTodos();
            dormir(40);
            return r;
        }

        private static void dormir(long ms) {
            try {
                Thread.sleep(ms);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }
    }

    @Test
    void diezAltasSimultaneasConElMismoUsuario_soloUnaCuentaSeCrea() throws Exception {
        var repo = new ConLatencia();
        var servicio = new UsuarioService(Optional.of(repo));
        int hilos = 10;
        ExecutorService pool = Executors.newFixedThreadPool(hilos);
        CyclicBarrier salida = new CyclicBarrier(hilos);
        AtomicInteger creadas = new AtomicInteger();
        AtomicInteger rechazadas = new AtomicInteger();
        List<Future<?>> trabajos = new ArrayList<>();
        for (int i = 0; i < hilos; i++) {
            final int n = i;
            trabajos.add(pool.submit(() -> {
                salida.await();
                try {
                    servicio.crear(new CrearUsuarioDTO("Persona " + n, "mismo.usuario", List.of()), "uid-" + n);
                    creadas.incrementAndGet();
                } catch (UsuarioService.UsernameDuplicadoException e) {
                    rechazadas.incrementAndGet();
                }
                return null;
            }));
        }
        for (Future<?> t : trabajos) t.get(30, TimeUnit.SECONDS);
        pool.shutdown();

        long conEseUsuario = repo.listarTodos().stream().filter(u -> "mismo.usuario".equals(u.getUsername())).count();
        assertThat(conEseUsuario).as("cuentas con el mismo usuario (creadas=%d, rechazadas=%d)", creadas.get(), rechazadas.get()).isEqualTo(1);
        assertThat(creadas.get()).isEqualTo(1);
        assertThat(rechazadas.get()).isEqualTo(9);
    }

    @Test
    void elUsuarioSeComparaSinImportarMayusculas() {
        var servicio = new UsuarioService(Optional.of(new RepositoriosEnMemoria.Usuarios()));
        servicio.crear(new CrearUsuarioDTO("Ana Pérez", "Ana.P", List.of()), "uid-a");
        org.junit.jupiter.api.Assertions.assertThrows(UsuarioService.UsernameDuplicadoException.class,
                () -> servicio.crear(new CrearUsuarioDTO("Otra Ana", "ANA.p", List.of()), "uid-b"));
    }

    @Test
    void listarDe_devuelveSoloLasCuentasDeEsaPersona_yNadaConUidNulo() {
        var servicio = new UsuarioService(Optional.of(new RepositoriosEnMemoria.Usuarios()));
        servicio.crear(new CrearUsuarioDTO("Ana Pérez", "ana", List.of()), "uid-ana");
        servicio.crear(new CrearUsuarioDTO("Ana Dos", "ana2", List.of()), "uid-ana");
        servicio.crear(new CrearUsuarioDTO("Beto Ruiz", "beto", List.of()), "uid-beto");
        servicio.crear(new CrearUsuarioDTO("Sin dueño", "sin.dueno", List.of()), null);
        assertThat(servicio.listarDe("uid-ana")).extracting("username").containsExactlyInAnyOrder("ana", "ana2");
        assertThat(servicio.listarDe("uid-beto")).hasSize(1);
        assertThat(servicio.listarDe(null)).isEmpty();
        assertThat(servicio.listarDe("uid-inexistente")).isEmpty();
    }

    @Test
    void alEliminarLaCuenta_suUsuarioQuedaLibre() {
        var servicio = new UsuarioService(Optional.of(new RepositoriosEnMemoria.Usuarios()));
        String id = servicio.crear(new CrearUsuarioDTO("Ana Pérez", "ana", List.of()), "uid-a").id();
        servicio.eliminar(id);
        assertThat(servicio.crear(new CrearUsuarioDTO("Ana Nueva", "ana", List.of()), "uid-b").username()).isEqualTo("ana");
    }
}
