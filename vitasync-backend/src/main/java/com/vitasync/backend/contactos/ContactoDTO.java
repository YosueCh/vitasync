package com.vitasync.backend.contactos;

/** Un contacto de emergencia de una cuenta: a quién avisar si algo pasa. */
public record ContactoDTO(String id, String nombre, String telefono, String relacion) {
}
