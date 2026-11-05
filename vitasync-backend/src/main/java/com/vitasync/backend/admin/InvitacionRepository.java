package com.vitasync.backend.admin;

import com.google.cloud.firestore.DocumentReference;
import com.google.cloud.firestore.DocumentSnapshot;
import com.google.cloud.firestore.Firestore;
import com.google.cloud.firestore.QueryDocumentSnapshot;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ExecutionException;

/**
 * Invitaciones de un solo uso (Práctica 7 dentro de VitaSync): documento «invitaciones/{codigo}» en Firestore.
 * Canjear es una TRANSACCIÓN (leer, comprobar que sigue libre, marcar como usada) para que dos personas con el mismo
 * código no puedan usarlo las dos. Solo existe con credenciales de Firebase; las reglas niegan todo acceso desde
 * los clientes (solo el servidor la toca).
 */
public class InvitacionRepository {

    /** Una invitación: rol que concede, cuándo caduca y quién la usó (null = libre). */
    public record Invitacion(String codigo, String rol, long creadaEn, long venceEn, String usadaPor) {
    }

    private static final String COLECCION = "invitaciones";

    private final Firestore db;

    public InvitacionRepository(Firestore db) {
        this.db = db;
    }

    private DocumentReference ref(String codigo) {
        return db.collection(COLECCION).document(codigo);
    }

    public void guardar(Invitacion i) {
        try {
            ref(i.codigo()).set(aMapa(i)).get();
        } catch (InterruptedException | ExecutionException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Error al guardar la invitación en Firestore", e);
        }
    }

    public List<Invitacion> listar() {
        try {
            List<Invitacion> lista = new ArrayList<>();
            for (QueryDocumentSnapshot d : db.collection(COLECCION).get().get().getDocuments()) lista.add(aDTO(d));
            return lista;
        } catch (InterruptedException | ExecutionException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Error al listar las invitaciones en Firestore", e);
        }
    }

    /**
     * Marca la invitación como usada por {@code uid} si existe, está libre y no ha caducado.
     *
     * @throws InvitacionInvalidaException con el motivo (no existe, ya usada o caducada)
     */
    public Invitacion canjear(String codigo, String uid, long ahora) {
        DocumentReference ref = ref(codigo);
        try {
            return db.runTransaction(tx -> {
                DocumentSnapshot snap = tx.get(ref).get();
                if (!snap.exists()) throw new InvitacionInvalidaException("Ese código no existe.");
                Invitacion actual = aDTO(snap);
                if (actual.usadaPor() != null) throw new InvitacionInvalidaException("Ese código ya se usó.");
                if (ahora > actual.venceEn()) throw new InvitacionInvalidaException("Ese código caducó.");
                Invitacion usada = new Invitacion(actual.codigo(), actual.rol(), actual.creadaEn(), actual.venceEn(), uid);
                tx.set(ref, aMapa(usada));
                return usada;
            }).get();
        } catch (ExecutionException e) {
            for (Throwable t = e; t != null; t = t.getCause()) {
                if (t instanceof InvitacionInvalidaException i) throw i;
            }
            throw new IllegalStateException("Error al canjear la invitación en Firestore", e);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Error al canjear la invitación en Firestore", e);
        }
    }

    public Optional<Invitacion> obtener(String codigo) {
        try {
            DocumentSnapshot d = ref(codigo).get().get();
            return d.exists() ? Optional.of(aDTO(d)) : Optional.empty();
        } catch (InterruptedException | ExecutionException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Error al consultar la invitación en Firestore", e);
        }
    }

    private static Map<String, Object> aMapa(Invitacion i) {
        Map<String, Object> m = new HashMap<>();
        m.put("rol", i.rol());
        m.put("creadaEn", i.creadaEn());
        m.put("venceEn", i.venceEn());
        m.put("usadaPor", i.usadaPor());
        return m;
    }

    private static Invitacion aDTO(DocumentSnapshot d) {
        return new Invitacion(d.getId(), d.getString("rol"),
                d.getLong("creadaEn") == null ? 0 : d.getLong("creadaEn"),
                d.getLong("venceEn") == null ? 0 : d.getLong("venceEn"),
                d.getString("usadaPor"));
    }

    /** La invitación no se puede usar (no existe, ya se usó o caducó). */
    public static class InvitacionInvalidaException extends RuntimeException {
        public InvitacionInvalidaException(String mensaje) {
            super(mensaje);
        }
    }
}
