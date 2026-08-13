package com.vitasync.backend.cast.dto;

public record CastSessionDTO(
        String codigo,
        String estado,
        String creadoEn,
        String expiraEn,
        String emparejadoEn) {
}
