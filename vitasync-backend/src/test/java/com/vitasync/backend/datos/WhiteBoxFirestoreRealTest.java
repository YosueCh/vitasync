package com.vitasync.backend.datos;

import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.firestore.Firestore;
import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import com.google.firebase.cloud.FirestoreClient;
import com.vitasync.backend.contactos.ContactoRepository;
import com.vitasync.backend.contactos.ContactoService;
import com.vitasync.backend.contactos.CrearContactoDTO;
import com.vitasync.backend.metas.ActualizarMetasDTO;
import com.vitasync.backend.metas.ConflictoDeVersionException;
import com.vitasync.backend.metas.MetasRepository;
import com.vitasync.backend.metas.MetasService;
import com.vitasync.backend.smartwatch.dto.MetricasDTO;
import com.vitasync.backend.smartwatch.repository.HistorialMetricasRepository;
import com.vitasync.backend.usuarios.dto.CrearUsuarioDTO;
import com.vitasync.backend.usuarios.model.Usuario;
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
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.function.Supplier;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assertions.assertThrows;

/**
 * PRÁCTICA 11 · Fase 4 · Pruebas de caja blanca de la base de datos contra el Firestore REAL del proyecto.
 *
 * Los 8 pasos que pide la práctica (alta válida, alta inválida, consulta existente/inexistente, actualización,
 * eliminación, consulta posterior, concurrencia) sobre TRES operaciones: cuentas (usuarios), contactos y metas; más la
 * medición de tiempos de consulta. Imprime líneas «WB|clave|valor» que se guardan como evidencia.
 *
 * Solo corre con: mvn test -Dtest=WhiteBoxFirestoreRealTest -Dfirestore.real=true -Dfirebase.auth.emulator.host=
 * Todo lo que crea lleva el prefijo «zz-wb» y se borra al terminar.
 */
@EnabledIfSystemProperty(named = "firestore.real", matches = "true")
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
class WhiteBoxFirestoreRealTest {

    private static final String SUFIJO = Long.toString(System.currentTimeMillis(), 36);
    private static final List<Runnable> LIMPIEZA = new ArrayList<>();

