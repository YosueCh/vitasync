package com.vitasync.backend.usuarios.repository;

import com.google.cloud.firestore.Firestore;
import com.google.cloud.firestore.QueryDocumentSnapshot;
import com.vitasync.backend.usuarios.model.Usuario;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutionException;

/**
 * DAO sobre la colección "usuarios" de Firestore. Igual que
 * DispositivoRepository, se instancia manualmente en FirebaseConfig (no
 * es un @Repository escaneado) porque solo debe existir cuando hay
 * credenciales de Firebase disponibles.
 */
public class UsuarioRepository {

    private static final String COLECCION = "usuarios";
    /** Un documento por usuario ocupado: es lo que hace que el usuario sea ÚNICO (ver guardarSiUsernameLibre). */
    private static final String RESERVAS = "usernames";
    private final Firestore db;

    public UsuarioRepository(Firestore db) {
        this.db = db;
    }

    public void guardar(Usuario u) {
        try {
            db.collection(COLECCION).document(u.getId()).set(u).get();
        } catch (InterruptedException | ExecutionException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Error al guardar en Firestore", e);
        }
    }

    public Usuario buscarPorId(String id) {
        try {
            var snap = db.collection(COLECCION).document(id).get().get();
            return snap.exists() ? snap.toObject(Usuario.class) : null;
        } catch (InterruptedException | ExecutionException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Error al consultar Firestore", e);
        }
    }

    public List<Usuario> listarTodos() {
        try {
            List<Usuario> resultado = new ArrayList<>();
            for (QueryDocumentSnapshot doc : db.collection(COLECCION).get().get().getDocuments()) {
                resultado.add(doc.toObject(Usuario.class));
            }
            return resultado;
        } catch (InterruptedException | ExecutionException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Error al listar en Firestore", e);
        }
    }

    /**
     * Las cuentas de una persona con una consulta filtrada por el servidor. Antes se traían TODAS las cuentas de todas
     * las personas y se filtraba en memoria (WB-HALLAZGO-10: más datos de los necesarios y cada vez más lento).
     */
    public List<Usuario> listarPorPropietario(String propietarioUid) {
        try {
            List<Usuario> resultado = new ArrayList<>();
            for (QueryDocumentSnapshot doc : db.collection(COLECCION).whereEqualTo("propietarioUid", propietarioUid).get().get().getDocuments()) {
                resultado.add(doc.toObject(Usuario.class));
            }
            return resultado;
        } catch (InterruptedException | ExecutionException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Error al consultar las cuentas en Firestore", e);
        }
    }

    /** ¿Ya existe una cuenta con ese usuario? Consulta con límite 1 en vez de leer toda la colección (WB-HALLAZGO-10). */
    public boolean existeUsername(String username) {
        try {
            return !db.collection(COLECCION).whereEqualTo("username", username).limit(1).get().get().isEmpty();
        } catch (InterruptedException | ExecutionException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Error al consultar el usuario en Firestore", e);
        }
    }

    /**
     * Alta ATÓMICA con usuario único (WB-HALLAZGO-9). Firestore no tiene restricción UNIQUE: dos altas simultáneas con
     * el mismo usuario pasaban la comprobación y se guardaban las dos. Aquí el usuario se «reserva» creando el
     * documento «usernames/{usuario}» en la misma transacción que guarda la cuenta; si ya existe, no se guarda nada.
     *
     * @return false si ese usuario ya estaba reservado por otra cuenta
     */
    public boolean guardarSiUsernameLibre(Usuario u) {
        var reserva = db.collection(RESERVAS).document(u.getUsername());
        try {
            return db.runTransaction(tx -> {
                if (tx.get(reserva).get().exists()) return false;
                tx.set(reserva, java.util.Map.of("cuentaId", u.getId()));
                tx.set(db.collection(COLECCION).document(u.getId()), u);
                return true;
            }).get();
        } catch (InterruptedException | ExecutionException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Error al guardar la cuenta en Firestore", e);
        }
    }

    /** Elimina la cuenta y libera su usuario reservado, para que otra persona pueda volver a usarlo. */
    public void eliminar(String id) {
        try {
            var doc = db.collection(COLECCION).document(id);
            String username = doc.get().get().getString("username");
            if (username != null) db.collection(RESERVAS).document(username).delete().get();
            doc.delete().get();
        } catch (InterruptedException | ExecutionException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Error al eliminar en Firestore", e);
        }
    }
}
