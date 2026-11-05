package com.vitasync.backend.admin;

import com.vitasync.backend.admin.InvitacionRepository.Invitacion;
import com.vitasync.backend.admin.InvitacionRepository.InvitacionInvalidaException;
import org.springframework.stereotype.Service;

import java.security.SecureRandom;
import java.time.Clock;
import java.util.ArrayDeque;
import java.util.Deque;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

/**
 * Invitaciones de un solo uso con el rol ya asignado (Práctica 7 dentro de VitaSync): el administrador genera un
 * código, se lo da a la persona y, al canjearlo con su sesión, la persona recibe ese rol.
 *
 * Reglas: solo «paciente» y «medico» (nunca administrador); caduca a los 7 días; un solo uso; no se puede usar
 * sobre un administrador; y cada persona tiene un máximo de 5 intentos fallidos cada 15 minutos para que nadie
 * pueda adivinar códigos a fuerza bruta (8 caracteres de un alfabeto de 32 = 40 bits).
 */
@Service
public class InvitacionesService {

    public static final long VIGENCIA_MS = 7L * 24 * 60 * 60 * 1000;
    public static final int MAX_FALLOS = 5;
    public static final long VENTANA_FALLOS_MS = 15L * 60 * 1000;

    private static final String ALFABETO = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // sin I ni O ni 0 ni 1 (se confunden)
    private static final Set<String> ASIGNABLES = Set.of("paciente", "medico");

    private final Optional<InvitacionRepository> repo;
    private final Optional<GestorDeRoles> roles;
    private final Clock reloj;
    private final SecureRandom azar = new SecureRandom();
    private final Map<String, Deque<Long>> fallos = new HashMap<>();

    @org.springframework.beans.factory.annotation.Autowired
    public InvitacionesService(Optional<InvitacionRepository> repo, Optional<GestorDeRoles> roles) {
        this(repo, roles, Clock.systemUTC());
    }

    InvitacionesService(Optional<InvitacionRepository> repo, Optional<GestorDeRoles> roles, Clock reloj) {
        this.repo = repo;
        this.roles = roles;
        this.reloj = reloj;
    }

    public boolean isDisponible() {
        return repo.isPresent() && roles.isPresent();
    }

    public Invitacion crear(String rol) {
        if (rol == null || !ASIGNABLES.contains(rol)) {
            throw new RolesService.DatoInvalidoException("Rol no permitido. Solo paciente o medico.");
        }
        long ahora = reloj.millis();
        StringBuilder c = new StringBuilder();
        for (int i = 0; i < 8; i++) c.append(ALFABETO.charAt(azar.nextInt(ALFABETO.length())));
        Invitacion nueva = new Invitacion(c.toString(), rol, ahora, ahora + VIGENCIA_MS, null);
        repo.orElseThrow().guardar(nueva);
        return nueva;
    }

    public List<Invitacion> listar() {
        return repo.orElseThrow().listar();
    }

    /** @return el rol que quedó asignado a la persona */
    public String canjear(String uid, String codigoEscrito) {
        String codigo = codigoEscrito == null ? "" : codigoEscrito.trim().toUpperCase();
        if (!codigo.matches("[A-Z0-9]{8}")) throw new RolesService.DatoInvalidoException("El código tiene 8 letras o números.");
        long ahora = reloj.millis();
        exigirCupoDeIntentos(uid, ahora);

        GestorDeRoles gestor = roles.orElseThrow();
        GestorDeRoles.Persona persona = gestor.buscar(uid)
                .orElseThrow(() -> new RolesService.DatoInvalidoException("No se encontró tu cuenta de acceso."));
        if ("admin".equals(persona.rol())) {
            throw new RolesService.DatoInvalidoException("Un administrador no puede cambiar su rol con una invitación.");
        }
        Invitacion usada;
        try {
            usada = repo.orElseThrow().canjear(codigo, uid, ahora);
        } catch (InvitacionInvalidaException e) {
            registrarFallo(uid, ahora);
            throw e;
        }
        gestor.asignar(uid, usada.rol());
        return usada.rol();
    }

    private synchronized void exigirCupoDeIntentos(String uid, long ahora) {
        Deque<Long> f = fallos.computeIfAbsent(uid, k -> new ArrayDeque<>());
        while (!f.isEmpty() && ahora - f.peekFirst() > VENTANA_FALLOS_MS) f.pollFirst();
        if (f.size() >= MAX_FALLOS) throw new DemasiadosIntentosException();
    }

    private synchronized void registrarFallo(String uid, long ahora) {
        fallos.computeIfAbsent(uid, k -> new ArrayDeque<>()).addLast(ahora);
    }

    /** Demasiados códigos equivocados seguidos (429). */
    public static class DemasiadosIntentosException extends RuntimeException {
        public DemasiadosIntentosException() {
            super("Demasiados intentos con códigos incorrectos. Espera unos minutos.");
        }
    }
}
