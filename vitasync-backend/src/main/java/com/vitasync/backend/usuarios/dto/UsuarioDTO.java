package com.vitasync.backend.usuarios.dto;

import java.util.List;

public record UsuarioDTO(
        String id,
        String nombreCompleto,
        String username,
        List<String> grupos,
        boolean habilitado,
        boolean requiereCambioPassword,
        String fechaCreacion,
        String ultimoInicioSesion) {
}
