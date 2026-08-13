package com.vitasync.backend.smartwatch.controller;

import com.vitasync.backend.smartwatch.dto.EstadoRespuestaDTO;
import com.vitasync.backend.smartwatch.dto.MetasDTO;
import com.vitasync.backend.smartwatch.dto.MetricasDTO;
import com.vitasync.backend.smartwatch.service.SmartwatchService;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/smartwatch")
@CrossOrigin(origins = "http://localhost:4200")
public class SmartwatchController {

    private final SmartwatchService service;

    public SmartwatchController(SmartwatchService service) {
        this.service = service;
    }

    /** GET /api/smartwatch/status?usuarioId=... */
    @GetMapping("/status")
    public ResponseEntity<?> status(@RequestParam String usuarioId) {
        return conFirebase(() -> service.estado(usuarioId));
    }

    /** POST /api/smartwatch/connect?usuarioId=... */
    @PostMapping("/connect")
    public ResponseEntity<?> connect(@RequestParam String usuarioId) {
        return conFirebase(() -> service.conectar(usuarioId));
    }

    /** POST /api/smartwatch/sync?usuarioId=...  (smartwatch -> sistema -> metas) */
    @PostMapping("/sync")
    public ResponseEntity<?> sync(@RequestParam String usuarioId, @RequestBody(required = false) MetricasDTO metricas) {
        return conFirebase(() -> service.sincronizar(usuarioId, metricas));
    }

    /** GET /api/smartwatch/metrics?usuarioId=... */
    @GetMapping("/metrics")
    public ResponseEntity<?> metrics(@RequestParam String usuarioId) {
        return conFirebase(() -> service.metricas(usuarioId));
    }

    private ResponseEntity<?> conFirebase(java.util.function.Supplier<?> accion) {
        if (!service.isDisponible()) {
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                    .body(new ErrorDTO("Firebase no está configurado. Agrega serviceAccountKey.json en "
                            + "src/main/resources/ (ver docs-elasticsearch/GUIA_ELASTICSEARCH.md y el README)."));
        }
        return ResponseEntity.ok(accion.get());
    }

    private record ErrorDTO(String error) {
    }
}
