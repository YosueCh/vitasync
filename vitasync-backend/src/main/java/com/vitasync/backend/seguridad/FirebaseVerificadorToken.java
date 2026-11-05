package com.vitasync.backend.seguridad;

import com.google.firebase.auth.FirebaseAuth;
import com.google.firebase.auth.FirebaseAuthException;
import com.google.firebase.auth.FirebaseToken;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

import java.util.Optional;

/**
 * Verifica ID tokens reales de Firebase Authentication (firma, caducidad y proyecto).
 * Con el emulador de Authentication, basta definir FIREBASE_AUTH_EMULATOR_HOST (p. ej. localhost:9099).
 * Solo existe con vitasync.seguridad.activa=true.
 */
@Component
@ConditionalOnProperty(name = "vitasync.seguridad.activa", havingValue = "true", matchIfMissing = true)
public class FirebaseVerificadorToken implements VerificadorToken {

    @Override
    public Optional<Identidad> verificar(String token) {
        try {
            FirebaseToken t = FirebaseAuth.getInstance().verifyIdToken(token);
            Object rol = t.getClaims().get("rol");
            return Optional.of(new Identidad(t.getUid(), rol instanceof String s ? s : "paciente"));
        } catch (FirebaseAuthException | IllegalArgumentException | IllegalStateException e) {
            return Optional.empty();
        }
    }
}
