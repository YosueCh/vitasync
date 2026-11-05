package com.vitasync.backend.datos;

import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.firestore.Firestore;
import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import com.google.firebase.auth.FirebaseAuth;
import com.google.firebase.cloud.FirestoreClient;
import com.vitasync.backend.admin.FirebaseGestorDeRoles;
import com.vitasync.backend.contactos.ContactoRepository;
import com.vitasync.backend.contactos.ContactoService;
import com.vitasync.backend.contactos.CrearContactoDTO;
import com.vitasync.backend.metas.ActualizarMetasDTO;
import com.vitasync.backend.metas.MetasRepository;
import com.vitasync.backend.metas.MetasService;
import com.vitasync.backend.seguridad.FirebaseVerificadorToken;
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
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Firebase Authentication y las reglas de Firestore con PERSONAS REALES de la nube (no emuladores):
 * firma real de los tokens, roles como claim y «cada persona lee solo lo suyo» con el SDK de cliente (REST con el
 * token de la persona, sin pasar por el backend).
 *
 * Se activa con
 *   mvn test -Dtest=FirebaseNubeRealTest -Dfirestore.real=true -Dfirebase.apikey=&lt;clave de API web&gt; -Dfirebase.auth.emulator.host=
 * (la clave de API web no es secreta). Crea dos personas «zz-prueba-…» y una cuenta VitaSync; todo se borra al terminar.
 */
@EnabledIfSystemProperty(named = "firestore.real", matches = "true")
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
class FirebaseNubeRealTest {

    private static final String SUFIJO = Long.toString(System.currentTimeMillis(), 36);
    private static final HttpClient HTTP = HttpClient.newHttpClient();
    private static final List<Runnable> LIMPIEZA = new ArrayList<>();

    private static String apiKey;
    private static String proyecto;
    private static Firestore db;

    // personas y cuenta creadas por la prueba
    private static String uidA, tokenA, uidB, tokenB, cuentaDeA, contactoDeA;

    @BeforeAll
    static void conectar() throws Exception {
        apiKey = System.getProperty("firebase.apikey");
        Path clave = Path.of("src/main/resources/serviceAccountKey.json");
        org.junit.jupiter.api.Assumptions.assumeTrue(apiKey != null && !apiKey.isBlank(), "falta -Dfirebase.apikey");
        org.junit.jupiter.api.Assumptions.assumeTrue(Files.exists(clave), "falta serviceAccountKey.json");
        org.junit.jupiter.api.Assumptions.assumeTrue(System.getenv("FIREBASE_AUTH_EMULATOR_HOST") == null
                || System.getenv("FIREBASE_AUTH_EMULATOR_HOST").isEmpty(), "con el emulador de Authentication puesto no se puede probar la nube");
        try (FileInputStream in = new FileInputStream(clave.toFile())) {
            if (FirebaseApp.getApps().isEmpty()) {
                FirebaseApp.initializeApp(FirebaseOptions.builder().setCredentials(GoogleCredentials.fromStream(in)).build());
            }
        }
        db = FirestoreClient.getFirestore();
        proyecto = FirebaseApp.getInstance().getOptions().getProjectId();
        if (proyecto == null) proyecto = campo(Files.readString(clave), "project_id");
    }

    @AfterAll
    static void limpiar() {
        for (int i = LIMPIEZA.size() - 1; i >= 0; i--) {
            try {
                LIMPIEZA.get(i).run();
            } catch (RuntimeException e) {
                System.err.println("No se pudo limpiar: " + e.getMessage());
            }
        }
    }

    // ------------------------------------------------------------ utilidades REST

    private static String campo(String json, String nombre) {
        Matcher m = Pattern.compile("\"" + nombre + "\"\\s*:\\s*\"([^\"]+)\"").matcher(json);
        if (!m.find()) throw new IllegalStateException("No vino «" + nombre + "»: " + json);
        return m.group(1);
    }

