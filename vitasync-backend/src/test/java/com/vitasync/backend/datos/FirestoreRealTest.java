package com.vitasync.backend.datos;

import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.firestore.CollectionReference;
import com.google.cloud.firestore.Firestore;
import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import com.google.firebase.cloud.FirestoreClient;
import com.vitasync.backend.admin.InvitacionRepository;
import com.vitasync.backend.admin.InvitacionRepository.Invitacion;
import com.vitasync.backend.contactos.ContactoRepository;
import com.vitasync.backend.contactos.ContactoService;
import com.vitasync.backend.contactos.CrearContactoDTO;
import com.vitasync.backend.metas.ActualizarMetasDTO;
import com.vitasync.backend.metas.ConflictoDeVersionException;
import com.vitasync.backend.metas.MetasCuentaDTO;
import com.vitasync.backend.metas.MetasRepository;
import com.vitasync.backend.metas.MetasService;
import com.vitasync.backend.smartwatch.dto.MetricasDTO;
import com.vitasync.backend.smartwatch.repository.DispositivoRepository;
import com.vitasync.backend.smartwatch.repository.HistorialMetricasRepository;
import com.vitasync.backend.smartwatch.service.SmartwatchService;
import com.vitasync.backend.usuarios.dto.CrearUsuarioDTO;
import com.vitasync.backend.usuarios.repository.UsuarioRepository;
import com.vitasync.backend.usuarios.service.UsuarioService;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.MethodOrderer;
import org.junit.jupiter.api.Order;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestMethodOrder;
import org.junit.jupiter.api.condition.EnabledIfSystemProperty;

import java.io.FileInputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Los repositorios de Firestore contra el Firestore REAL del proyecto de Firebase (no un emulador): lo que ninguna
 * otra prueba verificaba (Actividad 3): persistencia, transacciones, orden e historial y borrado en cascada de
 * subcolecciones.
 *
 * NO corre con «mvn test» normal: escribe en la nube. Se activa con
 *   mvn test -Dtest=FirestoreRealTest -Dfirestore.real=true
 * y necesita src/main/resources/serviceAccountKey.json. Todo lo que crea lleva el prefijo «zz-prueba-» y se borra al
 * terminar (también si una prueba falla); jamás toca documentos que no creó.
 */
@EnabledIfSystemProperty(named = "firestore.real", matches = "true")
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
class FirestoreRealTest {

    private static final String PREFIJO = "zz-prueba-" + Long.toString(System.currentTimeMillis(), 36);

    private static Firestore db;
    private static final List<Runnable> LIMPIEZA = new ArrayList<>();

    @BeforeAll
    static void conectar() throws Exception {
        Path clave = Path.of("src/main/resources/serviceAccountKey.json");
        org.junit.jupiter.api.Assumptions.assumeTrue(Files.exists(clave), "falta serviceAccountKey.json");
        try (FileInputStream in = new FileInputStream(clave.toFile())) {
            if (FirebaseApp.getApps().isEmpty()) {
                FirebaseApp.initializeApp(FirebaseOptions.builder().setCredentials(GoogleCredentials.fromStream(in)).build());
            }
        }
        db = FirestoreClient.getFirestore();
    }

    @AfterAll
    static void limpiar() {
        // Se borra solo lo creado por esta corrida, en orden inverso, y se reporta si algo no se pudo borrar.
        for (int i = LIMPIEZA.size() - 1; i >= 0; i--) {
            try {
                LIMPIEZA.get(i).run();
            } catch (RuntimeException e) {
                System.err.println("No se pudo limpiar: " + e.getMessage());
            }
        }
    }

    // ------------------------------------------------------------ solo lectura

    @Test
    @Order(0)
    void sondeo_firestoreRespondeYSeVeQueHayEnElProyecto() throws Exception {
        List<String> colecciones = new ArrayList<>();
        for (CollectionReference c : db.listCollections()) colecciones.add(c.getId());
        System.out.println("COLECCIONES RAIZ EN EL PROYECTO REAL: " + colecciones);
        assertThat(colecciones).isNotNull(); // si llegó aquí, la conexión y los permisos del servidor funcionan
    }

