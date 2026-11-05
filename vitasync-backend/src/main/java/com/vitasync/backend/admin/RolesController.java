package com.vitasync.backend.admin;

import com.vitasync.backend.seguridad.ControlDeAcceso;
import com.vitasync.backend.seguridad.Identidad;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

/**
 * Roles de las personas, solo para el administrador (el filtro de seguridad rechaza a los demás con 403):
 * <pre>
 *   GET /api/admin/personas   quién existe y qué rol tiene
 *   PUT /api/admin/roles      {"cambios":[{"uid":"..","rol":"medico"}, ...]}  asigna varios roles de un solo envío
 * </pre>
 */
@RestController
@RequestMapping("/api/admin")
public class RolesController {

    private final RolesService service;

    public RolesController(RolesService service) {
        this.service = service;
    }

    public record LoteDTO(List<RolesService.Cambio> cambios) {
    }

    @GetMapping("/personas")
    public ResponseEntity<?> personas() {
        if (!service.isDisponible()) return noDisponible();
        return ResponseEntity.ok(service.personas());
    }

    @PutMapping("/roles")
    public ResponseEntity<?> asignar(@RequestBody LoteDTO lote, HttpServletRequest peticion) {
        if (!service.isDisponible()) return noDisponible();
        Identidad quien = (Identidad) peticion.getAttribute(ControlDeAcceso.ATRIBUTO);
        try {
            return ResponseEntity.ok(service.asignar(quien == null ? null : quien.uid(), lote == null ? null : lote.cambios()));
        } catch (RolesService.DatoInvalidoException e) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(Map.of("error", e.getMessage()));
        }
    }

    private static ResponseEntity<Map<String, String>> noDisponible() {
        return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                .body(Map.of("error", "La gestión de roles necesita la seguridad activa (vitasync.seguridad.activa=true)."));
    }
}
