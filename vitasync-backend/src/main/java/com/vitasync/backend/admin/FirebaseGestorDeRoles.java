package com.vitasync.backend.admin;

import com.google.firebase.auth.ExportedUserRecord;
import com.google.firebase.auth.FirebaseAuth;
import com.google.firebase.auth.FirebaseAuthException;
import com.google.firebase.auth.ListUsersPage;
import com.google.firebase.auth.UserRecord;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/** Roles guardados como claim «rol» de Firebase Authentication. Solo existe con la seguridad activa. */
@Component
@ConditionalOnProperty(name = "vitasync.seguridad.activa", havingValue = "true")
public class FirebaseGestorDeRoles implements GestorDeRoles {

    @Override
    public List<Persona> listar() {
        try {
            List<Persona> personas = new ArrayList<>();
            ListUsersPage pagina = FirebaseAuth.getInstance().listUsers(null);
            while (pagina != null) {
                for (ExportedUserRecord u : pagina.getValues()) personas.add(aPersona(u));
                pagina = pagina.getNextPage();
            }
            return personas;
        } catch (FirebaseAuthException e) {
            throw new IllegalStateException("No se pudo consultar Firebase Authentication", e);
        }
    }

    @Override
    public Optional<Persona> buscar(String uid) {
        try {
            return Optional.of(aPersona(FirebaseAuth.getInstance().getUser(uid)));
        } catch (FirebaseAuthException e) {
            return Optional.empty();
        }
    }

    @Override
    public void asignar(String uid, String rol) {
        try {
            UserRecord u = FirebaseAuth.getInstance().getUser(uid);
            Map<String, Object> claims = new HashMap<>(u.getCustomClaims());
            claims.put("rol", rol);
            FirebaseAuth.getInstance().setCustomUserClaims(uid, claims);
        } catch (FirebaseAuthException e) {
            throw new IllegalStateException("No se pudo asignar el rol", e);
        }
    }

    private static Persona aPersona(UserRecord u) {
        Object rol = u.getCustomClaims().get("rol");
        return new Persona(u.getUid(), u.getEmail(), rol instanceof String s ? s : "paciente");
    }
}
