package com.vitasync.backend.admin;

import com.vitasync.backend.seguridad.ControlDeAcceso;
import com.vitasync.backend.seguridad.Identidad;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

/**
 * Invitaciones de un solo uso con rol:
 * <pre>
 *   POST /api/admin/invitaciones     {"rol":"medico"}   el administrador genera un código
 *   GET  /api/admin/invitaciones                         el administrador ve las que hay y si se usaron
 *   POST /api/invitaciones/canjear   {"codigo":"AB12CD34"}   cualquier persona con sesión recibe ese rol
 * </pre>
 */
@RestController
public class InvitacionesController {

    private final InvitacionesService service;

    public InvitacionesController(InvitacionesService service) {
        this.service = service;
    }

    public record CrearDTO(String rol) {
    }

    public record CanjearDTO(String codigo) {
    }

    @PostMapping("/api/admin/invitaciones")
    public ResponseEntity<?> crear(@RequestBody CrearDTO cuerpo) {
        return respuesta(() -> service.crear(cuerpo == null ? null : cuerpo.rol()));
    }

    @GetMapping("/api/admin/invitaciones")
    public ResponseEntity<?> listar() {
        return respuesta(service::listar);
    }

    @PostMapping("/api/invitaciones/canjear")
    public ResponseEntity<?> canjear(@RequestBody CanjearDTO cuerpo, HttpServletRequest peticion) {
        Identidad quien = (Identidad) peticion.getAttribute(ControlDeAcceso.ATRIBUTO);
        if (quien == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(Map.of("error", "Inicia sesión para continuar."));
        }
        return respuesta(() -> Map.of("rol", service.canjear(quien.uid(), cuerpo == null ? null : cuerpo.codigo())));
    }

    private ResponseEntity<?> respuesta(java.util.function.Supplier<?> accion) {
        if (!service.isDisponible()) {
            return error(HttpStatus.SERVICE_UNAVAILABLE, "Las invitaciones necesitan Firebase y la seguridad activa.");
        }
        try {
            return ResponseEntity.ok(accion.get());
        } catch (RolesService.DatoInvalidoException e) {
            return error(HttpStatus.BAD_REQUEST, e.getMessage());
        } catch (InvitacionRepository.InvitacionInvalidaException e) {
            return error(HttpStatus.CONFLICT, e.getMessage());
        } catch (InvitacionesService.DemasiadosIntentosException e) {
            return error(HttpStatus.TOO_MANY_REQUESTS, e.getMessage());
        }
    }

    private static ResponseEntity<Map<String, String>> error(HttpStatus estado, String mensaje) {
        return ResponseEntity.status(estado).body(Map.of("error", mensaje));
    }
}
