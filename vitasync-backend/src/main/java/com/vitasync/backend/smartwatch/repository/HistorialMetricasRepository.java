package com.vitasync.backend.smartwatch.repository;

import com.google.cloud.firestore.Firestore;
import com.google.cloud.firestore.Query;
import com.google.cloud.firestore.QueryDocumentSnapshot;
import com.vitasync.backend.smartwatch.dto.MetricasDTO;

import java.time.Instant;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutionException;

/**
 * DAO del historial de lecturas del smartwatch: la subcolección
 * "devices/{usuarioId}/historial" de Firestore.
 *
 * Cada vez que el reloj (o el firmware simulado) sincroniza, la lectura se
 * guarda como un documento nuevo; así las "cards" de la app móvil muestran la
 * última lectura de la base de datos y, al tocarlas, su historial.
 *
 * Igual que {@link DispositivoRepository}, se instancia en FirebaseConfig solo
 * cuando hay credenciales de Firebase.
 */
public class HistorialMetricasRepository {

    private static final String COLECCION = "devices";
    private static final String SUBCOLECCION = "historial";

    private final Firestore db;

    public HistorialMetricasRepository(Firestore db) {
        this.db = db;
    }

    /** Guarda una lectura. "ts" (milisegundos) permite ordenar sin depender del formato del texto. */
    public void guardar(String usuarioId, MetricasDTO m) {
        Instant momento = m.timestamp() != null ? m.timestamp() : Instant.now();
        Map<String, Object> doc = new HashMap<>();
        doc.put("pasos", m.pasos());
        doc.put("calorias", m.calorias());
        doc.put("suenoHoras", m.sueñoHoras());
        doc.put("frecuenciaCardiaca", m.frecuenciaCardiaca());
        doc.put("bateria", m.bateria());
        doc.put("timestamp", momento.toString());
        doc.put("ts", momento.toEpochMilli());
        try {
            db.collection(COLECCION).document(usuarioId).collection(SUBCOLECCION).add(doc).get();
        } catch (InterruptedException | ExecutionException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Error al guardar el historial en Firestore", e);
        }
    }

    /** Las últimas lecturas del usuario, de la más reciente a la más antigua. */
    public List<MetricasDTO> ultimas(String usuarioId, int limite) {
        try {
            return db.collection(COLECCION).document(usuarioId).collection(SUBCOLECCION)
                    .orderBy("ts", Query.Direction.DESCENDING)
                    .limit(limite)
                    .get().get()
                    .getDocuments().stream()
                    .map(HistorialMetricasRepository::aDTO)
                    .toList();
        } catch (InterruptedException | ExecutionException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Error al consultar el historial en Firestore", e);
        }
    }

    /** Borra TODO el historial de la cuenta (al eliminarla). Firestore no borra subcolecciones solo. */
    public void eliminarTodo(String usuarioId) {
        try {
            var coleccion = db.collection(COLECCION).document(usuarioId).collection(SUBCOLECCION);
            List<QueryDocumentSnapshot> lote;
            do {
                lote = coleccion.limit(100).get().get().getDocuments();
                for (QueryDocumentSnapshot d : lote) {
                    d.getReference().delete().get();
                }
            } while (!lote.isEmpty());
        } catch (InterruptedException | ExecutionException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Error al borrar el historial en Firestore", e);
        }
    }

    private static MetricasDTO aDTO(QueryDocumentSnapshot d) {
        String texto = d.getString("timestamp");
        return new MetricasDTO(
                numero(d, "pasos").intValue(),
                numero(d, "calorias").intValue(),
                numero(d, "suenoHoras").doubleValue(),
                numero(d, "frecuenciaCardiaca").intValue(),
                numero(d, "bateria").intValue(),
                texto == null ? null : Instant.parse(texto));
    }

    private static Number numero(QueryDocumentSnapshot d, String campo) {
        Object v = d.get(campo);
        return v instanceof Number n ? n : 0;
    }
}
