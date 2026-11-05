package com.vitasync.backend.metas;

import com.vitasync.backend.usuarios.service.LimpiezaDeCuenta;
import org.springframework.stereotype.Service;

import java.util.Optional;

/**
 * Metas de salud de una cuenta, editables por la paciente y por su médico (Práctica 9 integrada en VitaSync).
 * Como dos personas pueden cambiarlas a la vez, el guardado tiene control de versión (ver {@link ActualizarMetasDTO}).
 *
 * Rangos válidos (el servidor los comprueba aunque la app ya los revise): pasos de 1000 a 50000, calorías de
 * 100 a 5000 y sueño de 4 a 12 horas por día.
 */
@Service
public class MetasService implements LimpiezaDeCuenta {

    private final Optional<MetasRepository> repo;

    public MetasService(Optional<MetasRepository> repo) {
        this.repo = repo;
    }

    /** false mientras no exista serviceAccountKey.json (ver FirebaseConfig). */
    public boolean isDisponible() {
        return repo.isPresent();
    }

    /** Las metas de la cuenta; si nadie las editó, las predeterminadas (versión 0). */
    public MetasCuentaDTO obtener(String cuentaId) {
        return repo.orElseThrow().obtener(cuentaId).orElse(MetasCuentaDTO.PREDETERMINADAS);
    }

    /**
     * @param actor quién lo hace, decidido por el SERVIDOR a partir del rol del token («Médico», «Paciente»…).
     *              null cuando no hay sesión (seguridad apagada): entonces se usa la etiqueta que mande la app.
     */
    public MetasCuentaDTO actualizar(String cuentaId, ActualizarMetasDTO datos, String actor) {
        if (datos == null || (datos.metaPasos() == null && datos.metaCalorias() == null && datos.metaSueno() == null)) {
            throw new DatoInvalidoException("Indica al menos una meta para cambiar.");
        }
        if (datos.metaPasos() != null && (datos.metaPasos() < 1000 || datos.metaPasos() > 50000)) {
            throw new DatoInvalidoException("La meta de pasos debe estar entre 1000 y 50000.");
        }
        if (datos.metaCalorias() != null && (datos.metaCalorias() < 100 || datos.metaCalorias() > 5000)) {
            throw new DatoInvalidoException("La meta de calorías debe estar entre 100 y 5000.");
        }
        if (datos.metaSueno() != null && (datos.metaSueno().isNaN() || datos.metaSueno() < 4.0 || datos.metaSueno() > 12.0)) {
            throw new DatoInvalidoException("La meta de sueño debe estar entre 4 y 12 horas.");
        }
        if (datos.version() != null && datos.version() < 0) {
            throw new DatoInvalidoException("La versión no es válida.");
        }
        String quien = actor != null ? actor : etiqueta(datos.dispositivo());
        return repo.orElseThrow().actualizar(cuentaId, datos.version(), actual -> new MetasCuentaDTO(
                datos.metaPasos() != null ? datos.metaPasos() : actual.metaPasos(),
                datos.metaCalorias() != null ? datos.metaCalorias() : actual.metaCalorias(),
                datos.metaSueno() != null ? Math.round(datos.metaSueno() * 10) / 10.0 : actual.metaSueno(),
                actual.version(),
                quien));
    }

    private static String etiqueta(String texto) {
        String t = texto == null ? "" : texto.trim();
        if (t.isEmpty()) return "Sin identificar";
        return t.length() > 30 ? t.substring(0, 30) : t;
    }

    /** Al eliminar la cuenta desaparecen también sus metas. */
    @Override
    public void borrarDatosDe(String usuarioId) {
        repo.ifPresent(r -> r.eliminar(usuarioId));
    }

    /** Datos que no cumplen las reglas (400). */
    public static class DatoInvalidoException extends RuntimeException {
        public DatoInvalidoException(String mensaje) {
            super(mensaje);
        }
    }
}
