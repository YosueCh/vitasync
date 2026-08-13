package com.vitasync.backend.cast.controller;

import com.vitasync.backend.cast.service.CastService;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.function.Supplier;

/**
 * Enlace con Smart TV (Práctica 9-10). Ver CastService para el detalle
 * del flujo de emparejamiento por código.
 */
@RestController
@RequestMapping("/api/cast")
@CrossOrigin(origins = "http://localhost:4200")
public class CastController {

    private final CastService service;

    public CastController(CastService service) {
        this.service = service;
    }

    @PostMapping("/generar")
    public ResponseEntity<?> generar() {
        return conFirebase(service::generar);
    }

    @PostMapping("/emparejar/{codigo}")
    public ResponseEntity<?> emparejar(@PathVariable String codigo) {
        return conFirebase(() -> service.emparejar(codigo));
    }

    @GetMapping("/estado/{codigo}")
    public ResponseEntity<?> estado(@PathVariable String codigo) {
        return conFirebase(() -> service.estado(codigo));
    }

    private ResponseEntity<?> conFirebase(Supplier<?> accion) {
        if (!service.isDisponible()) {
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                    .body(new ErrorDTO("Firebase no está configurado. Agrega serviceAccountKey.json en "
                            + "src/main/resources/ (ver README del backend)."));
        }
        try {
            return ResponseEntity.ok(accion.get());
        } catch (CastService.CodigoInvalidoException e) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND).body(new ErrorDTO(e.getMessage()));
        } catch (CastService.CodigoExpiradoException e) {
            return ResponseEntity.status(HttpStatus.GONE).body(new ErrorDTO(e.getMessage()));
        }
    }

    private record ErrorDTO(String error) {
    }
}
