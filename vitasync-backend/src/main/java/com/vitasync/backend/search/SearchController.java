package com.vitasync.backend.search;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;
import java.util.Optional;

@RestController
@RequestMapping("/api/search")
@CrossOrigin(origins = "http://localhost:4200")
public class SearchController {

    private final Optional<SearchService> service;

    /** El servicio solo existe con Elasticsearch activado (ver application.yml); sin él, /api/search responde 503. */
    public SearchController(Optional<SearchService> service) {
        this.service = service;
    }

    /** GET /api/search?q=sueño */
    @GetMapping
    public ResponseEntity<?> buscar(@RequestParam("q") String q) {
        try {
            if (service.isEmpty()) throw new IllegalStateException("buscador apagado");
            return ResponseEntity.ok(service.get().buscar(q));
        } catch (RuntimeException e) {
            // Sin Elasticsearch el buscador del servidor no puede responder; el resto del backend sigue.
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                    .body(Map.of("error", "El buscador del servidor no está disponible (Elasticsearch apagado o sin activar)."));
        }
    }
}