    // ------------------------------------------------------------ escritura (solo documentos «zz-prueba-»)

    @Test
    @Order(1)
    void cuentaConTodosSusDatos_seGuardaSeConsultaYSeBorraEnCascada() throws Exception {
        UsuarioRepository usuariosRepo = new UsuarioRepository(db);
        ContactoRepository contactosRepo = new ContactoRepository(db);
        MetasRepository metasRepo = new MetasRepository(db);
        DispositivoRepository dispositivoRepo = new DispositivoRepository(db);
        HistorialMetricasRepository historialRepo = new HistorialMetricasRepository(db);

        ContactoService contactos = new ContactoService(Optional.of(contactosRepo));
        MetasService metas = new MetasService(Optional.of(metasRepo));
        SmartwatchService reloj = new SmartwatchService(Optional.of(dispositivoRepo), Optional.of(historialRepo));
        UsuarioService usuarios = new UsuarioService(Optional.of(usuariosRepo), List.of(contactos, metas, reloj));

        String uid = PREFIJO + "-uid";
        String cuenta = usuarios.crear(new CrearUsuarioDTO("Prueba Firestore", PREFIJO + "-u", List.of()), uid).id();
        LIMPIEZA.add(() -> usuarios.eliminar(cuenta));

        // La cuenta quedó en Firestore con su dueña.
        assertThat(usuariosRepo.buscarPorId(cuenta)).isNotNull();
        assertThat(usuarios.propietarioDe(cuenta)).contains(uid);

        // Datos en subcolecciones y en las otras colecciones de la cuenta.
        contactos.crear(cuenta, new CrearContactoDTO("Mamá", "4421234567", "Familiar"));
        contactos.crear(cuenta, new CrearContactoDTO("Dra. López", "4427654321", "Médico"));
        assertThat(contactos.listar(cuenta)).hasSize(2);

        metas.actualizar(cuenta, new ActualizarMetasDTO(8000, null, null, 0L, null), "Paciente");
        assertThat(metas.obtener(cuenta).metaPasos()).isEqualTo(8000);

        reloj.conectar(cuenta);
        Instant t0 = Instant.now().minusSeconds(120);
        for (int i = 0; i < 3; i++) {
            reloj.sincronizar(cuenta, new MetricasDTO(1000 * (i + 1), 100 * (i + 1), 7.0, 70 + i, 90, t0.plusSeconds(30L * i)));
        }
        List<MetricasDTO> historial = reloj.historial(cuenta, 10);
        assertThat(historial).hasSize(3);
        assertThat(historial.get(0).pasos()).isEqualTo(3000); // la más reciente primero
        assertThat(reloj.metricas(cuenta)).isPresent();

        // Persistencia real: un repositorio NUEVO (otra instancia) ve lo mismo.
        assertThat(new ContactoRepository(db).listar(cuenta)).hasSize(2);
        assertThat(new MetasRepository(db).obtener(cuenta)).isPresent();

        // Borrado en cascada de la cuenta: desaparecen cuenta, subcolecciones, metas, reloj e historial.
        usuarios.eliminar(cuenta);
        assertThat(usuariosRepo.buscarPorId(cuenta)).isNull();
        assertThat(contactosRepo.listar(cuenta)).isEmpty();
        assertThat(metasRepo.obtener(cuenta)).isEmpty();
        assertThat(dispositivoRepo.buscarPorUsuario(cuenta)).isNull();
        assertThat(historialRepo.ultimas(cuenta, 10)).isEmpty();
        // Y ningún documento suelto quedó colgando de la cuenta borrada.
        assertThat(db.collection("usuarios").document(cuenta).collection("contactos").get().get().getDocuments()).isEmpty();
        assertThat(db.collection("devices").document(cuenta).collection("historial").get().get().getDocuments()).isEmpty();
    }

