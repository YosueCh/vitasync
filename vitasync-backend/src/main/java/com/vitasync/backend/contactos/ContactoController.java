package com.vitasync.backend.contactos;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

/**
 * Contactos de emergencia de una cuenta (Actividad 1):
 * <pre>
 *   GET    /api/contactos?usuarioId=         lista los de la cuenta
 *   POST   /api/contactos?usuarioId=         {nombre, telefono, relacion}  crea uno
 *   DELETE /api/contactos/{id}?usuarioId=    elimina uno
 * </pre>
 * Con la seguridad activa, ControlDeAcceso exige token y que usuarioId sea una cuenta de quien pide.
 */
@RestController
@RequestMapping("/api/contactos")
public class ContactoController {

    private final ContactoService service;

    public ContactoController(ContactoService service) {
        this.service = service;
    }

    @GetMapping
    public ResponseEntity<?> listar(@RequestParam String usuarioId) {
        return conFirebase(() -> service.listar(usuarioId));
    }

    @PostMapping
    public ResponseEntity<?> crear(@RequestParam String usuarioId, @RequestBody CrearContactoDTO cuerpo) {
        return conFirebase(() -> service.crear(usuarioId, cuerpo));
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<?> eliminar(@PathVariable String id, @RequestParam String usuarioId) {
        return conFirebase(() -> {
            service.eliminar(usuarioId, id);
            return Map.of("mensaje", "Contacto eliminado.");
        });
    }

    private ResponseEntity<?> conFirebase(java.util.function.Supplier<?> accion) {
        if (!service.isDisponible()) {
            return error(HttpStatus.SERVICE_UNAVAILABLE, "Firebase no está configurado.");
        }
        try {
            return ResponseEntity.ok(accion.get());
        } catch (ContactoService.DatoInvalidoException e) {
            return error(HttpStatus.BAD_REQUEST, e.getMessage());
        } catch (ContactoService.ConflictoException e) {
            return error(HttpStatus.CONFLICT, e.getMessage());
        } catch (ContactoService.ContactoNoEncontradoException e) {
            return error(HttpStatus.NOT_FOUND, e.getMessage());
        }
    }

    private static ResponseEntity<Map<String, String>> error(HttpStatus estado, String mensaje) {
        return ResponseEntity.status(estado).body(Map.of("error", mensaje));
    }
}
