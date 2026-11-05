package com.vitasync.backend.chat;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

/**
 * Chat médico-paciente (Práctica 6). Es la "URL asignada" a la que se conectan
 * los dos teléfonos:
 *
 * <pre>
 *   POST /api/chat/{pacienteId}/mensajes   {emisor, texto}  envía un mensaje
 *   GET  /api/chat/{pacienteId}/mensajes?desde=N            mensajes con id &gt; N
 *   POST /api/chat/{pacienteId}/cerrar                      el paciente cierra: se borra todo
 *   POST /api/chat/{pacienteId}/abrir                       abre un chat nuevo
 * </pre>
 *
 * Los errores devuelven {@code {"error": "..."}} (400 dato inválido, 409 chat
 * cerrado), el formato que la app móvil ya sabe mostrar.
 */
@RestController
@RequestMapping("/api/chat/{pacienteId}")
public class ChatController {

    private final ChatService service;

    public ChatController(ChatService service) {
        this.service = service;
    }

    /** Cuerpo de POST /mensajes. */
    public record EnviarMensajeDTO(String emisor, String texto) {
    }

    @PostMapping("/mensajes")
    public MensajeChatDTO enviar(@PathVariable String pacienteId, @RequestBody EnviarMensajeDTO cuerpo) {
        return service.enviar(pacienteId, cuerpo.emisor(), cuerpo.texto());
    }

    @GetMapping("/mensajes")
    public ConversacionDTO consultar(@PathVariable String pacienteId,
                                     @RequestParam(defaultValue = "0") int desde) {
        return service.consultar(pacienteId, desde);
    }

    @PostMapping("/cerrar")
    public Map<String, Object> cerrar(@PathVariable String pacienteId) {
        service.cerrar(pacienteId);
        return Map.of("cerrado", true);
    }

    @PostMapping("/abrir")
    public Map<String, Object> abrir(@PathVariable String pacienteId) {
        service.abrir(pacienteId);
        return Map.of("cerrado", false);
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<Map<String, String>> datoInvalido(IllegalArgumentException e) {
        return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(Map.of("error", e.getMessage()));
    }

    @ExceptionHandler(IllegalStateException.class)
    public ResponseEntity<Map<String, String>> conflicto(IllegalStateException e) {
        return ResponseEntity.status(HttpStatus.CONFLICT).body(Map.of("error", e.getMessage()));
    }
}
