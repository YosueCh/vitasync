package com.vitasync.backend.cast.repository;

import com.google.cloud.firestore.Firestore;
import com.vitasync.backend.cast.model.CastSession;

import java.util.concurrent.ExecutionException;

/**
 * DAO sobre la colección "tv_sessions" de Firestore. Mismo patrón que
 * DispositivoRepository / UsuarioRepository: instanciado manualmente en
 * FirebaseConfig, solo existe cuando hay credenciales de Firebase.
 */
public class CastSessionRepository {

    private static final String COLECCION = "tv_sessions";
    private final Firestore db;

    public CastSessionRepository(Firestore db) {
        this.db = db;
    }

    public void guardar(CastSession s) {
        try {
            db.collection(COLECCION).document(s.getCodigo()).set(s).get();
        } catch (InterruptedException | ExecutionException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Error al guardar en Firestore", e);
        }
    }

    public CastSession buscarPorCodigo(String codigo) {
        try {
            var snap = db.collection(COLECCION).document(codigo).get().get();
            return snap.exists() ? snap.toObject(CastSession.class) : null;
        } catch (InterruptedException | ExecutionException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Error al consultar Firestore", e);
        }
    }
}