    private static String[] identitytoolkit(String operacion, String correo) throws Exception {
        HttpResponse<String> r = HTTP.send(HttpRequest.newBuilder(
                        URI.create("https://identitytoolkit.googleapis.com/v1/accounts:" + operacion + "?key=" + apiKey))
                .header("content-type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString("{\"email\":\"" + correo + "\",\"password\":\"Clave-Segura-9\",\"returnSecureToken\":true}"))
                .build(), HttpResponse.BodyHandlers.ofString());
        return new String[]{campo(r.body(), "localId"), campo(r.body(), "idToken")};
    }

    /** Pide a Firestore, como cliente, con el token de una persona (o sin sesión si es null). Devuelve el código HTTP. */
    private static int firestore(String metodo, String ruta, String token) throws Exception {
        HttpRequest.Builder b = HttpRequest.newBuilder(URI.create(
                "https://firestore.googleapis.com/v1/projects/" + proyecto + "/databases/(default)/documents/" + ruta));
        if (token != null) b.header("Authorization", "Bearer " + token);
        b.header("content-type", "application/json");
        if (metodo.equals("PATCH")) b.method("PATCH", HttpRequest.BodyPublishers.ofString("{\"fields\":{\"x\":{\"stringValue\":\"y\"}}}"));
        else b.GET();
        return HTTP.send(b.build(), HttpResponse.BodyHandlers.discarding()).statusCode();
    }

    // ------------------------------------------------------------ Authentication real

    @Test
    @Order(1)
    void dosPersonasRealesSeRegistranYElServidorVerificaSuTokenFirmado() throws Exception {
        String[] a = identitytoolkit("signUp", "zz-prueba-a-" + SUFIJO + "@uteq.test");
        String[] b = identitytoolkit("signUp", "zz-prueba-b-" + SUFIJO + "@uteq.test");
        uidA = a[0];
        tokenA = a[1];
        uidB = b[0];
        tokenB = b[1];
        LIMPIEZA.add(() -> borrarPersonas(uidA, uidB));

        FirebaseVerificadorToken verificador = new FirebaseVerificadorToken();
        var identidad = verificador.verificar(tokenA);
        assertThat(identidad).isPresent();
        assertThat(identidad.get().uid()).isEqualTo(uidA);
        assertThat(identidad.get().rol()).isEqualTo("paciente"); // sin claim = paciente

        // Un token manipulado (firma alterada) o inventado se rechaza: esto SÍ comprueba la firma real.
        String[] partes = tokenA.split("\\.");
        String firmaAlterada = partes[2].substring(0, partes[2].length() - 3) + (partes[2].endsWith("AAA") ? "BBB" : "AAA");
        assertThat(verificador.verificar(partes[0] + "." + partes[1] + "." + firmaAlterada)).isEmpty();
        assertThat(verificador.verificar("token-inventado")).isEmpty();
        String cuerpoAlterado = java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(
                new String(java.util.Base64.getUrlDecoder().decode(partes[1])).replace(uidA, uidB).getBytes());
        assertThat(verificador.verificar(partes[0] + "." + cuerpoAlterado + "." + partes[2])).isEmpty();
    }

    @Test
    @Order(2)
    void asignarUnRolEnLaNube_elTokenNuevoLoTrae() throws Exception {
        FirebaseGestorDeRoles gestor = new FirebaseGestorDeRoles();
        assertThat(gestor.buscar(uidB)).isPresent();
        gestor.asignar(uidB, "medico");
        assertThat(gestor.buscar(uidB).get().rol()).isEqualTo("medico");
        // Hay que volver a iniciar sesión para que el token traiga el rol nuevo (así lo dice la app a la persona).
        HttpResponse<String> r = HTTP.send(HttpRequest.newBuilder(
                        URI.create("https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=" + apiKey))
                .header("content-type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString("{\"email\":\"zz-prueba-b-" + SUFIJO + "@uteq.test\",\"password\":\"Clave-Segura-9\",\"returnSecureToken\":true}"))
                .build(), HttpResponse.BodyHandlers.ofString());
        tokenB = campo(r.body(), "idToken");
        var identidad = new FirebaseVerificadorToken().verificar(tokenB);
        assertThat(identidad).isPresent();
        assertThat(identidad.get().esMedico()).isTrue();
    }

