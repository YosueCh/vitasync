package com.vitasync.backend.smartwatch.dto;

/** Respuesta de estado para el indicador de Angular. */
public record EstadoRespuestaDTO(
        String estado,            // DESCONECTADO | CONECTANDO | CONECTADO | SINCRONIZANDO | ERROR
        DispositivoDTO dispositivo,
        String mensaje) {
}
