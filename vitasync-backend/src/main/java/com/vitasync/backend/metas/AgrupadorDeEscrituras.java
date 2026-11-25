package com.vitasync.backend.metas;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.AtomicLong;
import java.util.function.UnaryOperator;

/**
 * PRÁCTICA 12 · PER-11 · Escrituras agrupadas («group commit») sobre un mismo documento.
 *
 * <b>Problema medido:</b> cada cambio de metas es una transacción de Firestore (leer + escribir ≈ 3 viajes de red ≈
 * 270 ms) y Firestore las serializa por documento. Con 10 teléfonos guardando a la vez la 10.ª espera ≈ 2,7 s y con
 * 20 empezaron a aparecer errores HTTP 500 por contención entre transacciones.
 *
 * <b>Solución:</b> las peticiones que llegan para la misma cuenta mientras hay una transacción en curso se juntan en una
 * cola; cuando la transacción termina, TODAS las que esperaban se aplican una tras otra, en orden de llegada, dentro de
 * UNA sola transacción. El resultado es el mismo que si se hubieran ejecutado en serie (cada cambio sube la versión en
 * uno y cada petición con {@code version} se compara contra la versión que tendría en ese momento), pero con un viaje a
 * Firestore en lugar de N.
 *
 * Una cola por cuenta; un hilo del grupo atiende la cola (las peticiones solo esperan su resultado).
 */
final class AgrupadorDeEscrituras {

    static final int MAX_POR_LOTE = 100;

    /** Una petición de cambio de metas. */
    static final class Pedido {
        final Long versionEsperada;
        final UnaryOperator<MetasCuentaDTO> cambio;
        final CompletableFuture<MetasCuentaDTO> respuesta = new CompletableFuture<>();

        Pedido(Long versionEsperada, UnaryOperator<MetasCuentaDTO> cambio) {
            this.versionEsperada = versionEsperada;
            this.cambio = cambio;
        }
    }

    /**
     * Persiste un lote en UNA transacción. Devuelve, por cada pedido y en el mismo orden, su resultado: un
     * {@link MetasCuentaDTO} (guardado) o una {@link RuntimeException} (p. ej. {@link ConflictoDeVersionException}).
     * Si lanza, todos los pedidos del lote fallan con esa excepción.
     */
    interface Escritor {
        List<Object> escribir(String cuentaId, List<Pedido> lote) throws Exception;
    }

    private static final class Cola {
        final ArrayDeque<Pedido> pendientes = new ArrayDeque<>();
        boolean atendiendo;
    }

    private final Escritor escritor;
    private final Map<String, Cola> colas = new ConcurrentHashMap<>();
    private final ExecutorService hilos = Executors.newCachedThreadPool(r -> {
        Thread t = new Thread(r, "agrupador-metas");
        t.setDaemon(true);
        return t;
    });
    private final long esperaMaximaSeg;

    private final AtomicLong lotes = new AtomicLong();
    private final AtomicLong pedidos = new AtomicLong();

    AgrupadorDeEscrituras(Escritor escritor) {
        this(escritor, 60);
    }

    AgrupadorDeEscrituras(Escritor escritor, long esperaMaximaSeg) {
        this.escritor = escritor;
        this.esperaMaximaSeg = esperaMaximaSeg;
    }

    /** Encola el cambio y espera su resultado (lanza lo mismo que habría lanzado una transacción individual). */
    MetasCuentaDTO enviar(String cuentaId, Long versionEsperada, UnaryOperator<MetasCuentaDTO> cambio) {
        Pedido p = new Pedido(versionEsperada, cambio);
        Cola cola = colas.computeIfAbsent(cuentaId, k -> new Cola());
        boolean arrancar;
        synchronized (cola) {
            cola.pendientes.add(p);
            arrancar = !cola.atendiendo;
            if (arrancar) cola.atendiendo = true;
        }
        if (arrancar) hilos.execute(() -> atender(cuentaId, cola));
        try {
            return p.respuesta.get(esperaMaximaSeg, TimeUnit.SECONDS);
        } catch (ExecutionException e) {
            Throwable causa = e.getCause();
            if (causa instanceof RuntimeException r) throw r;
            throw new IllegalStateException("Error al guardar las metas", causa);
        } catch (TimeoutException e) {
            throw new IllegalStateException("Las metas no se guardaron a tiempo", e);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Guardado de metas interrumpido", e);
        }
    }

    private void atender(String cuentaId, Cola cola) {
        while (true) {
            List<Pedido> lote = new ArrayList<>();
            synchronized (cola) {
                if (cola.pendientes.isEmpty()) {
                    cola.atendiendo = false;
                    colas.remove(cuentaId, cola);
                    return;
                }
                while (!cola.pendientes.isEmpty() && lote.size() < MAX_POR_LOTE) lote.add(cola.pendientes.poll());
            }
            lotes.incrementAndGet();
            pedidos.addAndGet(lote.size());
            try {
                List<Object> resultados = escritor.escribir(cuentaId, lote);
                for (int i = 0; i < lote.size(); i++) {
                    Object r = resultados.get(i);
                    if (r instanceof RuntimeException e) lote.get(i).respuesta.completeExceptionally(e);
                    else lote.get(i).respuesta.complete((MetasCuentaDTO) r);
                }
            } catch (Throwable t) {
                for (Pedido p : lote) p.respuesta.completeExceptionally(t);
            }
        }
    }

    /**
     * Aplica un lote a las metas {@code actual}, en orden, como si fueran peticiones en serie. Es una función PURA (la
     * transacción de Firestore puede ejecutarla más de una vez al reintentar): no toca nada fuera de sus argumentos.
     */
    static Aplicacion aplicar(MetasCuentaDTO actual, List<Pedido> lote) {
        MetasCuentaDTO corriente = actual;
        List<Object> resultados = new ArrayList<>(lote.size());
        boolean hubo = false;
        for (Pedido p : lote) {
            if (p.versionEsperada != null && p.versionEsperada.longValue() != corriente.version()) {
                resultados.add(new ConflictoDeVersionException(corriente));
                continue;
            }
            try {
                MetasCuentaDTO nuevo = p.cambio.apply(corriente).conVersion(corriente.version() + 1);
                resultados.add(nuevo);
                corriente = nuevo;
                hubo = true;
            } catch (RuntimeException e) {
                resultados.add(e); // un pedido malo no hace fallar a los demás del lote
            }
        }
        return new Aplicacion(hubo ? corriente : null, resultados);
    }

    /** Resultado de aplicar un lote: el documento final a escribir (null si nada cambió) y el resultado por pedido. */
    record Aplicacion(MetasCuentaDTO documentoFinal, List<Object> resultados) {}

    long lotesEjecutados() {
        return lotes.get();
    }

    long pedidosAtendidos() {
        return pedidos.get();
    }
}
