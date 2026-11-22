package com.vitasync.backend.usuarios.controller;

import com.vitasync.backend.seguridad.ControlDeAcceso;
import com.vitasync.backend.seguridad.Identidad;
import com.vitasync.backend.usuarios.dto.CrearUsuarioDTO;
import com.vitasync.backend.usuarios.dto.PinDTO;
import com.vitasync.backend.usuarios.service.PinService;
import com.vitasync.backend.usuarios.service.UsuarioService;
import jakarta.servlet.http.HttpServletRequest;
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
    private final PinService pinService;

    public UsuarioController(UsuarioService service, PinService pinService) {
        this.service = service;
        this.pinService = pinService;
    }

    /** Con la seguridad activa, cada persona ve solo SUS cuentas (el administrador ve todas). */
    @GetMapping
    public ResponseEntity<?> listar(HttpServletRequest peticion) {
        Identidad quien = (Identidad) peticion.getAttribute(ControlDeAcceso.ATRIBUTO);
        if (quien == null || quien.esAdmin()) return conFirebase(service::listar);
        return conFirebase(() -> service.listarDe(quien.uid()));
    }

    /** El dueño de la cuenta nueva es quien la crea (UID del token), nunca un valor del cuerpo. */
    @PostMapping
    public ResponseEntity<?> crear(@RequestBody CrearUsuarioDTO datos, HttpServletRequest peticion) {
        Identidad quien = (Identidad) peticion.getAttribute(ControlDeAcceso.ATRIBUTO);
        return conFirebase(HttpStatus.CREATED, () -> service.crear(datos, quien == null ? null : quien.uid()));
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
        return conFirebase(HttpStatus.NO_CONTENT, () -> {
            service.eliminar(id);
            return null;
        });
    }

    @PostMapping("/{id}/login")
    public ResponseEntity<?> simularLogin(@PathVariable String id) {
        return conFirebase(() -> service.simularLogin(id));
    }

    /** POST /api/usuarios/{id}/pin: registra el PIN. Solo si la cuenta aún no tiene uno. */
    @PostMapping("/{id}/pin")
    public ResponseEntity<?> registrarPin(@PathVariable String id, @RequestBody PinDTO cuerpo) {
        return conFirebase(() -> pinService.registrar(id, cuerpo.pin()));
    }

    /** POST /api/usuarios/{id}/pin/verificar: 200 con exito true/false; 429 si la cuenta está bloqueada. */
    @PostMapping("/{id}/pin/verificar")
    public ResponseEntity<?> verificarPin(@PathVariable String id, @RequestBody PinDTO cuerpo) {
        return conFirebase(() -> pinService.verificar(id, cuerpo.pin()));
    }

    private ResponseEntity<?> conFirebase(Supplier<?> accion) {
        return conFirebase(HttpStatus.OK, accion);
    }

    /** {@code exito}: 200 para consultas y cambios, 201 al crear, 204 al eliminar (sin cuerpo). */
    private ResponseEntity<?> conFirebase(HttpStatus exito, Supplier<?> accion) {
        if (!service.isDisponible()) {
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                    .body(new ErrorDTO("Firebase no está configurado. Agrega serviceAccountKey.json en "
                            + "src/main/resources/ (ver README del backend)."));
        }
        try {
            Object cuerpo = accion.get();
            return exito == HttpStatus.NO_CONTENT ? ResponseEntity.noContent().build() : ResponseEntity.status(exito).body(cuerpo);
        } catch (UsuarioService.UsuarioNoEncontradoException e) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND).body(new ErrorDTO(e.getMessage()));
        } catch (UsuarioService.DatoInvalidoException e) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(new ErrorDTO(e.getMessage()));
        } catch (UsuarioService.UsernameDuplicadoException e) {
            return ResponseEntity.status(HttpStatus.CONFLICT).body(new ErrorDTO(e.getMessage()));
        } catch (PinService.PinInvalidoException e) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(new ErrorDTO(e.getMessage()));
        } catch (PinService.PinYaRegistradoException | PinService.PinNoRegistradoException e) {
            return ResponseEntity.status(HttpStatus.CONFLICT).body(new ErrorDTO(e.getMessage()));
        } catch (PinService.CuentaBloqueadaException e) {
            return ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS)
                    .header("Retry-After", String.valueOf(e.getSegundos()))
                    .body(new ErrorDTO(e.getMessage()));
        }
    }

    private record ErrorDTO(String error) {
    }

}
