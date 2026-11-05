package com.vitasync.backend.contactos;

import com.google.cloud.firestore.CollectionReference;
import com.google.cloud.firestore.Firestore;
import com.google.cloud.firestore.Query;
import com.google.cloud.firestore.QueryDocumentSnapshot;

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

    /** Borra todos los contactos de la cuenta (al eliminarla). */
    public void eliminarTodos(String cuentaId) {
        try {
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
