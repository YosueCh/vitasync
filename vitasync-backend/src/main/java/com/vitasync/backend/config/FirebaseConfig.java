package com.vitasync.backend.config;

import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.firestore.Firestore;
import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import com.google.firebase.cloud.FirestoreClient;
import com.vitasync.backend.cast.repository.CastSessionRepository;
import com.vitasync.backend.smartwatch.repository.DispositivoRepository;
import com.vitasync.backend.smartwatch.repository.HistorialMetricasRepository;
import com.vitasync.backend.usuarios.repository.UsuarioRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.io.ClassPathResource;

import java.io.IOException;
import java.io.InputStream;
import java.util.Optional;

/**
 * Inicializa Firebase y expone Firestore como bean SOLO si existe
 * src/main/resources/serviceAccountKey.json (descargado desde la consola
 * de Firebase: Configuración del proyecto > Cuentas de servicio > Generar
 * nueva clave privada).
 *
 * Esto es intencional: sin esta condición, el backend entero fallaría al
 * arrancar en cualquier máquina donde todavía no se haya creado un
 * proyecto Firebase (por ejemplo, mientras solo se está probando el
 * buscador con Elasticsearch). Con ella, /api/smartwatch/* simplemente
 * responde 503 hasta que agregues la clave (ver DispositivoRepository /
 * SmartwatchService).
 */
@Configuration
public class FirebaseConfig {

    private static final Logger log = LoggerFactory.getLogger(FirebaseConfig.class);
    private static final String CLAVE = "serviceAccountKey.json";

    @Bean
    public Firestore firestore() {
        ClassPathResource recurso = new ClassPathResource(CLAVE);
        if (!recurso.exists()) {
            log.warn("No se encontró {} en resources: los endpoints /api/smartwatch/* quedarán deshabilitados. "
                    + "Descárgalo desde la consola de Firebase y colócalo en src/main/resources/.", CLAVE);
            return null;
        }
        try (InputStream cuentaServicio = recurso.getInputStream()) {
            FirebaseOptions opciones = FirebaseOptions.builder()
                    .setCredentials(GoogleCredentials.fromStream(cuentaServicio))
                    .build();
            if (FirebaseApp.getApps().isEmpty()) {
                FirebaseApp.initializeApp(opciones);
            }
            return FirestoreClient.getFirestore();
        } catch (IOException e) {
            log.error("No se pudo inicializar Firebase con {}: {}", CLAVE, e.getMessage());
            return null;
        }
    }

    /**
     * El parámetro es Optional<Firestore> (no Firestore) a propósito: si
     * fuera obligatorio, Spring no podría resolverlo cuando firestore()
     * devuelve null (queda "ignorado", no registrado como bean) y tumbaría
     * el arranque completo de la aplicación en vez de solo deshabilitar
     * este repositorio.
     */
    @Bean
    public DispositivoRepository dispositivoRepository(Optional<Firestore> firestore) {
        return firestore.map(DispositivoRepository::new).orElse(null);
    }

    @Bean
    public HistorialMetricasRepository historialMetricasRepository(Optional<Firestore> firestore) {
        return firestore.map(HistorialMetricasRepository::new).orElse(null);
    }

    @Bean
    public UsuarioRepository usuarioRepository(Optional<Firestore> firestore) {
        return firestore.map(UsuarioRepository::new).orElse(null);
    }

    @Bean
    public com.vitasync.backend.contactos.ContactoRepository contactoRepository(Optional<Firestore> firestore) {
        return firestore.map(com.vitasync.backend.contactos.ContactoRepository::new).orElse(null);
    }

    @Bean
    public CastSessionRepository castSessionRepository(Optional<Firestore> firestore) {
        return firestore.map(CastSessionRepository::new).orElse(null);
    }
}
