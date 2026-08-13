package com.vitasync.backend.smartwatch.dto;

import java.time.Instant;

/** Datos que el smartwatch envía al sistema. */
public record MetricasDTO(
        int pasos,
        int calorias,
        double sueñoHoras,
        int frecuenciaCardiaca,
        int bateria,
        Instant timestamp) {
}
