package com.vitasync.backend.admin;

import org.springframework.stereotype.Service;

import java.util.HashSet;
import java.util.List;
import java.util.Optional;
import java.util.Set;

/**
 * Asignación masiva de roles por el administrador (Práctica 7 dentro de VitaSync).
 *
 * Reglas: solo se reparten «paciente» y «medico»; el rol de administrador no se concede ni se quita desde aquí
 * (se crea fuera de la app, para que nadie pueda ascenderse ni dejar al sistema sin administrador). Todo el lote
 * se valida ANTES de aplicar el primer cambio: si algo no cumple, no se cambia nada. Firebase no ofrece una
 * escritura atómica de roles, así que un fallo de red a mitad del lote podría dejar cambios parciales; por eso la
 * respuesta lista exactamente qué quedó aplicado.
 */
@Service
public class RolesService {

    public static final int MAX_LOTE = 50;
    private static final Set<String> ASIGNABLES = Set.of("paciente", "medico");

    public record Cambio(String uid, String rol) {
    }

    private final Optional<GestorDeRoles> gestor;

    public RolesService(Optional<GestorDeRoles> gestor) {
        this.gestor = gestor;
    }

    public boolean isDisponible() {
        return gestor.isPresent();
    }

    public List<GestorDeRoles.Persona> personas() {
        return gestor.orElseThrow().listar();
    }

    /** @return las personas ya con su rol nuevo, en el orden pedido */
    public List<GestorDeRoles.Persona> asignar(String adminUid, List<Cambio> cambios) {
        if (cambios == null || cambios.isEmpty()) throw new DatoInvalidoException("Indica al menos un cambio de rol.");
        if (cambios.size() > MAX_LOTE) throw new DatoInvalidoException("Máximo " + MAX_LOTE + " cambios por lote.");
        GestorDeRoles g = gestor.orElseThrow();

        Set<String> vistos = new HashSet<>();
        for (Cambio c : cambios) {
            if (c == null || c.uid() == null || c.uid().isBlank() || c.rol() == null) {
                throw new DatoInvalidoException("Cada cambio necesita uid y rol.");
            }
            if (!ASIGNABLES.contains(c.rol())) {
                throw new DatoInvalidoException("Rol no permitido: «" + c.rol() + "». Solo paciente o medico.");
            }
            if (!vistos.add(c.uid())) throw new DatoInvalidoException("La persona " + c.uid() + " aparece dos veces.");
            if (c.uid().equals(adminUid)) throw new DatoInvalidoException("El administrador no puede cambiar su propio rol.");
            GestorDeRoles.Persona p = g.buscar(c.uid())
                    .orElseThrow(() -> new DatoInvalidoException("No existe la persona " + c.uid() + "."));
            if ("admin".equals(p.rol())) throw new DatoInvalidoException("No se puede cambiar el rol de un administrador.");
        }
        for (Cambio c : cambios) g.asignar(c.uid(), c.rol());
        return cambios.stream().map(c -> g.buscar(c.uid()).orElseThrow()).toList();
    }

    /** Datos que no cumplen las reglas (400). */
    public static class DatoInvalidoException extends RuntimeException {
        public DatoInvalidoException(String mensaje) {
            super(mensaje);
        }
    }
}
