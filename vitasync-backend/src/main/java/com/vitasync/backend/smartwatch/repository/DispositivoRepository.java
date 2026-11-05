package com.vitasync.backend.smartwatch.repository;

import com.google.cloud.firestore.DocumentSnapshot;
import com.google.cloud.firestore.Firestore;
import com.vitasync.backend.smartwatch.model.Dispositivo;

import java.util.concurrent.ExecutionException;

/**
 * DAO que encapsula el acceso a la colección "devices" de Firestore.
 * Se instancia manualmente en FirebaseConfig (no es un @Repository
 * escaneado por Spring) porque solo debe existir cuando hay credenciales
 * de Firebase disponibles.
 *
 * Cada documento se guarda con el usuarioId como ID de documento: un
 * dispositivo por cuenta, para que el reloj y la web muestren datos
 * distintos según qué usuario esté activo, en vez de un solo dispositivo
 * global compartido por cualquiera que entre.
 */
public class DispositivoRepository {

    private static final String COLECCION = "devices";
    private final Firestore db;

    public DispositivoRepository(Firestore db) {
        this.db = db;
    }

    /** Crea o actualiza el dispositivo del usuario dado (operación bloqueante con .get()). */
    public void guardar(String usuarioId, Dispositivo d) {
        try {
            db.collection(COLECCION).document(usuarioId).set(d).get();
        } catch (InterruptedException | ExecutionException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Error al guardar en Firestore", e);
        }
    }

    /** Elimina el dispositivo de la cuenta (no falla si no existe). */
    public void eliminar(String usuarioId) {
        try {
            db.collection(COLECCION).document(usuarioId).delete().get();
        } catch (InterruptedException | ExecutionException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Error al eliminar en Firestore", e);
        }
    }

    /** Devuelve el dispositivo del usuario dado, o null si nunca se ha conectado uno. */
    public Dispositivo buscarPorUsuario(String usuarioId) {
        try {
            DocumentSnapshot snap = db.collection(COLECCION).document(usuarioId).get().get();
            return snap.exists() ? snap.toObject(Dispositivo.class) : null;
        } catch (InterruptedException | ExecutionException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Error al consultar Firestore", e);
        }
    }
}
