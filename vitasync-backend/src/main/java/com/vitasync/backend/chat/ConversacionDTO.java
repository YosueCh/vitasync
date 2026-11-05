package com.vitasync.backend.chat;

import java.util.List;

/**
 * Respuesta de la consulta de una conversación.
 *
 * @param cerrado  true si el paciente cerró el chat (el historial ya se borró)
 * @param mensajes mensajes con id mayor al pedido, en orden de envío
 */
public record ConversacionDTO(boolean cerrado, List<MensajeChatDTO> mensajes) {
}