    @Test
    @Order(2)
    void metas_dosGuardadosConLaMismaVersion_laTransaccionDejaPasarSoloUno() throws Exception {
        MetasRepository repo = new MetasRepository(db);
        String cuenta = PREFIJO + "-metas";
        LIMPIEZA.add(() -> repo.eliminar(cuenta));

        List<Callable<String>> tareas = new ArrayList<>();
        for (String quien : List.of("Paciente", "Médico")) {
            tareas.add(() -> {
                try {
                    repo.actualizar(cuenta, 0L, a -> new MetasCuentaDTO(quien.equals("Médico") ? 12000 : 7000, a.metaCalorias(), a.metaSueno(), a.version(), quien));
                    return "OK";
                } catch (ConflictoDeVersionException e) {
                    return "CONFLICTO";
                }
            });
        }
        ExecutorService pool = Executors.newFixedThreadPool(2);
        try {
            List<String> resultados = new ArrayList<>();
            for (Future<String> f : pool.invokeAll(tareas)) resultados.add(f.get());
            assertThat(resultados).containsExactlyInAnyOrder("OK", "CONFLICTO");
        } finally {
            pool.shutdown();
        }
        MetasCuentaDTO final1 = repo.obtener(cuenta).orElseThrow();
        assertThat(final1.version()).isEqualTo(1); // una sola escritura ganó
    }

    @Test
    @Order(3)
    void metas_conflictoDeVersionTrasUnGuardado_devuelveLoActual() {
        MetasRepository repo = new MetasRepository(db);
        String cuenta = PREFIJO + "-metas2";
        LIMPIEZA.add(() -> repo.eliminar(cuenta));
        repo.actualizar(cuenta, 0L, a -> new MetasCuentaDTO(9000, a.metaCalorias(), a.metaSueno(), a.version(), "Médico"));
        try {
            repo.actualizar(cuenta, 0L, a -> a);
            org.junit.jupiter.api.Assertions.fail("debía haber conflicto");
        } catch (ConflictoDeVersionException e) {
            assertThat(e.getActual().metaPasos()).isEqualTo(9000);
            assertThat(e.getActual().actualizadaPor()).isEqualTo("Médico");
        }
    }

    @Test
    @Order(4)
    void invitaciones_dosPersonasConElMismoCodigo_soloUnaLoCanjea() throws Exception {
        InvitacionRepository repo = new InvitacionRepository(db);
        String codigo = (PREFIJO + "-inv").toUpperCase();
        long ahora = System.currentTimeMillis();
        repo.guardar(new Invitacion(codigo, "medico", ahora, ahora + 60_000, null));
        LIMPIEZA.add(() -> db.collection("invitaciones").document(codigo).delete());

        ExecutorService pool = Executors.newFixedThreadPool(2);
        try {
            List<Callable<Boolean>> intentos = new ArrayList<>();
            for (String uid : List.of("uid-a", "uid-b")) {
                intentos.add(() -> {
                    try {
                        repo.canjear(codigo, uid, System.currentTimeMillis());
                        return true;
                    } catch (InvitacionRepository.InvitacionInvalidaException e) {
                        return false;
                    }
                });
            }
            List<Boolean> r = new ArrayList<>();
            for (Future<Boolean> f : pool.invokeAll(intentos)) r.add(f.get());
            assertThat(r).containsExactlyInAnyOrder(true, false);
        } finally {
            pool.shutdown();
        }
        assertThat(repo.obtener(codigo).orElseThrow().usadaPor()).isIn("uid-a", "uid-b");
    }

    @Test
    @Order(5)
    void invitaciones_caducadaYInexistente_seRechazan() {
        InvitacionRepository repo = new InvitacionRepository(db);
        String codigo = (PREFIJO + "-vieja").toUpperCase();
        repo.guardar(new Invitacion(codigo, "medico", 1, 2, null));
        LIMPIEZA.add(() -> db.collection("invitaciones").document(codigo).delete());
        org.junit.jupiter.api.Assertions.assertThrows(InvitacionRepository.InvitacionInvalidaException.class,
                () -> repo.canjear(codigo, "uid-x", System.currentTimeMillis()));
        org.junit.jupiter.api.Assertions.assertThrows(InvitacionRepository.InvitacionInvalidaException.class,
                () -> repo.canjear("NOEXISTE" + PREFIJO.toUpperCase(), "uid-x", System.currentTimeMillis()));
    }
}
