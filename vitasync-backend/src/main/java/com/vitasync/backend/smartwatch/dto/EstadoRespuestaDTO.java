package com.vitasync.backend.smartwatch.dto;

import com.fasterxml.jackson.annotation.JsonInclude;

/**
 * Respuesta de estado para el indicador de Angular y la app móvil.
 *
 * {@code claveDispositivo} solo viene al CONECTAR el reloj (Práctica 10): es la clave que el firmware debe
 * mandar en la cabecera X-Clave-Dispositivo. No se guarda en claro ni se vuelve a mostrar.
 */
public record EstadoRespuestaDTO(
        String estado,            // DESCONECTADO | CONECTANDO | CONECTADO | SINCRONIZANDO | ERROR
        DispositivoDTO dispositivo,
        String mensaje,
        @JsonInclude(JsonInclude.Include.NON_NULL) String claveDispositivo) {

    public EstadoRespuestaDTO(String estado, DispositivoDTO dispositivo, String mensaje) {
        this(estado, dispositivo, mensaje, null);
    }
}
