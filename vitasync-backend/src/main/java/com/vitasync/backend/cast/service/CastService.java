package com.vitasync.backend.cast.service;

import com.vitasync.backend.cast.dto.CastSessionDTO;
import com.vitasync.backend.cast.model.CastSession;
import com.vitasync.backend.cast.repository.CastSessionRepository;
import org.springframework.stereotype.Service;

import java.time.Duration;
import java.time.Instant;
import java.util.Optional;
import java.util.Random;

/**
 * Enlace con Smart TV (Práctica 9-10): genera un código corto de
 * emparejamiento (como Chromecast/AirPlay) que la "TV" debe ingresar
 * para confirmar el enlace. El navegador nunca habla directo con la TV:
 * ambos consultan este servicio a través de Spring Boot, igual que el
 * smartwatch (Práctica 5-6).
 */
@Service
public class CastService {

    private static final Duration VIGENCIA = Duration.ofMinutes(5);

    private final Optional<CastSessionRepository> repo;
    private final Random rnd = new Random();

    public CastService(Optional<CastSessionRepository> repo) {
        this.repo = repo;
    }

    public boolean isDisponible() {
        return repo.isPresent();
    }

    /** Genera un código de 6 dígitos y crea la sesión en estado ESPERANDO_TV. */
    public CastSessionDTO generar() {
        CastSessionRepository r = repo.orElseThrow();
        String codigo;
        int intentos = 0;
        do {
            codigo = String.format("%06d", rnd.nextInt(1_000_000));
            intentos++;
        } while (r.buscarPorCodigo(codigo) != null && intentos < 5);

        CastSession s = new CastSession();
        s.setCodigo(codigo);
        s.setEstado("ESPERANDO_TV");
        s.setCreadoEn(Instant.now().toString());
        s.setExpiraEn(Instant.now().plus(VIGENCIA).toString());
        s.setEmparejadoEn(null);
        r.guardar(s);
        return toDTO(s);
    }

    /** La "TV" confirma el emparejamiento ingresando el código mostrado en el emisor. */
    public CastSessionDTO emparejar(String codigo) {
        CastSession s = obtenerVigente(codigo);
        if (!"EMPAREJADO".equals(s.getEstado())) {
            s.setEstado("EMPAREJADO");
            s.setEmparejadoEn(Instant.now().toString());
            repo.orElseThrow().guardar(s);
        }
        return toDTO(s);
    }

    /** El emisor consulta este endpoint (polling) para saber si la TV ya se emparejó. */
    public CastSessionDTO estado(String codigo) {
        return toDTO(obtenerVigente(codigo));
    }

    private CastSession obtenerVigente(String codigo) {
        CastSession s = repo.orElseThrow().buscarPorCodigo(codigo);
        if (s == null) throw new CodigoInvalidoException(codigo);
        if (!"EMPAREJADO".equals(s.getEstado()) && Instant.parse(s.getExpiraEn()).isBefore(Instant.now())) {
            s.setEstado("EXPIRADO");
            repo.orElseThrow().guardar(s);
        }
        if ("EXPIRADO".equals(s.getEstado())) throw new CodigoExpiradoException(codigo);
        return s;
    }

    private CastSessionDTO toDTO(CastSession s) {
        return new CastSessionDTO(s.getCodigo(), s.getEstado(), s.getCreadoEn(), s.getExpiraEn(), s.getEmparejadoEn());
    }

    public static class CodigoInvalidoException extends RuntimeException {
        public CodigoInvalidoException(String codigo) {
            super("No existe una sesión de enlace con el código " + codigo);
        }
    }

    public static class CodigoExpiradoException extends RuntimeException {
        public CodigoExpiradoException(String codigo) {
            super("El código " + codigo + " expiró. Genera uno nuevo desde el dashboard.");
        }
    }
}
