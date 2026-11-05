package com.vitasync.backend.seguridad;

/**
 * Quién hace la petición, según un token ya verificado (Práctica 10).
 * El UID lo pone Firebase Authentication; la aplicación cliente no puede inventarlo.
 *
 * @param uid UID de Firebase Authentication
 * @param rol "paciente" (por omisión), "medico" o "admin" (claim «rol» del token)
 */
public record Identidad(String uid, String rol) {

    public boolean esAdmin() {
        return "admin".equals(rol);
    }

    public boolean esMedico() {
        return "medico".equals(rol);
    }
}
