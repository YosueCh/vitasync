package com.vitasync.backend.usuarios.dto;

import java.util.List;

public record CrearUsuarioDTO(
        String nombreCompleto,
        String username,
        List<String> grupos) {
}
