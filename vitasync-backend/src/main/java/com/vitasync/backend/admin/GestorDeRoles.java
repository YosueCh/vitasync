package com.vitasync.backend.admin;

import java.util.List;
import java.util.Optional;

/**
 * Dónde viven los roles de las personas (Práctica 7 dentro de VitaSync). En producción es Firebase Authentication
 * (claim «rol» del token); en las pruebas, una lista en memoria.
 */
public interface GestorDeRoles {

    /** Una persona con sesión en la app y su rol actual. */
    record Persona(String uid, String correo, String rol) {
    }

    List<Persona> listar();

    Optional<Persona> buscar(String uid);

    /** Cambia el rol. Si la persona tiene sesión abierta, lo adopta al renovar su token (hasta 1 hora o al volver a entrar). */
    void asignar(String uid, String rol);
}
