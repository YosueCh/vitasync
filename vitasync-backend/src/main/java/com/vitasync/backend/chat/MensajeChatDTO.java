package com.vitasync.backend.chat;

/**
 * Un mensaje de la conversación médico-paciente.
 *
 * @param id     número consecutivo dentro de la conversación (nunca se repite,
 *               aunque el chat se cierre y se vuelva a abrir)
 * @param emisor "MEDICO" (Dispositivo A) o "PACIENTE" (Dispositivo B)
 * @param texto  contenido ya validado
 * @param hora   instante de envío en ISO-8601 (UTC), lo pone el servidor
 * @param archivo datos del archivo adjunto (Práctica 7), o null si es un mensaje de texto; el contenido se descarga
 *                aparte con GET /api/chat/{pacienteId}/archivos/{id}
 */
public record MensajeChatDTO(int id, String emisor, String texto, String hora, ArchivoDTO archivo) {

    /** Mensaje de texto, sin archivo. */
    public MensajeChatDTO(int id, String emisor, String texto, String hora) {
        this(id, emisor, texto, hora, null);
    }

    /** Lo que se muestra de un archivo adjunto (el contenido no viaja en la lista de mensajes). */
    public record ArchivoDTO(String nombre, String tipo, int tamano) {
    }
}
