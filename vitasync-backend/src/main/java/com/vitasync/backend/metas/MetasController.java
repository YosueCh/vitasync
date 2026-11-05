package com.vitasync.backend.metas;

import com.vitasync.backend.seguridad.ControlDeAcceso;
import com.vitasync.backend.seguridad.Identidad;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.function.Supplier;

/**
 * Metas de salud de una cuenta, compartidas entre la paciente y su médico:
 * <pre>
 *   GET /api/metas?usuarioId=     las metas y su versión
 *   PUT /api/metas?usuarioId=     cambia metas (con «version»: control de versión → 409 si otro se adelantó;
 *                                 sin «version»: fusión por campos)
 * </pre>
 * Con la seguridad activa pueden usarlo la dueña de la cuenta y cualquier médico (ver ControlDeAcceso).
 * Quién hizo el cambio se anota según el rol del token, no según lo que diga la app.
 */
@RestController
@RequestMapping("/api/metas")
public class MetasController {

    private final MetasService service;

    public MetasController(MetasService service) {
        this.service = service;
    }

    @GetMapping
    public ResponseEntity<?> obtener(@RequestParam String usuarioId) {
        return conFirebase(() -> service.obtener(usuarioId));
    }

    @PutMapping
    public ResponseEntity<?> actualizar(@RequestParam String usuarioId, @RequestBody ActualizarMetasDTO cuerpo,
                                        HttpServletRequest peticion) {
        Identidad quien = (Identidad) peticion.getAttribute(ControlDeAcceso.ATRIBUTO);
        String actor = quien == null ? null : quien.esMedico() ? "Médico" : quien.esAdmin() ? "Administrador" : "Paciente";
        return conFirebase(() -> service.actualizar(usuarioId, cuerpo, actor));
    }

    private ResponseEntity<?> conFirebase(Supplier<?> accion) {
        if (!service.isDisponible()) {
            return error(HttpStatus.SERVICE_UNAVAILABLE, "Firebase no está configurado.");
        }
        try {
            return ResponseEntity.ok(accion.get());
        } catch (MetasService.DatoInvalidoException e) {
            return error(HttpStatus.BAD_REQUEST, e.getMessage());
        } catch (ConflictoDeVersionException e) {
            Map<String, Object> cuerpo = new LinkedHashMap<>();
            cuerpo.put("error", e.getMessage());
            cuerpo.put("codigo", "CONFLICTO_DE_VERSION");
            cuerpo.put("actual", e.getActual());
            return ResponseEntity.status(HttpStatus.CONFLICT).body(cuerpo);
        }
    }

    private static ResponseEntity<Map<String, String>> error(HttpStatus estado, String mensaje) {
        return ResponseEntity.status(estado).body(Map.of("error", mensaje));
    }
}