    // ------------------------------------------------------------ reglas de Firestore con el SDK de cliente

    @Test
    @Order(3)
    void reglas_cadaPersonaLeeSoloLoSuyo_yNadieEscribeDesdeElCliente() throws Exception {
        UsuarioRepository usuariosRepo = new UsuarioRepository(db);
        ContactoService contactos = new ContactoService(Optional.of(new ContactoRepository(db)));
        MetasService metas = new MetasService(Optional.of(new MetasRepository(db)));
        UsuarioService usuarios = new UsuarioService(Optional.of(usuariosRepo), List.of(contactos, metas));

        cuentaDeA = usuarios.crear(new CrearUsuarioDTO("Prueba Nube A", "zzp" + SUFIJO, List.of()), uidA).id();
        LIMPIEZA.add(() -> usuarios.eliminar(cuentaDeA));
        contactoDeA = contactos.crear(cuentaDeA, new CrearContactoDTO("Mamá", "4421234567", "Familiar")).id();
        metas.actualizar(cuentaDeA, new ActualizarMetasDTO(9000, null, null, 0L, null), "Paciente");

        String cuenta = "usuarios/" + cuentaDeA;
        String contacto = cuenta + "/contactos/" + contactoDeA;
        String meta = cuenta + "/preferencias/metas";

        // La dueña lee su cuenta, su contacto y sus metas.
        assertThat(firestore("GET", cuenta, tokenA)).as("A lee su cuenta").isEqualTo(200);
        assertThat(firestore("GET", contacto, tokenA)).as("A lee su contacto").isEqualTo(200);
        assertThat(firestore("GET", meta, tokenA)).as("A lee sus metas").isEqualTo(200);

        // Otra persona real (aunque sea médica) no lee nada de A directo en Firestore.
        assertThat(firestore("GET", cuenta, tokenB)).as("B no lee la cuenta de A").isEqualTo(403);
        assertThat(firestore("GET", contacto, tokenB)).as("B no lee el contacto de A").isEqualTo(403);
        assertThat(firestore("GET", meta, tokenB)).as("B no lee las metas de A").isEqualTo(403);

        // Sin sesión, nada.
        assertThat(firestore("GET", cuenta, null)).as("anónimo no lee").isEqualTo(403);
        assertThat(firestore("GET", contacto, null)).isEqualTo(403);

        // Nadie escribe desde el cliente, ni siquiera la dueña.
        assertThat(firestore("PATCH", cuenta + "?updateMask.fieldPaths=x", tokenA)).as("A no escribe su cuenta").isEqualTo(403);
        assertThat(firestore("PATCH", meta + "?updateMask.fieldPaths=x", tokenA)).as("A no escribe sus metas").isEqualTo(403);
        assertThat(firestore("PATCH", "usuarios/zz-intruso-" + SUFIJO + "?updateMask.fieldPaths=x", tokenA)).as("A no crea cuentas").isEqualTo(403);

        // Las demás colecciones son solo del servidor.
        assertThat(firestore("GET", "tv_sessions/cualquiera", tokenA)).as("tv_sessions cerrada").isEqualTo(403);
        assertThat(firestore("GET", "invitaciones/ABCDEFGH", tokenA)).as("invitaciones cerradas").isEqualTo(403);

        // Listar toda la colección de cuentas (podría traer las de otros) se rechaza completa.
        assertThat(firestore("GET", "usuarios", tokenA)).as("A no lista todas las cuentas").isEqualTo(403);

        // Y el borrado de la cuenta no depende de las reglas: el servidor la elimina.
        usuarios.eliminar(cuentaDeA);
        assertThat(usuariosRepo.buscarPorId(cuentaDeA)).isNull();
    }

    private static void borrarPersonas(String... uids) {
        for (String uid : uids) {
            try {
                FirebaseAuth.getInstance().deleteUser(uid);
            } catch (Exception e) {
                throw new IllegalStateException("No se pudo borrar a " + uid + ": " + e.getMessage(), e);
            }
        }
    }
}
