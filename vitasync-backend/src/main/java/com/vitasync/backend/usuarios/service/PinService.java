package com.vitasync.backend.usuarios.service;

import com.vitasync.backend.usuarios.dto.LoginResultadoDTO;
import com.vitasync.backend.usuarios.model.Usuario;
import com.vitasync.backend.usuarios.repository.UsuarioRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.HexFormat;
import java.util.Optional;

/**
 * PIN de 4 dígitos de la vista móvil (Parcial 2), verificado en el servidor.
 *
 * Es la misma idea que el AuthService del reloj (salt aleatorio de 16 bytes y
 * SHA-256 de "salt:pin"), pero el hash vive aquí y no en el navegador, que no
 * tiene un almacén seguro como el Keystore de Android. Un PIN de 4 dígitos
 * tiene solo 10 000 combinaciones, así que tras {@link #MAX_INTENTOS} fallos
 * seguidos la cuenta se bloquea {@link #BLOQUEO} (respuesta 429).
 */
@Service
public class PinService {

    public static final int MAX_INTENTOS = 5;
    public static final Duration BLOQUEO = Duration.ofMinutes(5);

    private static final SecureRandom ALEATORIO = new SecureRandom();

    private final Optional<UsuarioRepository> repo;
    private final Clock reloj;

    @Autowired
    public PinService(Optional<UsuarioRepository> repo) {
        this(repo, Clock.systemUTC());
    }

    /** El reloj se inyecta para poder probar el bloqueo sin esperar 5 minutos. */
    PinService(Optional<UsuarioRepository> repo, Clock reloj) {
        this.repo = repo;
        this.reloj = reloj;
    }

    public boolean isDisponible() {
        return repo.isPresent();
    }

    /** Registra el PIN de una cuenta que todavía no tiene uno. Cambiarlo exigirá el PIN actual. */
    public LoginResultadoDTO registrar(String id, String pin) {
        validarFormato(pin);
        Usuario u = requerir(id);
        if (u.getPinHash() != null) {
            throw new PinYaRegistradoException();
        }
        byte[] sal = new byte[16];
        ALEATORIO.nextBytes(sal);
        String salHex = HexFormat.of().formatHex(sal);
        u.setPinSalt(salHex);
        u.setPinHash(hash(salHex, pin));
        u.setPinIntentosFallidos(0);
        u.setPinBloqueadoHasta(null);
        repo.orElseThrow().guardar(u);
        return new LoginResultadoDTO(true, "PIN registrado.");
    }

    public LoginResultadoDTO verificar(String id, String pin) {
        validarFormato(pin);
        Usuario u = requerir(id);
        if (!u.isHabilitado()) {
            return new LoginResultadoDTO(false, "La cuenta está deshabilitada.");
        }
        if (u.getPinHash() == null) {
            throw new PinNoRegistradoException();
        }
        Instant ahora = reloj.instant();
        if (u.getPinBloqueadoHasta() != null) {
            Instant hasta = Instant.parse(u.getPinBloqueadoHasta());
            if (ahora.isBefore(hasta)) {
                throw new CuentaBloqueadaException(Duration.between(ahora, hasta).toSeconds() + 1);
            }
            // El bloqueo ya venció: se empieza de cero.
            u.setPinBloqueadoHasta(null);
            u.setPinIntentosFallidos(0);
        }

        if (sonIguales(u.getPinHash(), hash(u.getPinSalt(), pin))) {
            u.setPinIntentosFallidos(0);
            u.setPinBloqueadoHasta(null);
            u.setUltimoInicioSesion(ahora.toString());
            repo.orElseThrow().guardar(u);
            return new LoginResultadoDTO(true, "PIN correcto.");
        }

        int fallos = u.getPinIntentosFallidos() + 1;
        if (fallos >= MAX_INTENTOS) {
            u.setPinIntentosFallidos(0);
            u.setPinBloqueadoHasta(ahora.plus(BLOQUEO).toString());
            repo.orElseThrow().guardar(u);
            throw new CuentaBloqueadaException(BLOQUEO.toSeconds());
        }
        u.setPinIntentosFallidos(fallos);
        repo.orElseThrow().guardar(u);
        int quedan = MAX_INTENTOS - fallos;
        return new LoginResultadoDTO(false,
                "PIN incorrecto. Te quedan " + quedan + (quedan == 1 ? " intento." : " intentos."));
    }

    static String hash(String salHex, String pin) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest((salHex + ":" + pin).getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 no disponible", e);
        }
    }

    /** Comparación en tiempo constante: no revela cuántos caracteres coinciden. */
    private static boolean sonIguales(String a, String b) {
        return MessageDigest.isEqual(a.getBytes(StandardCharsets.UTF_8), b.getBytes(StandardCharsets.UTF_8));
    }

    private static void validarFormato(String pin) {
        if (pin == null || !pin.matches("\\d{4}")) {
            throw new PinInvalidoException();
        }
    }

    private Usuario requerir(String id) {
        Usuario u = repo.orElseThrow().buscarPorId(id);
        if (u == null) throw new UsuarioService.UsuarioNoEncontradoException(id);
        return u;
    }

    public static class PinInvalidoException extends RuntimeException {
        public PinInvalidoException() {
            super("El PIN debe tener exactamente 4 dígitos.");
        }
    }

    public static class PinYaRegistradoException extends RuntimeException {
        public PinYaRegistradoException() {
            super("La cuenta ya tiene un PIN registrado.");
        }
    }

    public static class PinNoRegistradoException extends RuntimeException {
        public PinNoRegistradoException() {
            super("La cuenta todavía no tiene un PIN registrado.");
        }
    }

    public static class CuentaBloqueadaException extends RuntimeException {
        private final long segundos;

        public CuentaBloqueadaException(long segundos) {
            super("Demasiados intentos fallidos. Intenta de nuevo en " + Math.max(1, (segundos + 59) / 60) + " min.");
            this.segundos = segundos;
        }

        public long getSegundos() {
            return segundos;
        }
    }
}