    private static Firestore db;
    private static UsuarioRepository usuariosRepo;
    private static ContactoRepository contactosRepo;
    private static MetasRepository metasRepo;
    private static HistorialMetricasRepository historialRepo;
    private static ContactoService contactos;
    private static MetasService metas;
    private static UsuarioService usuarios;

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
        usuariosRepo = new UsuarioRepository(db);
        contactosRepo = new ContactoRepository(db);
        metasRepo = new MetasRepository(db);
        historialRepo = new HistorialMetricasRepository(db);
        contactos = new ContactoService(Optional.of(contactosRepo));
        metas = new MetasService(Optional.of(metasRepo));
        usuarios = new UsuarioService(Optional.of(usuariosRepo), List.of(contactos, metas));
    }

    @AfterAll
    static void limpiar() {
        for (int i = LIMPIEZA.size() - 1; i >= 0; i--) {
            try {
                LIMPIEZA.get(i).run();
            } catch (RuntimeException e) {
                System.out.println("WB|aviso-limpieza|" + e.getMessage());
            }
        }
    }

    private static void wb(String clave, Object valor) {
        System.out.println("WB|" + clave + "|" + valor);
    }

    private static String nuevaCuenta(String etiqueta) {
        String id = usuarios.crear(new CrearUsuarioDTO("WB " + etiqueta, "zzwb" + etiqueta.toLowerCase() + SUFIJO, List.of()), "zz-wb-uid-" + SUFIJO).id();
        LIMPIEZA.add(() -> {
            if (usuariosRepo.buscarPorId(id) != null) usuarios.eliminar(id);
        });
        return id;
    }

    /** Mide una operación N veces y devuelve estadísticas en ms. */
    private static double[] medir(int repeticiones, Runnable operacion) {
        double[] ms = new double[repeticiones];
        for (int i = 0; i < repeticiones; i++) {
            long t0 = System.nanoTime();
            operacion.run();
            ms[i] = (System.nanoTime() - t0) / 1e6;
        }
        return ms;
    }

    private static String estadisticas(double[] ms) {
        double[] orden = ms.clone();
        java.util.Arrays.sort(orden);
        double suma = 0;
        for (double v : ms) suma += v;
        double media = suma / ms.length;
        double var = 0;
        for (double v : ms) var += (v - media) * (v - media);
        double p95 = orden[(int) Math.min(orden.length - 1, Math.ceil(0.95 * orden.length) - 1)];
        return String.format(java.util.Locale.ROOT, "n=%d min=%.1f media=%.1f max=%.1f p95=%.1f desv=%.1f", ms.length, orden[0], media, orden[orden.length - 1], p95, Math.sqrt(var / ms.length));
    }

    // ------------------------------------------------------------------ OPERACIÓN 1: cuentas (colección «usuarios»)

    @Test
    @Order(1)
    void db_cuentas_ochoPasos() throws Exception {
        // 1. Inserción válida
        long t0 = System.nanoTime();
        String id = nuevaCuenta("A");
        wb("DB-01 alta valida (ms)", String.format("%.1f", (System.nanoTime() - t0) / 1e6));
        assertThat(usuariosRepo.buscarPorId(id)).isNotNull();

        // 2. Inserción inválida: nada se escribe
        long antes = usuariosRepo.listarPorPropietario("zz-wb-uid-" + SUFIJO).size();
        assertThrows(UsuarioService.DatoInvalidoException.class, () -> usuarios.crear(new CrearUsuarioDTO("", "", List.of()), "zz-wb-uid-" + SUFIJO));
        assertThrows(UsuarioService.UsernameDuplicadoException.class, () -> usuarios.crear(new CrearUsuarioDTO("Otro", "ZZWBA" + SUFIJO, List.of()), "zz-wb-uid-" + SUFIJO));
        assertThat(usuariosRepo.listarPorPropietario("zz-wb-uid-" + SUFIJO).size()).as("las altas inválidas no escriben nada").isEqualTo(antes);
        wb("DB-02 altas invalidas rechazadas", "datos vacíos → DatoInvalido; usuario repetido (otras mayúsculas) → UsernameDuplicado; 0 escrituras");

        // 3 y 4. Consulta existente / inexistente
        assertThat(usuariosRepo.buscarPorId(id)).isNotNull();
        assertThat(usuariosRepo.buscarPorId("zz-wb-no-existe")).isNull();
        wb("DB-03 consulta existente / inexistente", "documento / null (sin excepción)");

        // 5. Actualización y 7. consulta posterior con un repositorio NUEVO (persistencia real)
        usuarios.deshabilitar(id);
        assertThat(new UsuarioRepository(db).buscarPorId(id).isHabilitado()).isFalse();
        usuarios.habilitar(id);
        assertThat(new UsuarioRepository(db).buscarPorId(id).isHabilitado()).isTrue();
        wb("DB-04 actualizacion persistida", "deshabilitar/habilitar leído con un cliente nuevo");

        // El usuario reservado impide una segunda cuenta; al eliminar se libera
        assertThat(db.collection("usernames").document("zzwba" + SUFIJO).get().get().exists()).as("el usuario queda reservado").isTrue();

        // 6. Eliminación
        usuarios.eliminar(id);
        assertThat(usuariosRepo.buscarPorId(id)).isNull();
        assertThat(usuariosRepo.existeUsername("zzwba" + SUFIJO)).isFalse();
        wb("DB-05 eliminacion", "cuenta borrada y usuario liberado");
    }

    // ------------------------------------------------------------------ OPERACIÓN 2: contactos (subcolección)

    @Test
    @Order(2)
    void db_contactos_ochoPasosYConcurrencia() throws Exception {
        String cuenta = nuevaCuenta("B");
        // 1. alta válida + 7. consulta posterior desde otro repositorio
        var c = contactos.crear(cuenta, new CrearContactoDTO("Mamá", "4421234567", "Familiar"));
        assertThat(new ContactoRepository(db).listar(cuenta)).extracting("id").contains(c.id());
        // 2. altas inválidas / repetidas
        assertThrows(ContactoService.DatoInvalidoException.class, () -> contactos.crear(cuenta, new CrearContactoDTO("", "abc", "Otro")));
        assertThrows(ContactoService.ConflictoException.class, () -> contactos.crear(cuenta, new CrearContactoDTO("Otra", "442 123 4567", "Otro")));
        // 3/4. consulta de una cuenta sin contactos / inexistente: lista vacía, sin excepción
        assertThat(contactosRepo.listar("zz-wb-cuenta-sin-nada")).isEmpty();
        // 6. eliminación y eliminación repetida
        contactos.eliminar(cuenta, c.id());
        assertThrows(ContactoService.ContactoNoEncontradoException.class, () -> contactos.eliminar(cuenta, c.id()));
        assertThat(contactosRepo.listar(cuenta)).isEmpty();
        wb("DB-contactos ocho pasos", "alta / altas inválidas / consulta vacía / baja / baja repetida → OK");

        // 8. CONCURRENCIA REAL: 10 altas simultáneas con teléfonos distintos → como máximo 5 (transacción con cerrojo)
        int hilos = 10;
        ExecutorService pool = Executors.newFixedThreadPool(hilos);
        CyclicBarrier salida = new CyclicBarrier(hilos);
        List<Callable<String>> tareas = new ArrayList<>();
        for (int i = 0; i < hilos; i++) {
            final int n = i;
            tareas.add(() -> {
                salida.await();
                try {
                    contactos.crear(cuenta, new CrearContactoDTO("Contacto " + n, "44211100" + (10 + n), "Otro"));
                    return "CREADO";
                } catch (ContactoService.ConflictoException e) {
                    return "RECHAZADO";
                }
            });
        }
        long t0 = System.nanoTime();
        int creados = 0;
        for (Future<String> f : pool.invokeAll(tareas)) if (f.get().equals("CREADO")) creados++;
        pool.shutdown();
        double ms = (System.nanoTime() - t0) / 1e6;
        int guardados = contactosRepo.listar(cuenta).size();
        wb("DB-06 concurrencia contactos (10 altas simultáneas)", "creados=" + creados + " guardados=" + guardados + " maximo=5 tiempo_ms=" + String.format("%.0f", ms));
        assertThat(guardados).isEqualTo(5);
        assertThat(creados).isEqualTo(5);

        // 8b. 10 altas simultáneas con el MISMO teléfono → una sola
        String cuenta2 = nuevaCuenta("C");
        ExecutorService pool2 = Executors.newFixedThreadPool(hilos);
        CyclicBarrier salida2 = new CyclicBarrier(hilos);
        List<Callable<Boolean>> mismas = new ArrayList<>();
        for (int i = 0; i < hilos; i++) {
            final int n = i;
            mismas.add(() -> {
                salida2.await();
                try {
                    contactos.crear(cuenta2, new CrearContactoDTO("Igual " + n, "4429998877", "Otro"));
                    return true;
                } catch (ContactoService.ConflictoException e) {
                    return false;
                }
            });
        }
        int unicos = 0;
        for (Future<Boolean> f : pool2.invokeAll(mismas)) if (f.get()) unicos++;
        pool2.shutdown();
        wb("DB-06 concurrencia mismo telefono (10 altas)", "creados=" + unicos + " guardados=" + contactosRepo.listar(cuenta2).size());
        assertThat(contactosRepo.listar(cuenta2)).hasSize(1);

        // Al eliminar la cuenta no queda el documento «cerrojo» huérfano
        usuarios.eliminar(cuenta);
        assertThat(db.collection("usuarios").document(cuenta).collection("preferencias").document("cerrojo-contactos").get().get().exists()).isFalse();
        wb("DB-05 cascada", "se borran contactos y el cerrojo de la cuenta");
    }

    // ------------------------------------------------------------------ OPERACIÓN 3: metas (documento con versión)

    @Test
    @Order(3)
    void db_metas_ochoPasos() throws Exception {
        String cuenta = nuevaCuenta("D");
        // 3/4. sin editar nunca: no existe el documento (Optional vacío) y el servicio devuelve las predeterminadas
        assertThat(metasRepo.obtener(cuenta)).isEmpty();
        assertThat(metas.obtener(cuenta).version()).isZero();
        // 1. alta válida (versión 0 → 1)
        var m = metas.actualizar(cuenta, new ActualizarMetasDTO(8000, null, null, 0L, null), "Paciente");
        assertThat(m.version()).isEqualTo(1);
        // 2. inválida: fuera de rango, no escribe
        assertThrows(MetasService.DatoInvalidoException.class, () -> metas.actualizar(cuenta, new ActualizarMetasDTO(999, null, null, 1L, null), "Paciente"));
        assertThat(metasRepo.obtener(cuenta).orElseThrow().version()).isEqualTo(1);
        // 5. actualización con la versión vigente, y con una vieja → conflicto
        assertThat(metas.actualizar(cuenta, new ActualizarMetasDTO(null, 700, null, 1L, null), "Médico").version()).isEqualTo(2);
        assertThrows(ConflictoDeVersionException.class, () -> metas.actualizar(cuenta, new ActualizarMetasDTO(7000, null, null, 1L, null), "Paciente"));
        // 7. consulta posterior desde un repositorio nuevo
        var leido = new MetasRepository(db).obtener(cuenta).orElseThrow();
        assertThat(leido.metaPasos()).isEqualTo(8000);
        assertThat(leido.metaCalorias()).isEqualTo(700);
        assertThat(leido.actualizadaPor()).isEqualTo("Médico");
        // 6. eliminación
        metasRepo.eliminar(cuenta);
        assertThat(metasRepo.obtener(cuenta)).isEmpty();
        wb("DB-metas ocho pasos", "alta v1 / inválida / update v2 / conflicto / lectura / baja → OK");
    }

    // ------------------------------------------------------------------ Integridad entre cuentas: concurrencia de «username»

    @Test
    @Order(4)
    void db_concurrenciaUsername_diezAltasSimultaneas_soloUnaCuenta() throws Exception {
        String username = "zzwbmismo" + SUFIJO;
        int hilos = 10;
        ExecutorService pool = Executors.newFixedThreadPool(hilos);
        CyclicBarrier salida = new CyclicBarrier(hilos);
        List<Callable<String>> tareas = new ArrayList<>();
        for (int i = 0; i < hilos; i++) {
            final int n = i;
            tareas.add(() -> {
                salida.await();
                try {
                    String id = usuarios.crear(new CrearUsuarioDTO("Persona " + n, username, List.of()), "zz-wb-uid-" + SUFIJO).id();
                    LIMPIEZA.add(() -> {
                        if (usuariosRepo.buscarPorId(id) != null) usuarios.eliminar(id);
                    });
                    return id;
                } catch (UsuarioService.UsernameDuplicadoException e) {
                    return null;
                }
            });
        }
        int creadas = 0;
        for (Future<String> f : pool.invokeAll(tareas)) if (f.get() != null) creadas++;
        pool.shutdown();
        long conEseUsuario = usuariosRepo.listarTodos().stream().filter(u -> username.equals(u.getUsername())).count();
        wb("DB-02/06 concurrencia username (10 altas simultáneas)", "creadas=" + creadas + " cuentas_con_ese_usuario=" + conEseUsuario);
        assertThat(conEseUsuario).isEqualTo(1);
        assertThat(creadas).isEqualTo(1);
    }

    // ------------------------------------------------------------------ Mediciones de consultas (≥3, con repeticiones)

    @Test
    @Order(5)
    void db_mediciones_tiemposDeConsulta() {
        String cuenta = nuevaCuenta("M");
        for (int i = 0; i < 5; i++) contactos.crear(cuenta, new CrearContactoDTO("Contacto " + i, "44255500" + (10 + i), "Otro"));
        Instant t0 = Instant.now().minusSeconds(600);
        for (int i = 0; i < 20; i++) historialRepo.guardar(cuenta, new MetricasDTO(100 * i, 10 * i, 7.0, 70, 90, t0.plusSeconds(30L * i)));
        LIMPIEZA.add(() -> historialRepo.eliminarTodo(cuenta));

        // Consulta 1: por identificador (lectura de un documento)
        wb("Q1 buscarPorId (documento)", estadisticas(medir(10, () -> usuariosRepo.buscarPorId(cuenta))));
        // Consulta 2: subcolección ordenada (orderBy creadoEn)
        wb("Q2 listar contactos (subcoleccion + orderBy)", estadisticas(medir(10, () -> contactosRepo.listar(cuenta))));
        // Consulta 3: últimas lecturas (orderBy timestamp desc + limit 10)
        wb("Q3 historial ultimas(10) (orderBy + limit)", estadisticas(medir(10, () -> historialRepo.ultimas(cuenta, 10))));
        // Consulta 4: unicidad de usuario (whereEqualTo + limit 1)
        wb("Q4 existeUsername (whereEqualTo + limit 1)", estadisticas(medir(10, () -> usuariosRepo.existeUsername("zzwbm" + SUFIJO))));
        // Consulta 5: cuentas de una persona (whereEqualTo propietarioUid)
        wb("Q5 listarPorPropietario (whereEqualTo)", estadisticas(medir(10, () -> usuariosRepo.listarPorPropietario("zz-wb-uid-" + SUFIJO))));
        // Consulta 6: ANTES de la corrección se usaba esta (colección completa)
        wb("Q6 listarTodos (coleccion completa) con pocos docs", estadisticas(medir(10, () -> usuariosRepo.listarTodos())));
        wb("Q6 documentos en la coleccion usuarios", usuariosRepo.listarTodos().size());
    }

    @Test
    @Order(6)
    void db_mediciones_escalaDeLaLecturaCompleta() throws Exception {
        // Se siembran 100 cuentas de relleno para ver cómo crece «leer toda la colección» frente a una consulta con filtro.
        int n = 100;
        List<String> ids = new ArrayList<>();
        for (int i = 0; i < n; i++) {
            Usuario u = new Usuario();
            u.setId("zz-wb-relleno-" + SUFIJO + "-" + i);
            u.setNombreCompleto("Relleno " + i);
            u.setUsername("zzwbrelleno" + SUFIJO + i);
            u.setGrupos(List.of());
            u.setHabilitado(true);
            u.setFechaCreacion(Instant.now().toString());
            u.setPropietarioUid("zz-wb-uid-relleno");
            usuariosRepo.guardar(u);
            ids.add(u.getId());
        }
        LIMPIEZA.add(() -> ids.forEach(id -> {
            try {
                db.collection("usuarios").document(id).delete().get();
            } catch (Exception e) {
                throw new IllegalStateException(e);
            }
        }));
        int total = usuariosRepo.listarTodos().size();
        wb("ESCALA documentos en usuarios", total);
        wb("ESCALA listarTodos (leer toda la coleccion)", estadisticas(medir(10, () -> usuariosRepo.listarTodos())));
        wb("ESCALA existeUsername (consulta con limit 1)", estadisticas(medir(10, () -> usuariosRepo.existeUsername("zzwbrelleno" + SUFIJO + "0"))));
        wb("ESCALA listarPorPropietario (filtro en el servidor)", estadisticas(medir(10, () -> usuariosRepo.listarPorPropietario("zz-wb-uid-" + SUFIJO))));
        wb("ESCALA listarPorPropietario devuelve", usuariosRepo.listarPorPropietario("zz-wb-uid-relleno").size() + " cuentas (las del relleno)");
        assertThat(total).isGreaterThanOrEqualTo(n);
    }

    @SuppressWarnings("unused")
    private static <T> T uno(Supplier<T> s) {
        return s.get();
    }
}
