package com.vitasync.backend.metas;

import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.UnaryOperator;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * PRÁCTICA 12 · PER-11 · Escrituras agrupadas. Sin Firestore: el «escritor» es una réplica en memoria que aplica la
 * misma función pura que usa la transacción real, con una pausa que imita los ≈270 ms de la transacción.
 */
class AgrupadorDeEscriturasTest {

    private static UnaryOperator<MetasCuentaDTO> pasos(int p) {
        return a -> new MetasCuentaDTO(p, a.metaCalorias(), a.metaSueno(), a.version(), "t");
    }

    private static UnaryOperator<MetasCuentaDTO> calorias(int c) {
        return a -> new MetasCuentaDTO(a.metaPasos(), c, a.metaSueno(), a.version(), "t");
    }

    /** Almacén en memoria: un «documento» y un contador de transacciones. */
    private static class Almacen implements AgrupadorDeEscrituras.Escritor {
        volatile MetasCuentaDTO doc = MetasCuentaDTO.PREDETERMINADAS;
        final AtomicInteger transacciones = new AtomicInteger();
        final List<Integer> tamanos = Collections.synchronizedList(new ArrayList<>());
        final long pausaMs;
        RuntimeException fallar;

        Almacen(long pausaMs) {
            this.pausaMs = pausaMs;
        }

        @Override
        public List<Object> escribir(String cuentaId, List<AgrupadorDeEscrituras.Pedido> lote) throws Exception {
            transacciones.incrementAndGet();
            tamanos.add(lote.size());
            if (pausaMs > 0) Thread.sleep(pausaMs);
            if (fallar != null) throw fallar;
            AgrupadorDeEscrituras.Aplicacion ap = AgrupadorDeEscrituras.aplicar(doc, lote);
            if (ap.documentoFinal() != null) doc = ap.documentoFinal();
            return ap.resultados();
        }
    }

    // ---------------- función pura ----------------

    @Test
    void aplicar_cadaCambioSubeLaVersionEnUno_comoSiFueranEnSerie() {
        var lote = List.of(new AgrupadorDeEscrituras.Pedido(null, pasos(6000)), new AgrupadorDeEscrituras.Pedido(null, calorias(300)),
                new AgrupadorDeEscrituras.Pedido(null, pasos(7000)));

        var ap = AgrupadorDeEscrituras.aplicar(MetasCuentaDTO.PREDETERMINADAS, lote);

        assertThat(ap.resultados()).extracting(r -> ((MetasCuentaDTO) r).version()).containsExactly(1L, 2L, 3L);
        assertThat(ap.documentoFinal().metaPasos()).isEqualTo(7000); // el último gana en el mismo campo
        assertThat(ap.documentoFinal().metaCalorias()).isEqualTo(300); // y el otro campo no se pierde
    }

    @Test
    void aplicar_conVersionEsperada_soloGanaElPrimeroDeLosQueTraenLaMismaVersion() {
        var lote = new ArrayList<AgrupadorDeEscrituras.Pedido>();
        for (int i = 0; i < 5; i++) lote.add(new AgrupadorDeEscrituras.Pedido(0L, pasos(6000 + i)));

        var ap = AgrupadorDeEscrituras.aplicar(MetasCuentaDTO.PREDETERMINADAS, lote);

        assertThat(ap.resultados().get(0)).isInstanceOf(MetasCuentaDTO.class);
        for (int i = 1; i < 5; i++) assertThat(ap.resultados().get(i)).isInstanceOf(ConflictoDeVersionException.class);
        assertThat(ap.documentoFinal().version()).isEqualTo(1);
        assertThat(ap.documentoFinal().metaPasos()).isEqualTo(6000);
        // El conflicto lleva las metas ACTUALES (con la versión ya subida por el ganador)
        assertThat(((ConflictoDeVersionException) ap.resultados().get(1)).getActual().version()).isEqualTo(1);
    }

