package com.vitasync.backend.firmware;

/** Versión de firmware publicada y sus notas de cambios. */
public record FirmwareDTO(String version, String notas) {
}
