package com.vitasync.backend.usuarios.dto;

/** Cuerpo de las peticiones de PIN. Solo viaja en el cuerpo, nunca en la URL ni en logs. */
public record PinDTO(String pin) {
}