    @Test
    void aplicar_unaVersionEncadenadaEnElMismoLoteSiEsValida() {
        var lote = List.of(new AgrupadorDeEscrituras.Pedido(0L, pasos(6000)), new AgrupadorDeEscrituras.Pedido(1L, calorias(250)));

        var ap = AgrupadorDeEscrituras.aplicar(MetasCuentaDTO.PREDETERMINADAS, lote);

        assertThat(ap.resultados()).allMatch(r -> r instanceof MetasCuentaDTO);
        assertThat(ap.documentoFinal().version()).isEqualTo(2);
    }

    @Test
    void aplicar_unPedidoQueLanzaNoHaceFallarALosDemas() {
        var malo = new AgrupadorDeEscrituras.Pedido(null, a -> { throw new IllegalArgumentException("meta inválida"); });
        var bueno = new AgrupadorDeEscrituras.Pedido(null, pasos(9000));

        var ap = AgrupadorDeEscrituras.aplicar(MetasCuentaDTO.PREDETERMINADAS, List.of(malo, bueno));

        assertThat(ap.resultados().get(0)).isInstanceOf(IllegalArgumentException.class);
        assertThat(((MetasCuentaDTO) ap.resultados().get(1)).metaPasos()).isEqualTo(9000);
        assertThat(ap.documentoFinal().version()).isEqualTo(1);
    }

    @Test
    void aplicar_sinCambiosNoGeneraDocumentoFinal() {
        var ap = AgrupadorDeEscrituras.aplicar(MetasCuentaDTO.PREDETERMINADAS, List.of(new AgrupadorDeEscrituras.Pedido(5L, pasos(1))));
        assertThat(ap.documentoFinal()).isNull();
    }

    // ---------------- cola y concurrencia ----------------

    @Test
    void unaPeticionSola_seEjecutaEnUnaTransaccion() {
        Almacen a = new Almacen(0);
        var agrupador = new AgrupadorDeEscrituras(a);

        MetasCuentaDTO r = agrupador.enviar("c1", null, pasos(8000));

        assertThat(r.metaPasos()).isEqualTo(8000);
        assertThat(r.version()).isEqualTo(1);
        assertThat(a.transacciones).hasValue(1);
    }

    @Test
    void veintePeticionesSimultaneas_seAgrupan_yNingunaSePierde() throws Exception {
        Almacen a = new Almacen(120); // la transacción dura 120 ms: mientras tanto se acumulan las demás
        var agrupador = new AgrupadorDeEscrituras(a);
        int n = 20;
        ExecutorService pool = Executors.newFixedThreadPool(n);
        CountDownLatch salida = new CountDownLatch(1);
        List<Future<MetasCuentaDTO>> futuros = new ArrayList<>();
        for (int i = 0; i < n; i++) {
            int valor = 8000 + i;
            futuros.add(pool.submit(() -> { salida.await(); return agrupador.enviar("c1", null, pasos(valor)); }));
        }
        salida.countDown();
        List<Long> versiones = new ArrayList<>();
        for (Future<MetasCuentaDTO> f : futuros) versiones.add(f.get(10, TimeUnit.SECONDS).version());
        pool.shutdown();

        assertThat(versiones).as("cada petición recibió una versión distinta y consecutiva").doesNotHaveDuplicates()
                .containsExactlyInAnyOrderElementsOf(java.util.stream.LongStream.rangeClosed(1, n).boxed().toList());
        assertThat(a.doc.version()).isEqualTo(n);
        assertThat(a.transacciones.get()).as("20 peticiones en muy pocas transacciones").isLessThanOrEqualTo(4);
        assertThat(agrupador.pedidosAtendidos()).isEqualTo(n);
    }

