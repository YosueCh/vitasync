package com.vitasync.backend.contactos;

/** Cuerpo de POST /api/contactos. La cuenta dueña sale de ?usuarioId= (y se comprueba contra el token), no del cuerpo. */
public record CrearContactoDTO(String nombre, String telefono, String relacion) {
}
