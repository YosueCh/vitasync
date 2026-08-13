package com.vitasync.backend.usuarios.service;

import com.vitasync.backend.usuarios.dto.CrearUsuarioDTO;
import com.vitasync.backend.usuarios.dto.LoginResultadoDTO;
import com.vitasync.backend.usuarios.dto.UsuarioDTO;
import com.vitasync.backend.usuarios.model.Usuario;
import com.vitasync.backend.usuarios.repository.UsuarioRepository;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * Administración de cuentas de usuario de VitaSync (Práctica 13,
 * reinterpretada como una funcionalidad real del sistema en vez de
 * comandos de Windows). Conserva la distinción central de la práctica:
 * deshabilitar una cuenta preserva toda su información y permite
 * revertir el cambio; eliminarla es permanente.
 */
@Service
public class UsuarioService {

    private final Optional<UsuarioRepository> repo;

    public UsuarioService(Optional<UsuarioRepository> repo) {
        this.repo = repo;
    }

    /** false mientras no exista serviceAccountKey.json (ver FirebaseConfig). */
    public boolean isDisponible() {
        return repo.isPresent();
    }

    public UsuarioDTO crear(CrearUsuarioDTO datos) {
        Usuario u = new Usuario();
        u.setId(UUID.randomUUID().toString());
        u.setNombreCompleto(datos.nombreCompleto());
        u.setUsername(datos.username());
        u.setGrupos(datos.grupos());
        // Una cuenta nueva siempre nace habilitada y debe forzar el cambio
        // de contraseña en el primer inicio de sesión (buena práctica que
        // la Práctica 13 identifica al revisar la columna "cambio de
        // contraseña" de cada usuario).
        u.setHabilitado(true);
        u.setRequiereCambioPassword(true);
        u.setFechaCreacion(Instant.now().toString());
        u.setUltimoInicioSesion(null);
        repo.orElseThrow().guardar(u);
        return toDTO(u);
    }

    public List<UsuarioDTO> listar() {
        return repo.orElseThrow().listarTodos().stream().map(this::toDTO).toList();
    }

    public UsuarioDTO obtener(String id) {
        Usuario u = repo.orElseThrow().buscarPorId(id);
        if (u == null) throw new UsuarioNoEncontradoException(id);
        return toDTO(u);
    }

    /** Deshabilitar: la cuenta y sus datos se conservan, solo se bloquea el acceso. */
    public UsuarioDTO deshabilitar(String id) {
        Usuario u = requerir(id);
        u.setHabilitado(false);
        repo.orElseThrow().guardar(u);
        return toDTO(u);
    }

    /** Volver a habilitar: revierte el bloqueo sin perder nada. */
    public UsuarioDTO habilitar(String id) {
        Usuario u = requerir(id);
        u.setHabilitado(true);
        repo.orElseThrow().guardar(u);
        return toDTO(u);
    }

    /** Eliminar: a diferencia de deshabilitar, esto es permanente e irreversible. */
    public void eliminar(String id) {
        requerir(id); // valida que exista antes de intentar borrar
        repo.orElseThrow().eliminar(id);
    }

    /**
     * Simula un intento de inicio de sesión. Si la cuenta está
     * deshabilitada, se rechaza sin importar la contraseña — exactamente
     * el comportamiento que la Práctica 13 pide verificar en Windows.
     */
    public LoginResultadoDTO simularLogin(String id) {
        Usuario u = requerir(id);
        if (!u.isHabilitado()) {
            return new LoginResultadoDTO(false, "La cuenta está deshabilitada. No es posible iniciar sesión.");
        }
        u.setUltimoInicioSesion(Instant.now().toString());
        repo.orElseThrow().guardar(u);
        String aviso = u.isRequiereCambioPassword() ? " (se requiere cambio de contraseña)" : "";
        return new LoginResultadoDTO(true, "Inicio de sesión correcto" + aviso + ".");
    }

    private Usuario requerir(String id) {
        Usuario u = repo.orElseThrow().buscarPorId(id);
        if (u == null) throw new UsuarioNoEncontradoException(id);
        return u;
    }

    private UsuarioDTO toDTO(Usuario u) {
        return new UsuarioDTO(
                u.getId(), u.getNombreCompleto(), u.getUsername(), u.getGrupos(),
                u.isHabilitado(), u.isRequiereCambioPassword(),
                u.getFechaCreacion(), u.getUltimoInicioSesion());
    }

    public static class UsuarioNoEncontradoException extends RuntimeException {
        public UsuarioNoEncontradoException(String id) {
            super("No existe un usuario con id " + id);
        }
    }
}
