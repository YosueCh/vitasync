package com.vitasync.backend.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.context.request.WebRequest;
import org.springframework.web.servlet.mvc.method.annotation.ResponseEntityExceptionHandler;

import java.util.Map;

/**
 * Forma ÚNICA de las respuestas de error: siempre {@code {"error": "mensaje"}}, sin clases ni rutas internas
 * (WB-HALLAZGO-5 y WB-HALLAZGO-6 de la Práctica 11).
 *
 * Antes, lo que Spring contestaba por su cuenta (JSON mal formado, falta un parámetro, método no permitido…) traía
 * {@code timestamp, status, error, trace, path}: el campo «trace» exponía la pila de Java completa, y la estructura
 * era distinta a la de los errores de la propia aplicación. Aquí se traducen los errores estándar de MVC y cualquier
 * excepción no prevista; esta última se registra en el log del servidor y se contesta 500 con un mensaje genérico.
 */
@RestControllerAdvice
public class ManejadorDeErrores extends ResponseEntityExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(ManejadorDeErrores.class);

    @Override
    protected ResponseEntity<Object> handleExceptionInternal(Exception ex, Object body, HttpHeaders headers,
                                                             HttpStatusCode status, WebRequest request) {
        return ResponseEntity.status(status).headers(headers).body(Map.of("error", mensaje(status.value())));
    }

    /** Un argumento que el servicio rechazó (p. ej. un id que Firestore no acepta): 400, sin repetir el detalle interno. */
    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<Map<String, String>> argumentoInvalido(IllegalArgumentException e) {
        log.warn("Argumento inválido: {}", e.getMessage());
        return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(Map.of("error", mensaje(400)));
    }

    /** Cualquier otra excepción no prevista: se registra aquí y la persona recibe un 500 genérico. */
    @ExceptionHandler(Exception.class)
    public ResponseEntity<Map<String, String>> inesperada(Exception e) {
        log.error("Error no controlado", e);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(Map.of("error", mensaje(500)));
    }

    static String mensaje(int estado) {
        return switch (estado) {
            case 400 -> "La petición no es válida.";
            case 404 -> "No existe ese recurso.";
            case 405 -> "Ese método no está permitido en esta ruta.";
            case 406 -> "No se puede responder en el formato pedido.";
            case 415 -> "El tipo de contenido no es compatible.";
            case 500 -> "Ocurrió un error en el servidor. Inténtalo de nuevo más tarde.";
            case 503 -> "El servicio no está disponible por ahora.";
            default -> "No se pudo completar la petición.";
        };
    }
}
