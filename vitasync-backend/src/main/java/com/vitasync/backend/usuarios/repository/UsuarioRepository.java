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

    public void eliminar(String id) {
        try {
            db.collection(COLECCION).document(id).delete().get();
        } catch (InterruptedException | ExecutionException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Error al eliminar en Firestore", e);
        }
    }
}
