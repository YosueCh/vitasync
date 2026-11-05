package com.vitasync.backend.firmware;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;
import java.util.function.Supplier;

@RestController
@RequestMapping("/api/firmware")
public class FirmwareController {

    private final FirmwareService service;

    public FirmwareController(FirmwareService service) {
        this.service = service;
    }

    /** GET /api/firmware/ultima: versión publicada y sus notas. */
    @GetMapping("/ultima")
    public FirmwareDTO ultima() {
        return service.ultima();
    }

    /** GET /api/firmware/estado?usuarioId=: versión del dispositivo vs. la última. */
    @GetMapping("/estado")
    public ResponseEntity<?> estado(@RequestParam String usuarioId) {
        return conFirebase(() -> service.estado(usuarioId));
    }

    /** POST /api/firmware/solicitar?usuarioId=: el usuario pide actualizar. */
    @PostMapping("/solicitar")
    public ResponseEntity<?> solicitar(@RequestParam String usuarioId) {
        return conFirebase(() -> service.solicitar(usuarioId));
    }

    /** GET /api/firmware/orden?usuarioId=: lo consulta el firmware del dispositivo. */
    @GetMapping("/orden")
    public ResponseEntity<?> orden(@RequestParam String usuarioId) {
        return ResponseEntity.ok(service.ordenPendiente(usuarioId)
                .map(v -> Map.<String, Object>of("pendiente", true, "version", v))
                .orElse(Map.<String, Object>of("pendiente", false)));
    }

    /** POST /api/firmware/aplicar?usuarioId=&version=: el firmware reporta la versión instalada. */
    @PostMapping("/aplicar")
    public ResponseEntity<?> aplicar(@RequestParam String usuarioId, @RequestParam String version) {
        return conFirebase(() -> service.aplicar(usuarioId, version));
    }

    private ResponseEntity<?> conFirebase(Supplier<?> accion) {
        if (!service.isDisponible()) {
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                    .body(Map.of("error", "Firebase no está configurado."));
        }
        return ResponseEntity.ok(accion.get());
    }
}
