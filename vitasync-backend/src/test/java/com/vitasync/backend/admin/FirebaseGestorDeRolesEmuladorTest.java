package com.vitasync.backend.admin;

import com.google.auth.oauth2.AccessToken;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import com.vitasync.backend.seguridad.FirebaseVerificadorToken;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

/**
 * Roles contra Firebase Authentication DE VERDAD (su emulador local, puerto 9099), sin dobles en memoria:
 * {@link FirebaseGestorDeRoles} cambia el claim «rol» y un token nuevo de esa persona ya lo trae.
 * Si el emulador no está encendido (o la variable FIREBASE_AUTH_EMULATOR_HOST no llegó al proceso), se omite.
 *
 * Encender el emulador: npx firebase-tools emulators:start --only auth --project demo-vitasync
 */
class FirebaseGestorDeRolesEmuladorTest {

    private static final String AUTH = "http://localhost:9099/identitytoolkit.googleapis.com/v1";
    private static final HttpClient HTTP = HttpClient.newHttpClient();

    @BeforeAll
    static void conectar() throws Exception {
        assumeTrue(System.getenv("FIREBASE_AUTH_EMULATOR_HOST") != null, "falta FIREBASE_AUTH_EMULATOR_HOST");
        try {
            HTTP.send(HttpRequest.newBuilder(URI.create("http://localhost:9099/")).build(), HttpResponse.BodyHandlers.discarding());
        } catch (java.io.IOException e) {
            assumeTrue(false, "el emulador de Authentication no está encendido");
        }
        if (FirebaseApp.getApps().isEmpty()) {
            FirebaseApp.initializeApp(FirebaseOptions.builder().setProjectId("demo-vitasync")
                    .setCredentials(GoogleCredentials.create(new AccessToken("emulador", null))).build());
        }
    }

    @AfterAll
    static void cerrar() {
        FirebaseApp.getApps().forEach(FirebaseApp::delete);
    }

    private static String[] registrar(String correo) throws Exception {
        HttpResponse<String> r = HTTP.send(HttpRequest.newBuilder(URI.create(AUTH + "/accounts:signUp?key=x"))
                .header("content-type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString("{\"email\":\"" + correo + "\",\"password\":\"clave-segura-1\",\"returnSecureToken\":true}"))
                .build(), HttpResponse.BodyHandlers.ofString());
        String cuerpo = r.body();
        return new String[]{campo(cuerpo, "localId"), campo(cuerpo, "idToken")};
    }

    private static String iniciarSesion(String correo) throws Exception {
        HttpResponse<String> r = HTTP.send(HttpRequest.newBuilder(URI.create(AUTH + "/accounts:signInWithPassword?key=x"))
                .header("content-type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString("{\"email\":\"" + correo + "\",\"password\":\"clave-segura-1\",\"returnSecureToken\":true}"))
                .build(), HttpResponse.BodyHandlers.ofString());
        return campo(r.body(), "idToken");
    }

    private static String campo(String json, String nombre) {
        java.util.regex.Matcher m = java.util.regex.Pattern.compile("\"" + nombre + "\"\\s*:\\s*\"([^\"]+)\"").matcher(json);
        if (!m.find()) throw new IllegalStateException("No vino " + nombre + ": " + json);
        return m.group(1);
    }

    /** El payload del JWT (sin verificar firma: el emulador firma con «none»). */
    private static String payload(String jwt) {
        return new String(java.util.Base64.getUrlDecoder().decode(jwt.split("\\.")[1]), java.nio.charset.StandardCharsets.UTF_8);
    }

    @Test
    void asignarUnRol_loVeElGestorYLoTraeElTokenNuevo() throws Exception {
        String correo = "rol-" + System.nanoTime() + "@prueba.mx";
        String uid = registrar(correo)[0];
        FirebaseGestorDeRoles gestor = new FirebaseGestorDeRoles();

        assertThat(gestor.buscar(uid)).get().extracting(GestorDeRoles.Persona::rol).isEqualTo("paciente"); // sin claim = paciente
        assertThat(gestor.buscar(uid).get().correo()).isEqualTo(correo);

        gestor.asignar(uid, "medico");

        assertThat(gestor.buscar(uid).get().rol()).isEqualTo("medico");
        assertThat(gestor.listar()).extracting(GestorDeRoles.Persona::uid).contains(uid);
        // Un token nuevo de esa persona ya trae el rol en el claim.
        assertThat(payload(iniciarSesion(correo))).contains("\"rol\":\"medico\"");
    }

    @Test
    void personaInexistente_buscarDaVacio() {
        assertThat(new FirebaseGestorDeRoles().buscar("uid-que-no-existe")).isEmpty();
    }

    @Test
    void elLoteCompletoDeRolesServiceFuncionaContraAuthenticationReal() throws Exception {
        String[] a = registrar("lote-a-" + System.nanoTime() + "@prueba.mx");
        String[] b = registrar("lote-b-" + System.nanoTime() + "@prueba.mx");
        RolesService servicio = new RolesService(java.util.Optional.of(new FirebaseGestorDeRoles()));

        var aplicados = servicio.asignar("uid-admin-que-no-es-a-ni-b",
                List.of(new RolesService.Cambio(a[0], "medico"), new RolesService.Cambio(b[0], "medico")));

        assertThat(aplicados).extracting(GestorDeRoles.Persona::rol).containsExactly("medico", "medico");
        // Un lote con una persona inexistente no cambia a nadie (se valida antes).
        String[] c = registrar("lote-c-" + System.nanoTime() + "@prueba.mx");
        org.junit.jupiter.api.Assertions.assertThrows(RolesService.DatoInvalidoException.class, () -> servicio.asignar("x",
                List.of(new RolesService.Cambio(c[0], "medico"), new RolesService.Cambio("uid-fantasma", "medico"))));
        assertThat(new FirebaseGestorDeRoles().buscar(c[0]).get().rol()).isEqualTo("paciente");
    }

    @Test
    void elVerificadorLeeElRolDelTokenReal() throws Exception {
        String correo = "ver-" + System.nanoTime() + "@prueba.mx";
        String uid = registrar(correo)[0];
        new FirebaseGestorDeRoles().asignar(uid, "medico");
        // verifyIdToken con el emulador acepta tokens sin firma real y devuelve los claims.
        var identidad = new FirebaseVerificadorToken().verificar(iniciarSesion(correo));
        assertThat(identidad).isPresent();
        assertThat(identidad.get().uid()).isEqualTo(uid);
        assertThat(identidad.get().esMedico()).isTrue();
    }
}
