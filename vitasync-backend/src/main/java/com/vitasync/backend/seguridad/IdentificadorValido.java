package com.vitasync.backend.seguridad;

import java.util.regex.Pattern;

/**
 * Qué se acepta como identificador de cuenta que llega en la URL o en un parámetro (WB-HALLAZGO-4).
 *
 * Los ids se usan como nombre de documento de Firestore. Sin esta validación, un valor como «a/b» (una ruta), uno de
 * 2000 caracteres o uno reservado por Firestore («__x__») hacía fallar al servidor con HTTP 500 en vez de rechazarse
 * con 400. Se acepta lo mismo que ya aceptaba el chat: letras, números, guion y guion bajo, de 1 a 64 caracteres, y
 * nunca la forma «__algo__», que Firestore reserva.
 */
public final class IdentificadorValido {

    private static final Pattern FORMA = Pattern.compile("^[A-Za-z0-9_-]{1,64}$");
    private static final Pattern RESERVADO = Pattern.compile("^__.*__$");

    private IdentificadorValido() {
    }

    public static boolean esValido(String id) {
        return id != null && FORMA.matcher(id).matches() && !RESERVADO.matcher(id).matches();
    }
}
