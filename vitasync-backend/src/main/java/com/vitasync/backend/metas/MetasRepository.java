package com.vitasync.backend.metas;

import com.google.cloud.firestore.DocumentReference;
import com.google.cloud.firestore.DocumentSnapshot;
import com.google.cloud.firestore.Firestore;

import java.util.HashMap;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ExecutionException;
import java.util.function.UnaryOperator;

/**
 * Metas de la cuenta en Firestore: documento «usuarios/{cuentaId}/preferencias/metas». Cuelga de la cuenta, así
 * las reglas de seguridad y el borrado de la cuenta lo alcanzan. Como los demás DAO, se instancia en
 * FirebaseConfig y solo existe con credenciales de Firebase.
 *
 * El cambio se hace en una TRANSACCIÓN de Firestore (leer, comprobar la versión, escribir): así dos teléfonos que
 * guardan al mismo tiempo no pueden pisarse sin que el servidor lo note.
 */
public class MetasRepository {

    private static final String COLECCION = "usuarios";
    private static final String SUBCOLECCION = "preferencias";
    private static final String DOCUMENTO = "metas";

    private final Firestore db;

    public MetasRepository(Firestore db) {
        this.db = db;
    }

    private DocumentReference ref(String cuentaId) {
        return db.collection(COLECCION).document(cuentaId).collection(SUBCOLECCION).document(DOCUMENTO);
    }

    /** Las metas guardadas, o vacío si nadie las ha editado nunca. */
    public Optional<MetasCuentaDTO> obtener(String cuentaId) {
        try {
            DocumentSnapshot snap = ref(cuentaId).get().get();
            return snap.exists() ? Optional.of(aDTO(snap)) : Optional.empty();
        } catch (InterruptedException | ExecutionException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Error al consultar las metas en Firestore", e);
        }
    }

    /**
     * Aplica {@code cambio} a las metas actuales (o a las predeterminadas) y sube la versión, todo en una transacción.
     *
     * @param versionEsperada si no es null, solo guarda cuando la versión actual es exactamente esa; si no,
     *                        lanza {@link ConflictoDeVersionException} con las metas actuales
     */
    public MetasCuentaDTO actualizar(String cuentaId, Long versionEsperada, UnaryOperator<MetasCuentaDTO> cambio) {
        DocumentReference ref = ref(cuentaId);
        try {
            return db.runTransaction(tx -> {
                DocumentSnapshot snap = tx.get(ref).get();
                MetasCuentaDTO actual = snap.exists() ? aDTO(snap) : MetasCuentaDTO.PREDETERMINADAS;
                if (versionEsperada != null && versionEsperada != actual.version()) {
                    throw new ConflictoDeVersionException(actual);
                }
                MetasCuentaDTO nuevo = cambio.apply(actual).conVersion(actual.version() + 1);
                tx.set(ref, aMapa(nuevo));
                return nuevo;
            }).get();
        } catch (ExecutionException e) {
            // La excepción de la transacción llega envuelta: se busca el conflicto en la cadena de causas.
            for (Throwable t = e; t != null; t = t.getCause()) {
                if (t instanceof ConflictoDeVersionException c) throw c;
            }
            throw new IllegalStateException("Error al guardar las metas en Firestore", e);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Error al guardar las metas en Firestore", e);
        }
    }

    public void eliminar(String cuentaId) {
        try {
            ref(cuentaId).delete().get();
        } catch (InterruptedException | ExecutionException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Error al eliminar las metas en Firestore", e);
        }
    }

    private static Map<String, Object> aMapa(MetasCuentaDTO m) {
        Map<String, Object> doc = new HashMap<>();
        doc.put("metaPasos", m.metaPasos());
        doc.put("metaCalorias", m.metaCalorias());
        doc.put("metaSueno", m.metaSueno());
        doc.put("version", m.version());
        doc.put("actualizadaPor", m.actualizadaPor());
        doc.put("actualizadaEn", System.currentTimeMillis());
        return doc;
    }

    private static MetasCuentaDTO aDTO(DocumentSnapshot d) {
        return new MetasCuentaDTO(
                numero(d, "metaPasos").intValue(),
                numero(d, "metaCalorias").intValue(),
                numero(d, "metaSueno").doubleValue(),
                numero(d, "version").longValue(),
                d.getString("actualizadaPor") == null ? "—" : d.getString("actualizadaPor"));
    }

    private static Number numero(DocumentSnapshot d, String campo) {
        Object v = d.get(campo);
        return v instanceof Number n ? n : 0;
    }
}
