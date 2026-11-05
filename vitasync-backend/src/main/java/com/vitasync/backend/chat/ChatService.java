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

    /** Archivos (Práctica 7): tamaño máximo de cada uno, de todos juntos en una conversación y cuántos. */
    public static final int MAX_ARCHIVO_BYTES = 300 * 1024;
    public static final int MAX_ARCHIVOS_BYTES = 2 * 1024 * 1024;
    public static final int MAX_ARCHIVOS = 20;

    /** Solo estos tipos; además se comprueba que los primeros bytes correspondan de verdad al tipo declarado. */
    private static final java.util.Set<String> TIPOS = java.util.Set.of(
            "image/png", "image/jpeg", "application/pdf", "text/plain");

    private static class Conversacion {
        final List<MensajeChatDTO> mensajes = new ArrayList<>();
        final Map<Integer, byte[]> archivos = new java.util.HashMap<>();
        int bytesArchivos;
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

    /**
     * Guarda un archivo adjunto como un mensaje más. Se valida en el servidor: tipo permitido, que el contenido
     * sea de ese tipo (no se confía en lo que diga el nombre), tamaño y cupo de la conversación.
     *
     * @throws IllegalArgumentException archivo inválido (tipo, contenido, tamaño o nombre)
     * @throws IllegalStateException    chat cerrado o sin cupo
     */
    public MensajeChatDTO enviarArchivo(String pacienteId, String emisor, String nombre, String tipo, byte[] contenido) {
        validarId(pacienteId);
        String quien = emisor == null ? "" : emisor.trim().toUpperCase();
        if (!quien.equals("MEDICO") && !quien.equals("PACIENTE")) {
            throw new IllegalArgumentException("El emisor debe ser MEDICO o PACIENTE.");
        }
        String mime = tipo == null ? "" : tipo.trim().toLowerCase();
        if (!TIPOS.contains(mime)) {
            throw new IllegalArgumentException("Tipo de archivo no permitido. Solo PNG, JPG, PDF o texto.");
        }
        if (contenido == null || contenido.length == 0) throw new IllegalArgumentException("El archivo está vacío.");
        if (contenido.length > MAX_ARCHIVO_BYTES) {
            throw new IllegalArgumentException("El archivo no puede pasar de " + MAX_ARCHIVO_BYTES / 1024 + " KB.");
        }
        if (!coincideConElTipo(mime, contenido)) {
            throw new IllegalArgumentException("El contenido del archivo no corresponde a su tipo.");
        }
        String limpio = nombreSeguro(nombre);

        Conversacion c = conversacion(pacienteId);
        synchronized (c) {
            if (c.cerrada) throw new IllegalStateException("El paciente cerró el chat.");
            if (c.mensajes.size() >= MAX_MENSAJES) throw new IllegalStateException("El chat alcanzó el límite de mensajes.");
            if (c.archivos.size() >= MAX_ARCHIVOS || c.bytesArchivos + contenido.length > MAX_ARCHIVOS_BYTES) {
                throw new IllegalStateException("La conversación alcanzó el límite de archivos.");
            }
            int id = c.siguienteId++;
            MensajeChatDTO m = new MensajeChatDTO(id, quien, "Archivo: " + limpio, Instant.now().toString(),
                    new MensajeChatDTO.ArchivoDTO(limpio, mime, contenido.length));
            c.mensajes.add(m);
            c.archivos.put(id, contenido.clone());
            c.bytesArchivos += contenido.length;
            return m;
        }
    }

    /** El contenido de un archivo adjunto, o vacío si no existe (o el chat se cerró y se borró). */
    public java.util.Optional<byte[]> contenidoDe(String pacienteId, int mensajeId) {
        validarId(pacienteId);
        Conversacion c = conversacion(pacienteId);
        synchronized (c) {
            return java.util.Optional.ofNullable(c.archivos.get(mensajeId));
        }
    }

    /** Tipo y nombre del archivo del mensaje, o vacío si ese mensaje no tiene archivo. */
    public java.util.Optional<MensajeChatDTO.ArchivoDTO> archivoDe(String pacienteId, int mensajeId) {
        validarId(pacienteId);
        Conversacion c = conversacion(pacienteId);
        synchronized (c) {
            return c.mensajes.stream().filter(m -> m.id() == mensajeId && m.archivo() != null)
                    .map(MensajeChatDTO::archivo).findFirst();
        }
    }

    private static boolean coincideConElTipo(String mime, byte[] b) {
        switch (mime) {
            case "image/png":
                return b.length > 8 && (b[0] & 0xFF) == 0x89 && b[1] == 'P' && b[2] == 'N' && b[3] == 'G';
            case "image/jpeg":
                return b.length > 3 && (b[0] & 0xFF) == 0xFF && (b[1] & 0xFF) == 0xD8 && (b[2] & 0xFF) == 0xFF;
            case "application/pdf":
                return b.length > 5 && b[0] == '%' && b[1] == 'P' && b[2] == 'D' && b[3] == 'F' && b[4] == '-';
            default: // text/plain: UTF-8 válido y sin bytes nulos
                for (byte x : b) if (x == 0) return false;
                try {
                    java.nio.charset.StandardCharsets.UTF_8.newDecoder()
                            .onMalformedInput(java.nio.charset.CodingErrorAction.REPORT)
                            .decode(java.nio.ByteBuffer.wrap(b));
                    return true;
                } catch (java.nio.charset.CharacterCodingException e) {
                    return false;
                }
        }
    }

    /** Solo el nombre del archivo (sin carpetas), sin caracteres de control ni símbolos peligrosos, de hasta 80. */
    static String nombreSeguro(String nombre) {
        String n = nombre == null ? "" : nombre.trim();
        n = n.substring(Math.max(n.lastIndexOf('/'), n.lastIndexOf('\\')) + 1);
        n = n.replaceAll("[\\p{Cntrl}<>:\"|?*]", "_").trim();
        if (n.isEmpty() || n.equals(".") || n.equals("..")) throw new IllegalArgumentException("El archivo necesita un nombre.");
        return n.length() > 80 ? n.substring(0, 80) : n;
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
            c.archivos.clear();
            c.bytesArchivos = 0;
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
            c.archivos.clear();
            c.bytesArchivos = 0;
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
