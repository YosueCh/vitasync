package com.vitasync.backend.chat;

import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.regex.Pattern;

/**
 * Chat entre el médico (Dispositivo A) y el paciente (Dispositivo B).
 *
 * Es el servidor intermediario de la Práctica 6: los dos teléfonos no se
 * hablan entre sí, ambos usan esta URL del backend. Hay una conversación por
 * paciente (se identifica con el id de su cuenta).
 *
 * Almacenamiento: los mensajes viven solo en memoria del servidor y se
 * conservan hasta que el paciente cierra el chat ({@link #cerrar}); en ese
 * momento se borran. Tampoco sobreviven a un reinicio del servidor.
 */
@Service
public class ChatService implements com.vitasync.backend.usuarios.service.LimpiezaDeCuenta {

    public static final int MAX_TEXTO = 200;
    public static final int MAX_MENSAJES = 500;

    private static final Pattern ID_VALIDO = Pattern.compile("^[A-Za-z0-9_-]{1,64}$");

    private static class Conversacion {
        final List<MensajeChatDTO> mensajes = new ArrayList<>();
        int siguienteId = 1;
        boolean cerrada;
    }

    // pacienteId -> conversación
    private final Map<String, Conversacion> conversaciones = new ConcurrentHashMap<>();

    /**
     * Guarda un mensaje nuevo.
     *
     * @throws IllegalArgumentException dato inválido (emisor, texto vacío o largo, id)
     * @throws IllegalStateException    el paciente cerró el chat o se llenó el historial
     */
    public MensajeChatDTO enviar(String pacienteId, String emisor, String texto) {
        validarId(pacienteId);
        String quien = emisor == null ? "" : emisor.trim().toUpperCase();
        if (!quien.equals("MEDICO") && !quien.equals("PACIENTE")) {
            throw new IllegalArgumentException("El emisor debe ser MEDICO o PACIENTE.");
        }
        String limpio = texto == null ? "" : texto.trim();
        if (limpio.isEmpty()) {
            throw new IllegalArgumentException("El mensaje no puede estar vacío.");
        }
        if (limpio.length() > MAX_TEXTO) {
            throw new IllegalArgumentException("El mensaje no puede pasar de " + MAX_TEXTO + " caracteres.");
        }

        Conversacion c = conversacion(pacienteId);
        synchronized (c) {
            if (c.cerrada) {
                throw new IllegalStateException("El paciente cerró el chat.");
            }
            if (c.mensajes.size() >= MAX_MENSAJES) {
                throw new IllegalStateException("El chat alcanzó el límite de mensajes.");
            }
            MensajeChatDTO m = new MensajeChatDTO(c.siguienteId++, quien, limpio, Instant.now().toString());
            c.mensajes.add(m);
            return m;
        }
    }

    /** Mensajes con id mayor a {@code desde} (0 = todos) y si el chat está cerrado. */
    public ConversacionDTO consultar(String pacienteId, int desde) {
        validarId(pacienteId);
        Conversacion c = conversacion(pacienteId);
        synchronized (c) {
            List<MensajeChatDTO> nuevos = c.mensajes.stream().filter(m -> m.id() > desde).toList();
            return new ConversacionDTO(c.cerrada, nuevos);
        }
    }

    /** Al eliminar la cuenta del paciente desaparece su conversación completa. */
    @Override
    public void borrarDatosDe(String pacienteId) {
        conversaciones.remove(pacienteId);
    }

    /** El paciente cierra el chat: se borra todo el historial. */
    public void cerrar(String pacienteId) {
        validarId(pacienteId);
        Conversacion c = conversacion(pacienteId);
        synchronized (c) {
            c.mensajes.clear();
            c.cerrada = true;
        }
    }

    /**
     * Abre un chat nuevo después de haberlo cerrado. Los ids siguen subiendo
     * (no se reinician) para que quien ya había leído mensajes no se pierda
     * los nuevos.
     */
    public void abrir(String pacienteId) {
        validarId(pacienteId);
        Conversacion c = conversacion(pacienteId);
        synchronized (c) {
            c.mensajes.clear();
            c.cerrada = false;
        }
    }

    private Conversacion conversacion(String pacienteId) {
        return conversaciones.computeIfAbsent(pacienteId, id -> new Conversacion());
    }

    private static void validarId(String pacienteId) {
        if (pacienteId == null || !ID_VALIDO.matcher(pacienteId).matches()) {
            throw new IllegalArgumentException("Identificador de paciente inválido.");
        }
    }
}
