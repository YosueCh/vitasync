package com.vitasync.backend.seguridad;

import java.util.Optional;

/** Convierte el token de la cabecera Authorization en una {@link Identidad}; vacío si no es válido. */
public interface VerificadorToken {
    Optional<Identidad> verificar(String token);
}
