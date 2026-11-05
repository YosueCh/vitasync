package com.vitasync.backend.chat;

/**
 * Un mensaje de la conversación médico-paciente.
 *
 * @param id     número consecutivo dentro de la conversación (nunca se repite,
 *               aunque el chat se cierre y se vuelva a abrir)
 * @param emisor "MEDICO" (Dispositivo A) o "PACIENTE" (Dispositivo B)
 * @param texto  contenido ya validado
 * @param hora   instante de envío en ISO-8601 (UTC), lo pone el servidor
 */
public record MensajeChatDTO(int id, String emisor, String texto, String hora) {
}
