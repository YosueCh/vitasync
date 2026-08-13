package com.vitasync.backend.usuarios.controller;

import com.vitasync.backend.usuarios.dto.CrearUsuarioDTO;
import com.vitasync.backend.usuarios.service.UsuarioService;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.function.Supplier;

/**
 * Administración de cuentas de usuario de VitaSync (Práctica 13).
 * Distingue explícitamente deshabilitar (reversible, conserva datos) de
 * eliminar (permanente) — ver UsuarioService para el detalle.
 */
@RestController
@RequestMapping("/api/usuarios")
@CrossOrigin(origins = "http://localhost:4200")
public class UsuarioController {

    private final UsuarioService service;

    public UsuarioController(UsuarioService service) {
        this.service = service;
    }

    @GetMapping
    public ResponseEntity<?> listar() {
        return conFirebase(service::listar);
    }

    @PostMapping
    public ResponseEntity<?> crear(@RequestBody CrearUsuarioDTO datos) {
        return conFirebase(() -> service.crear(datos));
    }

    @GetMapping("/{id}")
    public ResponseEntity<?> obtener(@PathVariable String id) {
        return conFirebase(() -> service.obtener(id));
    }

    @PatchMapping("/{id}/habilitar")
    public ResponseEntity<?> habilitar(@PathVariable String id) {
        return conFirebase(() -> service.habilitar(id));
    }

    @PatchMapping("/{id}/deshabilitar")
    public ResponseEntity<?> deshabilitar(@PathVariable String id) {
        return conFirebase(() -> service.deshabilitar(id));
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<?> eliminar(@PathVariable String id) {
        return conFirebase(() -> {
            service.eliminar(id);
            return new MensajeDTO("Usuario eliminado permanentemente.");
        });
    }

    @PostMapping("/{id}/login")
    public ResponseEntity<?> simularLogin(@PathVariable String id) {
        return conFirebase(() -> service.simularLogin(id));
    }

    private ResponseEntity<?> conFirebase(Supplier<?> accion) {
        if (!service.isDisponible()) {
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                    .body(new ErrorDTO("Firebase no está configurado. Agrega serviceAccountKey.json en "
                            + "src/main/resources/ (ver README del backend)."));
        }
        try {
            return ResponseEntity.ok(accion.get());
        } catch (UsuarioService.UsuarioNoEncontradoException e) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND).body(new ErrorDTO(e.getMessage()));
        }
    }

    private record ErrorDTO(String error) {
    }

    private record MensajeDTO(String mensaje) {
    }
}
