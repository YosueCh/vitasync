package com.vitasync.backend.blackbox;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.vitasync.backend.seguridad.Identidad;
import com.vitasync.backend.seguridad.VerificadorToken;

import java.util.Base64;
import java.util.Optional;

/**
 * SOLO PARA PRUEBAS (vive en las clases de prueba, no en el producto): lee los tokens SIN FIRMA que emite el
 * emulador de Firebase Authentication, para poder probar el control de acceso completo sin credenciales de la
 * nube. En producción se usa FirebaseVerificadorToken, que sí comprueba la firma.
 */
public class VerificadorTokenEmulador implements VerificadorToken {

    private final ObjectMapper json = new ObjectMapper();

    @Override
    public Optional<Identidad> verificar(String token) {
        try {
            String[] partes = token.split("[.]", -1);
            if (partes.length != 3) return Optional.empty();
            JsonNode carga = json.readTree(Base64.getUrlDecoder().decode(partes[1]));
            String uid = carga.hasNonNull("user_id") ? carga.get("user_id").asText() : carga.path("sub").asText("");
            if (uid.isBlank()) return Optional.empty();
            long exp = carga.path("exp").asLong(Long.MAX_VALUE);
            if (exp < System.currentTimeMillis() / 1000) return Optional.empty();
            String rol = carga.hasNonNull("rol") ? carga.get("rol").asText() : "paciente";
            return Optional.of(new Identidad(uid, rol));
        } catch (Exception e) {
            return Optional.empty();
        }
    }
}