    @Test
    void diezConLaMismaVersion_exactamenteUnaGana_ylasDemasRecibenConflicto() throws Exception {
        Almacen a = new Almacen(80);
        var agrupador = new AgrupadorDeEscrituras(a);
        ExecutorService pool = Executors.newFixedThreadPool(10);
        CountDownLatch salida = new CountDownLatch(1);
        List<Future<Object>> futuros = new ArrayList<>();
        for (int i = 0; i < 10; i++) {
            int valor = 6000 + i;
            futuros.add(pool.submit(() -> {
                salida.await();
                try {
                    return agrupador.enviar("c1", 0L, pasos(valor));
                } catch (ConflictoDeVersionException e) {
                    return e;
                }
            }));
        }
        salida.countDown();
        int ganadores = 0, conflictos = 0;
        for (Future<Object> f : futuros) {
            Object r = f.get(10, TimeUnit.SECONDS);
            if (r instanceof MetasCuentaDTO) ganadores++;
            else if (r instanceof ConflictoDeVersionException) conflictos++;
        }
        pool.shutdown();

        assertThat(ganadores).isEqualTo(1);
        assertThat(conflictos).isEqualTo(9);
        assertThat(a.doc.version()).isEqualTo(1);
    }

    @Test
    void cuentasDistintas_noSeMezclanEnElMismoLote() throws Exception {
        Almacen a = new Almacen(0) {
            @Override
            public List<Object> escribir(String cuentaId, List<AgrupadorDeEscrituras.Pedido> lote) throws Exception {
                assertThat(cuentaId).isIn("c1", "c2");
                return super.escribir(cuentaId, lote);
            }
        };
        var agrupador = new AgrupadorDeEscrituras(a);
        agrupador.enviar("c1", null, pasos(1000 + 1));
        agrupador.enviar("c2", null, pasos(2000));
        assertThat(a.transacciones).hasValue(2);
    }

    @Test
    void siLaTransaccionFalla_todosLosDelLoteReciben_elMismoError_yLaColaSigueFuncionando() throws Exception {
        Almacen a = new Almacen(60);
        a.fallar = new IllegalStateException("Firestore caído");
        var agrupador = new AgrupadorDeEscrituras(a);
        ExecutorService pool = Executors.newFixedThreadPool(4);
        List<Future<Object>> futuros = new ArrayList<>();
        for (int i = 0; i < 4; i++) {
            futuros.add(pool.submit(() -> {
                try {
                    return agrupador.enviar("c1", null, pasos(7000));
                } catch (IllegalStateException e) {
                    return e;
                }
            }));
        }
        for (Future<Object> f : futuros) assertThat(f.get(10, TimeUnit.SECONDS)).isInstanceOf(IllegalStateException.class);

        a.fallar = null; // Firestore vuelve: la cola no quedó atascada
        assertThat(agrupador.enviar("c1", null, pasos(7100)).metaPasos()).isEqualTo(7100);
        pool.shutdown();
    }

    @Test
    void unaExcepcionDeNegocioDeUnPedido_sePropagaTalCual() {
        Almacen a = new Almacen(0);
        var agrupador = new AgrupadorDeEscrituras(a);

        assertThatThrownBy(() -> agrupador.enviar("c1", 9L, pasos(1)))
                .isInstanceOf(ConflictoDeVersionException.class);
    }

    @Test
    void elTamanoDelLote_nuncaPasaDelMaximo() throws Exception {
        Almacen a = new Almacen(150);
        var agrupador = new AgrupadorDeEscrituras(a);
        int n = AgrupadorDeEscrituras.MAX_POR_LOTE + 60;
        ExecutorService pool = Executors.newFixedThreadPool(n);
        CountDownLatch salida = new CountDownLatch(1);
        List<Future<MetasCuentaDTO>> futuros = new ArrayList<>();
        for (int i = 0; i < n; i++) futuros.add(pool.submit(() -> { salida.await(); return agrupador.enviar("c1", null, pasos(9000)); }));
        salida.countDown();
        for (Future<MetasCuentaDTO> f : futuros) f.get(20, TimeUnit.SECONDS);
        pool.shutdown();

        assertThat(a.tamanos).allMatch(t -> t <= AgrupadorDeEscrituras.MAX_POR_LOTE);
        assertThat(a.tamanos.stream().mapToInt(Integer::intValue).sum()).isEqualTo(n);
    }
}
