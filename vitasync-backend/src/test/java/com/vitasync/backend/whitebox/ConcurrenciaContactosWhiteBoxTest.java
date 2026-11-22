package com.vitasync.backend.whitebox;

import com.vitasync.backend.blackbox.RepositoriosEnMemoria;
import com.vitasync.backend.contactos.ContactoDTO;
import com.vitasync.backend.contactos.ContactoService;
import com.vitasync.backend.contactos.CrearContactoDTO;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * PRÁCTICA 11 · Fase 4 · DB-06 Concurrencia: dos (o diez) altas de contacto a la vez sobre la MISMA cuenta.
 *
 * Reglas de negocio que deben cumplirse SIEMPRE: máximo {@link ContactoService#MAX_POR_CUENTA} contactos por cuenta y
 * ningún teléfono repetido. Antes de la corrección, {@code ContactoService.crear} hacía «leer la lista → comprobar →
 * guardar» sin ninguna atomicidad: con varias peticiones simultáneas todas leían «hay 0» y todas guardaban
 * (WB-HALLAZGO-8). La latencia de red de Firestore (decenas de ms) hace la ventana de la carrera muy ancha; aquí se
 * simula con una espera en el repositorio.
 */
class ConcurrenciaContactosWhiteBoxTest {

    /** Repositorio en memoria con la latencia de una consulta de red, para ensanchar la ventana de la carrera. */
    static class ConLatencia extends RepositoriosEnMemoria.Contactos {
        @Override
        public List<ContactoDTO> listar(String cuentaId) {
            List<ContactoDTO> lista = super.listar(cuentaId);
            dormir(40);
            return lista;
        }

        @Override
        public void guardar(String cuentaId, ContactoDTO c) {
            dormir(40);
            super.guardar(cuentaId, c);
        }

        private static void dormir(long ms) {
            try {
                Thread.sleep(ms);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }
    }

    private static int[] lanzarAltasSimultaneas(ContactoService servicio, String cuenta, int hilos, java.util.function.IntFunction<String> telefono)
            throws Exception {
        ExecutorService pool = Executors.newFixedThreadPool(hilos);
        CyclicBarrier salida = new CyclicBarrier(hilos); // todos arrancan en el mismo instante
        AtomicInteger creados = new AtomicInteger();
        AtomicInteger rechazados = new AtomicInteger();
        List<Future<?>> trabajos = new ArrayList<>();
        for (int i = 0; i < hilos; i++) {
            final int n = i;
            trabajos.add(pool.submit(() -> {
                salida.await();
                try {
                    servicio.crear(cuenta, new CrearContactoDTO("Contacto " + n, telefono.apply(n), "Otro"));
                    creados.incrementAndGet();
                } catch (ContactoService.ConflictoException e) {
                    rechazados.incrementAndGet();
                }
                return null;
            }));
        }
        for (Future<?> t : trabajos) t.get(30, TimeUnit.SECONDS);
        pool.shutdown();
        return new int[]{creados.get(), rechazados.get()};
    }

    @Test
    void diezAltasSimultaneasConTelefonosDistintos_nuncaPasanDelMaximoDeCinco() throws Exception {
        var servicio = new ContactoService(java.util.Optional.of(new ConLatencia()));
        int[] r = lanzarAltasSimultaneas(servicio, "cuenta-1", 10, i -> "442111220" + i);

        int guardados = servicio.listar("cuenta-1").size();
        assertThat(guardados).as("contactos guardados (creados=%d, rechazados=%d)", r[0], r[1])
                .isLessThanOrEqualTo(ContactoService.MAX_POR_CUENTA);
        assertThat(r[0]).isEqualTo(guardados);
        assertThat(r[0] + r[1]).isEqualTo(10);
    }

    @Test
    void diezAltasSimultaneasConElMismoTelefono_soloUnaSeGuarda() throws Exception {
        var servicio = new ContactoService(java.util.Optional.of(new ConLatencia()));
        int[] r = lanzarAltasSimultaneas(servicio, "cuenta-2", 10, i -> "4421234567");

        List<ContactoDTO> guardados = servicio.listar("cuenta-2");
        assertThat(guardados).as("teléfono repetido guardado %d veces", guardados.size()).hasSize(1);
        assertThat(r[0]).isEqualTo(1);
        assertThat(r[1]).isEqualTo(9);
    }

    @Test
    void sinConcurrencia_elLimiteYLaUnicidadSiguenFuncionando() throws Exception {
        var servicio = new ContactoService(java.util.Optional.of(new RepositoriosEnMemoria.Contactos()));
        for (int i = 0; i < 5; i++) servicio.crear("cuenta-3", new CrearContactoDTO("Contacto " + i, "44211122" + (10 + i), "Otro"));
        org.junit.jupiter.api.Assertions.assertThrows(ContactoService.ConflictoException.class,
                () -> servicio.crear("cuenta-3", new CrearContactoDTO("Sexto", "4421112299", "Otro")));
        servicio.eliminar("cuenta-3", servicio.listar("cuenta-3").get(0).id());
        org.junit.jupiter.api.Assertions.assertThrows(ContactoService.ConflictoException.class,
                () -> servicio.crear("cuenta-3", new CrearContactoDTO("Repetido", "4421112211", "Otro")));
        assertThat(servicio.listar("cuenta-3")).hasSize(4);
    }

    @Test
    void siFirestoreAgotaLosReintentosPorContencion_laPersonaRecibeUn409_noUn500() {
        var repo = new RepositoriosEnMemoria.Contactos() {
            @Override
            public synchronized ResultadoAlta guardarSiCabe(String cuentaId, ContactoDTO c, int maximo) {
                return ResultadoAlta.OCUPADO;
            }
        };
        var servicio = new ContactoService(java.util.Optional.of(repo));
        var e = org.junit.jupiter.api.Assertions.assertThrows(ContactoService.ConflictoException.class,
                () -> servicio.crear("cuenta-4", new CrearContactoDTO("Ana", "4421234567", "Otro")));
        assertThat(e.getMessage()).contains("Inténtalo de nuevo");
    }
}
