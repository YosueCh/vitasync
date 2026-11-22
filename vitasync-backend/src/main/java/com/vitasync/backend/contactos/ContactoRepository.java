package com.vitasync.backend.contactos;

import com.google.cloud.firestore.CollectionReference;
import com.google.cloud.firestore.DocumentReference;
import com.google.cloud.firestore.FieldValue;
import com.google.cloud.firestore.Firestore;
import com.google.cloud.firestore.Query;
import com.google.cloud.firestore.QueryDocumentSnapshot;
import com.google.cloud.firestore.SetOptions;
import com.google.cloud.firestore.TransactionOptions;
import com.google.api.gax.rpc.AbortedException;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutionException;

/**
 * Contactos de emergencia en Firestore: subcolección «usuarios/{cuentaId}/contactos». Cuelgan de la cuenta, así
 * las reglas de seguridad y el borrado de la cuenta los alcanzan igual que a su reloj y su historial.
 * Como los demás DAO, se instancia en FirebaseConfig y solo existe con credenciales de Firebase.
 */
public class ContactoRepository {

    private static final String COLECCION = "usuarios";
    private static final String SUBCOLECCION = "contactos";

    private final Firestore db;

    public ContactoRepository(Firestore db) {
        this.db = db;
    }

    private CollectionReference de(String cuentaId) {
        return db.collection(COLECCION).document(cuentaId).collection(SUBCOLECCION);
    }

    /** Los contactos de la cuenta, del más antiguo al más reciente. */
    public List<ContactoDTO> listar(String cuentaId) {
        try {
            return de(cuentaId).orderBy("creadoEn", Query.Direction.ASCENDING).get().get()
                    .getDocuments().stream().map(ContactoRepository::aDTO).toList();
        } catch (InterruptedException | ExecutionException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Error al consultar los contactos en Firestore", e);
        }
    }

    public void guardar(String cuentaId, ContactoDTO c) {
        Map<String, Object> doc = new HashMap<>();
        doc.put("nombre", c.nombre());
        doc.put("telefono", c.telefono());
        doc.put("relacion", c.relacion());
        doc.put("creadoEn", System.currentTimeMillis());
        try {
            de(cuentaId).document(c.id()).set(doc).get();
        } catch (InterruptedException | ExecutionException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Error al guardar el contacto en Firestore", e);
        }
    }

    /** true si existía y se eliminó; false si no existía (Firestore, solo, «elimina con éxito» lo que no existe). */
    public boolean eliminar(String cuentaId, String contactoId) {
        try {
            var ref = de(cuentaId).document(contactoId);
            if (!ref.get().get().exists()) return false;
            ref.delete().get();
            return true;
        } catch (InterruptedException | ExecutionException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Error al eliminar el contacto en Firestore", e);
        }
    }

    /** Resultado de {@link #guardarSiCabe}. */
    public enum ResultadoAlta {
        CREADO, LIMITE_ALCANZADO, TELEFONO_REPETIDO,
        /** Demasiadas altas simultáneas sobre la misma cuenta: se agotaron los reintentos de la transacción. */
        OCUPADO
    }

    /** Intentos de la transacción de alta (Firestore usa 5 por omisión, insuficiente con altas muy simultáneas). */
    private static final int INTENTOS_TRANSACCION = 25;

    /**
     * Alta ATÓMICA (WB-HALLAZGO-8): comprueba el máximo y el teléfono repetido y guarda dentro de UNA transacción.
     *
     * Antes el servicio hacía «leer → comprobar → guardar» en tres pasos sueltos y varias altas simultáneas se colaban
     * por encima del máximo. Para que las altas de una misma cuenta se serialicen sin depender de cómo trate
     * Firestore las inserciones nuevas dentro de una consulta, todas leen y escriben un documento «cerrojo» común
     * (usuarios/{cuenta}/preferencias/cerrojo-contactos): dos transacciones que lo tocan chocan y una se reintenta.
     */
    public ResultadoAlta guardarSiCabe(String cuentaId, ContactoDTO c, int maximo) {
        DocumentReference cerrojo = db.collection(COLECCION).document(cuentaId).collection("preferencias").document("cerrojo-contactos");
        try {
            return db.runTransaction(tx -> {
                tx.get(cerrojo).get();
                var actuales = tx.get(de(cuentaId)).get().getDocuments();
                if (actuales.size() >= maximo) return ResultadoAlta.LIMITE_ALCANZADO;
                if (actuales.stream().anyMatch(d -> c.telefono().equals(d.getString("telefono")))) return ResultadoAlta.TELEFONO_REPETIDO;
                Map<String, Object> doc = new HashMap<>();
                doc.put("nombre", c.nombre());
                doc.put("telefono", c.telefono());
                doc.put("relacion", c.relacion());
                doc.put("creadoEn", System.currentTimeMillis());
                tx.set(de(cuentaId).document(c.id()), doc);
                tx.set(cerrojo, Map.of("altas", FieldValue.increment(1)), SetOptions.merge());
                return ResultadoAlta.CREADO;
            }, TransactionOptions.createReadWriteOptionsBuilder().setNumberOfAttempts(INTENTOS_TRANSACCION).build()).get();
        } catch (ExecutionException e) {
            // Con muchas altas simultáneas Firestore aborta algunas por «contención entre transacciones» (la prueba con
            // 10 altas a la vez lo mostró): se agotan los reintentos y se le pide a la persona que lo intente de nuevo.
            for (Throwable t = e; t != null; t = t.getCause()) {
                if (t instanceof AbortedException) return ResultadoAlta.OCUPADO;
            }
            throw new IllegalStateException("Error al guardar el contacto en Firestore", e);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Error al guardar el contacto en Firestore", e);
        }
    }

    /** Borra todos los contactos de la cuenta (al eliminarla), y el cerrojo que usa {@link #guardarSiCabe}. */
    public void eliminarTodos(String cuentaId) {
        try {
            db.collection(COLECCION).document(cuentaId).collection("preferencias").document("cerrojo-contactos").delete().get();
            List<QueryDocumentSnapshot> lote;
            do {
                lote = de(cuentaId).limit(100).get().get().getDocuments();
                for (QueryDocumentSnapshot d : lote) d.getReference().delete().get();
            } while (!lote.isEmpty());
        } catch (InterruptedException | ExecutionException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Error al borrar los contactos en Firestore", e);
        }
    }

    private static ContactoDTO aDTO(QueryDocumentSnapshot d) {
        return new ContactoDTO(d.getId(), d.getString("nombre"), d.getString("telefono"), d.getString("relacion"));
    }
}
