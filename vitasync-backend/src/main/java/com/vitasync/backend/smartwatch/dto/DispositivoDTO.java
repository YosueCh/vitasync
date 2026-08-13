package com.vitasync.backend.smartwatch.dto;

import java.time.Instant;

/** Información del dispositivo expuesta a la web. */
public record DispositivoDTO(
        String id,
        String nombre,
        String modelo,
        int bateria,
        String firmware,
        Instant ultimaSync) {
}
