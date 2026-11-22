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

    /**
     * Cuánto se recuerda el dueño de una cuenta (WB-HALLAZGO-12). El dueño NUNCA cambia después de crear la cuenta; lo
     * único que puede pasar es que la cuenta se elimine, y eso invalida la entrada en {@link #eliminar}.
     */
    static final long VIGENCIA_DUENOS_MS = 60_000;
    private static final int MAX_DUENOS_EN_CACHE = 10_000;

    private record DuenoEnCache(String uid, long venceEn) {
    }

    private final Optional<UsuarioRepository> repo;
    private final List<LimpiezaDeCuenta> limpiezas;
    private final java.time.Clock reloj;
    private final long vigenciaMs;
    private final java.util.Map<String, DuenoEnCache> duenos = new java.util.concurrent.ConcurrentHashMap<>();

    /**
     * @param vigenciaMs cuánto se recuerda el dueño de una cuenta; 0 (o menos) apaga el caché. Se configura con
     *                   {@code vitasync.cache-duenos.vigencia-ms} (por omisión 60000); apagarlo sirve para comparar
     *                   el rendimiento con y sin caché (Práctica 11, fase 5).
     */
    @org.springframework.beans.factory.annotation.Autowired
    public UsuarioService(Optional<UsuarioRepository> repo, List<LimpiezaDeCuenta> limpiezas,
                          @org.springframework.beans.factory.annotation.Value("${vitasync.cache-duenos.vigencia-ms:60000}") long vigenciaMs) {
        this(repo, limpiezas, vigenciaMs, java.time.Clock.systemUTC());
    }

    public UsuarioService(Optional<UsuarioRepository> repo, List<LimpiezaDeCuenta> limpiezas) {
        this(repo, limpiezas, VIGENCIA_DUENOS_MS, java.time.Clock.systemUTC());
    }

    /** Con reloj propio, para probar la caducidad del caché. */
    UsuarioService(Optional<UsuarioRepository> repo, List<LimpiezaDeCuenta> limpiezas, java.time.Clock reloj) {
        this(repo, limpiezas, VIGENCIA_DUENOS_MS, reloj);
    }

    private UsuarioService(Optional<UsuarioRepository> repo, List<LimpiezaDeCuenta> limpiezas, long vigenciaMs, java.time.Clock reloj) {
        this.repo = repo;
        this.limpiezas = limpiezas;
        this.vigenciaMs = vigenciaMs;
        this.reloj = reloj;
    }

    /** Sin limpiezas de datos asociados (pruebas de la propia cuenta). */
    public UsuarioService(Optional<UsuarioRepository> repo) {
        this(repo, List.of());
    }

    /** false mientras no exista serviceAccountKey.json (ver FirebaseConfig). */
    public boolean isDisponible() {
        return repo.isPresent();
    }

    /** Alta sin dueño (siembra de datos de ejemplo y pruebas). */
    public UsuarioDTO crear(CrearUsuarioDTO datos) {
        return crear(datos, null);
    }

    /**
     * Alta de cuenta. Valida en el SERVIDOR (defectos D-01 y D-02 de la Práctica 8):
     * nombre y usuario obligatorios, usuario con formato válido y único.
     * {@code propietarioUid} es el UID de quien la crea (Práctica 10); nunca viene del cuerpo de la petición.
     */
    public UsuarioDTO crear(CrearUsuarioDTO datos, String propietarioUid) {
        String nombre = datos == null || datos.nombreCompleto() == null ? "" : datos.nombreCompleto().trim();
        String username = datos == null || datos.username() == null ? "" : datos.username().trim().toLowerCase();
        if (nombre.length() < 2 || nombre.length() > 80) {
            throw new DatoInvalidoException("El nombre completo es obligatorio (2 a 80 caracteres).");
        }
        if (!USERNAME_VALIDO.matcher(username).matches()) {
            throw new DatoInvalidoException("El usuario es obligatorio: 3 a 30 caracteres entre letras, números, punto, guion y guion bajo.");
        }
        // Comprobación rápida con una consulta indexada (antes se leía TODA la colección: WB-HALLAZGO-10). La garantía
        // real contra altas simultáneas es guardarSiUsernameLibre, más abajo (WB-HALLAZGO-9).
        if (repo.orElseThrow().existeUsername(username)) {
            throw new UsernameDuplicadoException(username);
        }
        Usuario u = new Usuario();
        u.setId(UUID.randomUUID().toString());
        u.setNombreCompleto(nombre);
        u.setUsername(username);
        u.setGrupos(datos.grupos() == null ? List.of() : datos.grupos());
        u.setPropietarioUid(propietarioUid);
        // Una cuenta nueva siempre nace habilitada y debe forzar el cambio
        // de contraseña en el primer inicio de sesión (buena práctica que
        // la Práctica 13 identifica al revisar la columna "cambio de
        // contraseña" de cada usuario).
        u.setHabilitado(true);
        u.setRequiereCambioPassword(true);
        u.setFechaCreacion(Instant.now().toString());
        u.setUltimoInicioSesion(null);
        if (!repo.orElseThrow().guardarSiUsernameLibre(u)) {
            throw new UsernameDuplicadoException(username);
        }
        return toDTO(u);
    }

    public List<UsuarioDTO> listar() {
        return repo.orElseThrow().listarTodos().stream().map(this::toDTO).toList();
    }

    /** Solo las cuentas de una persona (Práctica 10): nadie ve las cuentas de otra. */
    public List<UsuarioDTO> listarDe(String propietarioUid) {
        if (propietarioUid == null) return List.of();
        return repo.orElseThrow().listarPorPropietario(propietarioUid).stream().map(this::toDTO).toList();
    }

    /** UID del dueño de la cuenta; vacío si la cuenta no existe o no tiene dueño. */
    public Optional<String> propietarioDe(String id) {
        // Cada petición autenticada pasa por aquí (ControlDeAcceso). Sin caché era UNA lectura de Firestore (~90 ms) por
        // petición, antes de hacer el trabajo real. Solo se recuerdan los dueños ENCONTRADOS; «no existe» se vuelve a
        // consultar siempre, para que una cuenta recién creada se vea de inmediato.
        long ahora = reloj.millis();
        DuenoEnCache guardado = vigenciaMs > 0 ? duenos.get(id) : null;
        if (guardado != null && guardado.venceEn() > ahora) return Optional.of(guardado.uid());
        Usuario u = repo.orElseThrow().buscarPorId(id);
        if (u == null || u.getPropietarioUid() == null) {
            duenos.remove(id);
            return Optional.empty();
        }
        if (vigenciaMs > 0) {
            if (duenos.size() >= MAX_DUENOS_EN_CACHE) duenos.clear(); // tope de memoria
            duenos.put(id, new DuenoEnCache(u.getPropietarioUid(), ahora + vigenciaMs));
        }
        return Optional.of(u.getPropietarioUid());
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

    /**
     * Eliminar: a diferencia de deshabilitar, esto es permanente e irreversible. Se borran primero los datos
     * de la cuenta (reloj, historial, chat, órdenes) y al final la cuenta: si algo falla a medias, la cuenta
     * sigue existiendo y se puede volver a intentar, en vez de dejar datos huérfanos sin dueño (D-04).
     */
    public void eliminar(String id) {
        requerir(id); // valida que exista antes de intentar borrar
        duenos.remove(id); // desde este momento nadie debe seguir pasando por el caché
        limpiezas.forEach(l -> l.borrarDatosDe(id));
        repo.orElseThrow().eliminar(id);
        duenos.remove(id);
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
                u.getFechaCreacion(), u.getUltimoInicioSesion(), u.getPinHash() != null);
    }

    private static final java.util.regex.Pattern USERNAME_VALIDO = java.util.regex.Pattern.compile("^[a-z0-9._-]{3,30}$");

    /** Datos del alta que no cumplen las reglas (400). */
    public static class DatoInvalidoException extends RuntimeException {
        public DatoInvalidoException(String mensaje) {
            super(mensaje);
        }
    }

    /** Ya existe una cuenta con ese usuario (409). */
    public static class UsernameDuplicadoException extends RuntimeException {
        public UsernameDuplicadoException(String username) {
            super("Ya existe una cuenta con el usuario «" + username + "».");
        }
    }

    public static class UsuarioNoEncontradoException extends RuntimeException {
        public UsuarioNoEncontradoException(String id) {
            super("No existe un usuario con id " + id);
        }
    }
}
