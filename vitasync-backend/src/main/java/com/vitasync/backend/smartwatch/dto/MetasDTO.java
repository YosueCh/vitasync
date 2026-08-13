package com.vitasync.backend.smartwatch.dto;

import java.util.List;

/** Datos que el sistema devuelve al smartwatch (sistema -> reloj). */
public record MetasDTO(
        int metaPasos,
        int metaCalorias,
        double metaSueñoHoras,
        List<String> notificaciones,
        List<String> recordatorios) {
}
