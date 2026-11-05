package com.vitasync.backend.firmware;

/**
 * Estado del firmware de un dispositivo.
 *
 * @param versionActual    versión que reporta el dispositivo (null si nunca se conectó)
 * @param ultima           versión más reciente publicada
 * @param hayActualizacion true si la versión actual es distinta a la última
 * @param ordenPendiente   true si el usuario ya pidió actualizar y el dispositivo aún no la aplica
 */
public record EstadoFirmwareDTO(
        String versionActual,
        FirmwareDTO ultima,
        boolean hayActualizacion,
        boolean ordenPendiente) {
}
