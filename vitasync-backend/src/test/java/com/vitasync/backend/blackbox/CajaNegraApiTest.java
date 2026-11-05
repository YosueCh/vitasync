package com.vitasync.backend.blackbox;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.MethodOrderer;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestMethodOrder;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;

/**
 * Pruebas de CAJA NEGRA de la API de VitaSync (Práctica 8).
 *
 * Cada caso se diseñó a partir de un REQUISITO (entradas, restricciones y
 * salida esperada), no del código: solo se envía una petición HTTP y se
 * observa la respuesta. El sistema probado es el backend real (controladores y
 * servicios reales) con repositorios en memoria en lugar de Firestore.
 *
 * Esto es una evaluación, no un seguro contra regresiones: cuando el sistema NO
 * cumple lo esperado, el caso se registra como FALLA (un defecto del producto)
 * y la prueba no rompe la compilación. Al terminar se escribe la evidencia en
 * {@code target/caja-negra/evidencia-api.txt} y el resumen en
 * {@code resultados-api.tsv}.
 */
// Estas pruebas de caja negra son sin sesión (como la Práctica 8); la seguridad se prueba aparte con tokens.
@SpringBootTest(classes = ServidorPruebas.class, properties = "vitasync.seguridad.activa=false")
@AutoConfigureMockMvc
@TestMethodOrder(MethodOrderer.MethodName.class)
class CajaNegraApiTest {

    private static final ObjectMapper JSON = new ObjectMapper();
    private static final List<String> EVIDENCIA = new ArrayList<>();
    private static final List<String[]> RESULTADOS = new ArrayList<>();

    @Autowired
    private MockMvc mvc;

    // ------------------------------------------------------------ utilidades

    private record Resp(int status, String cuerpo, String retryAfter) {
        JsonNode json() {
            try {
                return JSON.readTree(cuerpo);
            } catch (Exception e) {
                return JSON.createObjectNode();
            }
        }
    }

    private Resp http(String caso, MockHttpServletRequestBuilder peticion) throws Exception {
        MvcResult r = mvc.perform(peticion).andReturn();
        var rq = r.getRequest();
        var rs = r.getResponse();
        String url = rq.getRequestURI() + (rq.getQueryString() == null ? "" : "?" + rq.getQueryString());
        String cuerpoPeticion = rq.getContentAsString() == null ? "" : rq.getContentAsString();
        String cuerpo = rs.getContentAsString(StandardCharsets.UTF_8);
        EVIDENCIA.add("[" + caso + "] " + rq.getMethod() + " " + url
                + (cuerpoPeticion.isEmpty() ? "" : "\n    Cuerpo:    " + cuerpoPeticion)
                + "\n    Respuesta: " + rs.getStatus() + (cuerpo.isEmpty() ? "" : " " + cuerpo));
        return new Resp(rs.getStatus(), cuerpo, rs.getHeader("Retry-After"));
    }

    private static MockHttpServletRequestBuilder json(MockHttpServletRequestBuilder b, String cuerpo) {
        return b.contentType(MediaType.APPLICATION_JSON).content(cuerpo);
    }

    /** Registra el veredicto de un caso: PASA si lo observado coincide con lo esperado. */
    private static void veredicto(String caso, String requisito, String esperado, String obtenido, boolean cumple) {
        RESULTADOS.add(new String[]{caso, requisito, esperado, obtenido, cumple ? "PASA" : "FALLA"});
        EVIDENCIA.add("  => " + caso + " (" + requisito + "): " + (cumple ? "PASA" : "FALLA")
                + " | esperado: " + esperado + " | obtenido: " + obtenido + "\n");
    }

    private String crearCuenta(String caso, String nombre, String usuario) throws Exception {
        Resp r = http(caso, json(post("/api/usuarios"),
                "{\"nombreCompleto\":\"" + nombre + "\",\"username\":\"" + usuario + "\",\"grupos\":[\"alumnos\"]}"));
        return r.json().path("id").asText();
    }

    private static String unico(String base) {
        return base + "-" + UUID.randomUUID().toString().substring(0, 6);
    }

    // =================================================== Operaciones principales

    @Test
    void tc01_crearCuentaYListarla() throws Exception {
        String user = unico("pru");
        Resp alta = http("TC-01", json(post("/api/usuarios"),
                "{\"nombreCompleto\":\"Paciente Prueba\",\"username\":\"" + user + "\",\"grupos\":[\"alumnos\"]}"));
        String id = alta.json().path("id").asText();
        Resp lista = http("TC-01", get("/api/usuarios"));

        boolean ok = alta.status() == 200 && !id.isEmpty()
                && alta.json().path("habilitado").asBoolean()
                && lista.cuerpo().contains(id);
        veredicto("TC-01", "RF-01", "200, cuenta habilitada con id y presente en el listado",
                "estado " + alta.status() + ", habilitado=" + alta.json().path("habilitado") + ", en listado=" + lista.cuerpo().contains(id), ok);
    }

    @Test
    void tc02_registrarPinYEntrar() throws Exception {
        String id = crearCuenta("TC-02", "Ana PIN", unico("ana"));
        Resp reg = http("TC-02", json(post("/api/usuarios/" + id + "/pin"), "{\"pin\":\"1234\"}"));
        Resp cuenta = http("TC-02", get("/api/usuarios/" + id));
        Resp ok = http("TC-02", json(post("/api/usuarios/" + id + "/pin/verificar"), "{\"pin\":\"1234\"}"));
        Resp mal = http("TC-02", json(post("/api/usuarios/" + id + "/pin/verificar"), "{\"pin\":\"9999\"}"));

        boolean cumple = reg.status() == 200 && reg.json().path("exito").asBoolean()
                && cuenta.json().path("tienePin").asBoolean()
                && ok.json().path("exito").asBoolean()
                && !mal.json().path("exito").asBoolean();
        veredicto("TC-02", "RF-02", "PIN registrado; PIN correcto entra (exito=true) y PIN distinto no (exito=false)",
                "registro " + reg.status() + ", tienePin=" + cuenta.json().path("tienePin") + ", correcto=" + ok.json().path("exito")
                        + ", incorrecto=" + mal.json().path("exito") + " (" + mal.json().path("mensaje").asText() + ")", cumple);
    }

    @Test
    void tc03_sincronizarYConsultarLecturaDelReloj() throws Exception {
        String id = crearCuenta("TC-03", "Reloj Uno", unico("rel"));
        Resp con = http("TC-03", post("/api/smartwatch/connect?usuarioId=" + id));
        Resp sync = http("TC-03", json(post("/api/smartwatch/sync?usuarioId=" + id),
                "{\"pasos\":7777,\"calorias\":333,\"sueñoHoras\":7.5,\"frecuenciaCardiaca\":71,\"bateria\":80,\"timestamp\":\"2026-10-22T10:00:00Z\"}"));
        Resp m = http("TC-03", get("/api/smartwatch/metrics?usuarioId=" + id));

        boolean ok = con.status() == 200 && sync.status() == 200 && m.status() == 200
                && m.json().path("pasos").asInt() == 7777 && m.json().path("calorias").asInt() == 333;
        veredicto("TC-03", "RF-03", "La lectura enviada por el reloj es la que devuelve /metrics (pasos 7777, calorías 333)",
                "pasos=" + m.json().path("pasos") + ", calorías=" + m.json().path("calorias"), ok);
    }

    @Test
    void tc04_historialDeLecturas() throws Exception {
        String id = crearCuenta("TC-04", "Historial Uno", unico("his"));
        http("TC-04", post("/api/smartwatch/connect?usuarioId=" + id));
        for (int i = 1; i <= 3; i++) {
            http("TC-04", json(post("/api/smartwatch/sync?usuarioId=" + id),
                    "{\"pasos\":" + (i * 1000) + ",\"calorias\":" + (i * 10) + ",\"sueñoHoras\":7.0,\"frecuenciaCardiaca\":70,\"bateria\":80,"
                            + "\"timestamp\":\"2026-10-22T10:0" + i + ":00Z\"}"));
        }
        Resp h = http("TC-04", get("/api/smartwatch/historial?usuarioId=" + id + "&limite=30"));
        JsonNode lista = h.json();
        boolean ok = h.status() == 200 && lista.isArray() && lista.size() == 3
                && lista.get(0).path("pasos").asInt() == 3000 && lista.get(2).path("pasos").asInt() == 1000;
        veredicto("TC-04", "RF-04", "3 lecturas guardadas, la más reciente primero (3000, 2000, 1000)",
                "tamaño=" + lista.size() + ", primera=" + (lista.size() > 0 ? lista.get(0).path("pasos") : "-"), ok);
    }

    @Test
    void tc05_enviarYConsultarMensajesDelChat() throws Exception {
        String p = unico("pac");
        Resp a = http("TC-05", json(post("/api/chat/" + p + "/mensajes"), "{\"emisor\":\"MEDICO\",\"texto\":\"Buenos días, ¿cómo se siente?\"}"));
        Resp b = http("TC-05", json(post("/api/chat/" + p + "/mensajes"), "{\"emisor\":\"PACIENTE\",\"texto\":\"Mejor, gracias\"}"));
        Resp todos = http("TC-05", get("/api/chat/" + p + "/mensajes?desde=0"));
        Resp nuevos = http("TC-05", get("/api/chat/" + p + "/mensajes?desde=1"));

        JsonNode ms = todos.json().path("mensajes");
        boolean ok = a.status() == 200 && b.status() == 200 && ms.size() == 2
                && ms.get(0).path("emisor").asText().equals("MEDICO") && ms.get(1).path("emisor").asText().equals("PACIENTE")
                && !ms.get(0).path("hora").asText().isEmpty()
                && nuevos.json().path("mensajes").size() == 1;
        veredicto("TC-05", "RF-05", "2 mensajes en orden con emisor y hora; con desde=1 solo llega el segundo",
                "total=" + ms.size() + ", con desde=1: " + nuevos.json().path("mensajes").size(), ok);
    }

    @Test
    void tc06_deshabilitarYHabilitarCuenta() throws Exception {
        String id = crearCuenta("TC-06", "Cuenta Cambio", unico("cam"));
        Resp des = http("TC-06", patch("/api/usuarios/" + id + "/deshabilitar"));
        Resp enLista = http("TC-06", get("/api/usuarios/" + id));
        Resp hab = http("TC-06", patch("/api/usuarios/" + id + "/habilitar"));

        boolean ok = !des.json().path("habilitado").asBoolean() && !enLista.json().path("habilitado").asBoolean()
                && hab.json().path("habilitado").asBoolean();
        veredicto("TC-06", "RF-06", "Deshabilitar conserva la cuenta con habilitado=false y habilitar la revierte",
                "tras deshabilitar=" + enLista.json().path("habilitado") + ", tras habilitar=" + hab.json().path("habilitado"), ok);
    }

    @Test
    void tc07_eliminarCuentaYConsultarla() throws Exception {
        String id = crearCuenta("TC-07", "Cuenta Temporal", unico("tmp"));
        Resp del = http("TC-07", delete("/api/usuarios/" + id));
        Resp get = http("TC-07", get("/api/usuarios/" + id));
        Resp lista = http("TC-07", get("/api/usuarios"));

        boolean ok = del.status() == 200 && get.status() == 404 && !lista.cuerpo().contains(id);
        veredicto("TC-07", "RF-06", "Eliminar responde 200; la cuenta ya no se encuentra (404) ni aparece en el listado",
                "eliminar=" + del.status() + ", consultar=" + get.status() + ", en listado=" + lista.cuerpo().contains(id), ok);
    }

    @Test
    void tc08_actualizacionDeFirmwareOta() throws Exception {
        String id = crearCuenta("TC-08", "Firmware Uno", unico("fw"));
        http("TC-08", post("/api/smartwatch/connect?usuarioId=" + id));
        Resp antes = http("TC-08", get("/api/firmware/estado?usuarioId=" + id));
        http("TC-08", post("/api/firmware/solicitar?usuarioId=" + id));
        Resp orden = http("TC-08", get("/api/firmware/orden?usuarioId=" + id));
        Resp despues = http("TC-08", post("/api/firmware/aplicar?usuarioId=" + id + "&version=v2.4.0"));
        Resp sinOrden = http("TC-08", get("/api/firmware/orden?usuarioId=" + id));

        boolean ok = antes.json().path("hayActualizacion").asBoolean()
                && orden.json().path("pendiente").asBoolean()
                && !despues.json().path("hayActualizacion").asBoolean()
                && !sinOrden.json().path("pendiente").asBoolean();
        veredicto("TC-08", "RF-07", "Con firmware viejo hay actualización; tras solicitar hay orden; tras aplicar queda al día y sin orden",
                "antes=" + antes.json().path("hayActualizacion") + ", orden=" + orden.json().path("pendiente")
                        + ", después=" + despues.json().path("hayActualizacion") + ", orden final=" + sinOrden.json().path("pendiente"), ok);
    }

    // ================================================================ Validaciones

    @Test
    void tc09_pinInvalido() throws Exception {
        String id = crearCuenta("TC-09", "PIN Malo", unico("pm"));
        String[] malos = {"12", "12345", "abcd", "12a4", ""};
        List<String> obtenidos = new ArrayList<>();
        boolean ok = true;
        for (String pin : malos) {
            Resp r = http("TC-09", json(post("/api/usuarios/" + id + "/pin"), "{\"pin\":\"" + pin + "\"}"));
            obtenidos.add("'" + pin + "'→" + r.status());
            ok &= r.status() == 400;
        }
        Resp nulo = http("TC-09", json(post("/api/usuarios/" + id + "/pin"), "{}"));
        obtenidos.add("sin pin→" + nulo.status());
        ok &= nulo.status() == 400;
        veredicto("TC-09", "RV-01", "Todo PIN que no sean exactamente 4 dígitos se rechaza con 400",
                String.join(", ", obtenidos), ok);
    }

    @Test
    void tc10_mensajeDeChatVacioOLargo() throws Exception {
        String p = unico("pac");
        Resp vacio = http("TC-10", json(post("/api/chat/" + p + "/mensajes"), "{\"emisor\":\"MEDICO\",\"texto\":\"   \"}"));
        Resp largo = http("TC-10", json(post("/api/chat/" + p + "/mensajes"), "{\"emisor\":\"MEDICO\",\"texto\":\"" + "a".repeat(201) + "\"}"));
        Resp limite = http("TC-10", json(post("/api/chat/" + p + "/mensajes"), "{\"emisor\":\"MEDICO\",\"texto\":\"" + "a".repeat(200) + "\"}"));
        Resp emisor = http("TC-10", json(post("/api/chat/" + p + "/mensajes"), "{\"emisor\":\"ADMIN\",\"texto\":\"hola\"}"));
        Resp lista = http("TC-10", get("/api/chat/" + p + "/mensajes?desde=0"));

        boolean ok = vacio.status() == 400 && largo.status() == 400 && limite.status() == 200
                && emisor.status() == 400 && lista.json().path("mensajes").size() == 1;
        veredicto("TC-10", "RV-02", "Vacío, >200 caracteres y emisor desconocido → 400; exactamente 200 caracteres → 200; solo queda 1 mensaje",
                "vacío=" + vacio.status() + ", 201=" + largo.status() + ", 200=" + limite.status() + ", emisor ADMIN=" + emisor.status()
                        + ", guardados=" + lista.json().path("mensajes").size(), ok);
    }

    @Test
    void tc11_cuentaConDatosVacios() throws Exception {
        Resp r = http("TC-11", json(post("/api/usuarios"), "{\"nombreCompleto\":\"\",\"username\":\"\",\"grupos\":[]}"));
        Resp sinNada = http("TC-11", json(post("/api/usuarios"), "{}"));
        boolean ok = r.status() == 400 && sinNada.status() == 400;
        veredicto("TC-11", "RV-03", "Crear una cuenta sin nombre ni usuario se rechaza con 400",
                "nombre y usuario vacíos → " + r.status() + "; cuerpo {} → " + sinNada.status(), ok);
    }

    @Test
    void tc12_usuarioRepetido() throws Exception {
        String user = unico("dup");
        Resp a = http("TC-12", json(post("/api/usuarios"), "{\"nombreCompleto\":\"Uno\",\"username\":\"" + user + "\",\"grupos\":[]}"));
        Resp b = http("TC-12", json(post("/api/usuarios"), "{\"nombreCompleto\":\"Otro\",\"username\":\"" + user + "\",\"grupos\":[]}"));
        boolean ok = a.status() == 200 && (b.status() == 409 || b.status() == 400);
        veredicto("TC-12", "RV-03", "Un nombre de usuario repetido se rechaza (409/400)",
                "segundo alta con el mismo usuario → " + b.status(), ok);
    }

    @Test
    void tc13_identificadorDeChatInvalido() throws Exception {
        Resp espacio = http("TC-13", json(post("/api/chat/a%20b/mensajes"), "{\"emisor\":\"MEDICO\",\"texto\":\"hola\"}"));
        Resp ruta = http("TC-13", get("/api/chat/..%2Fx/mensajes?desde=0"));
        boolean ok = espacio.status() == 400 && (ruta.status() == 400 || ruta.status() == 404);
        veredicto("TC-13", "RV-02", "Un identificador de paciente con espacios o '../' se rechaza (400/404), nunca 500",
                "con espacio → " + espacio.status() + ", con ../ → " + ruta.status(), ok);
    }

    @Test
    void tc14_limiteDelHistorialFueraDeRango() throws Exception {
        String id = crearCuenta("TC-14", "Limites", unico("lim"));
        Resp cero = http("TC-14", get("/api/smartwatch/historial?usuarioId=" + id + "&limite=0"));
        Resp negativo = http("TC-14", get("/api/smartwatch/historial?usuarioId=" + id + "&limite=-5"));
        Resp enorme = http("TC-14", get("/api/smartwatch/historial?usuarioId=" + id + "&limite=99999"));
        Resp letras = http("TC-14", get("/api/smartwatch/historial?usuarioId=" + id + "&limite=abc"));
        boolean ok = cero.status() == 200 && negativo.status() == 200 && enorme.status() == 200 && letras.status() == 400;
        veredicto("TC-14", "RV-04", "Límites 0, negativo y enorme se acotan (200); un límite no numérico → 400; nunca 500",
                "0→" + cero.status() + ", -5→" + negativo.status() + ", 99999→" + enorme.status() + ", abc→" + letras.status(), ok);
    }

    // ====================================================== Persistencia / consistencia

    @Test
    void tc15_chatSeConservaHastaQueElPacienteLoCierra() throws Exception {
        String p = unico("pac");
        http("TC-15", json(post("/api/chat/" + p + "/mensajes"), "{\"emisor\":\"MEDICO\",\"texto\":\"uno\"}"));
        http("TC-15", json(post("/api/chat/" + p + "/mensajes"), "{\"emisor\":\"PACIENTE\",\"texto\":\"dos\"}"));
        Resp lee1 = http("TC-15", get("/api/chat/" + p + "/mensajes?desde=0"));
        Resp lee2 = http("TC-15", get("/api/chat/" + p + "/mensajes?desde=0"));
        Resp cierra = http("TC-15", post("/api/chat/" + p + "/cerrar"));
        Resp trasCerrar = http("TC-15", get("/api/chat/" + p + "/mensajes?desde=0"));
        Resp enviaCerrado = http("TC-15", json(post("/api/chat/" + p + "/mensajes"), "{\"emisor\":\"MEDICO\",\"texto\":\"¿sigue ahí?\"}"));
        http("TC-15", post("/api/chat/" + p + "/abrir"));
        Resp nuevo = http("TC-15", json(post("/api/chat/" + p + "/mensajes"), "{\"emisor\":\"PACIENTE\",\"texto\":\"chat nuevo\"}"));

        boolean ok = lee1.json().path("mensajes").size() == 2 && lee2.json().path("mensajes").size() == 2
                && cierra.status() == 200
                && trasCerrar.json().path("cerrado").asBoolean() && trasCerrar.json().path("mensajes").size() == 0
                && enviaCerrado.status() == 409
                && nuevo.status() == 200 && nuevo.json().path("id").asInt() == 3;
        veredicto("TC-15", "RP-01", "Los mensajes se conservan en cada consulta hasta que el paciente cierra; al cerrar se borran, no se acepta enviar (409) y al abrir de nuevo los ids continúan",
                "antes de cerrar=" + lee2.json().path("mensajes").size() + ", después=" + trasCerrar.json().path("mensajes").size()
                        + ", enviar cerrado=" + enviaCerrado.status() + ", id tras reabrir=" + nuevo.json().path("id"), ok);
    }

    @Test
    void tc16_laApiNoExponeElPin() throws Exception {
        String id = crearCuenta("TC-16", "Sin Exponer", unico("pin"));
        http("TC-16", json(post("/api/usuarios/" + id + "/pin"), "{\"pin\":\"4321\"}"));
        Resp lista = http("TC-16", get("/api/usuarios"));
        Resp una = http("TC-16", get("/api/usuarios/" + id));
        String todo = lista.cuerpo() + una.cuerpo();
        boolean ok = !todo.contains("pinHash") && !todo.contains("pinSalt") && !todo.contains("4321");
        veredicto("TC-16", "RP-02", "El PIN, su sal y su hash nunca salen en las respuestas de la API",
                "aparece pinHash/pinSalt/PIN: " + !ok, ok);
    }

    @Test
    void tc17_eliminarCuentaNoDejaDatosHuerfanos() throws Exception {
        String id = crearCuenta("TC-17", "Con Datos", unico("orf"));
        http("TC-17", post("/api/smartwatch/connect?usuarioId=" + id));
        http("TC-17", json(post("/api/chat/" + id + "/mensajes"), "{\"emisor\":\"MEDICO\",\"texto\":\"nota clínica\"}"));
        http("TC-17", delete("/api/usuarios/" + id));
        Resp reloj = http("TC-17", get("/api/smartwatch/status?usuarioId=" + id));
        Resp chat = http("TC-17", get("/api/chat/" + id + "/mensajes?desde=0"));

        boolean ok = !reloj.cuerpo().contains("\"estado\":\"CONECTADO\"") && chat.json().path("mensajes").size() == 0;
        veredicto("TC-17", "RP-03", "Al eliminar una cuenta se eliminan también su reloj vinculado y su chat",
                "reloj=" + (reloj.cuerpo().contains("\"estado\":\"CONECTADO\"") ? "sigue CONECTADO" : "eliminado")
                        + ", mensajes del chat=" + chat.json().path("mensajes").size(), ok);
    }

    // =========================================================== Roles y permisos

    @Test
    void tc18_cuentaDeshabilitadaNoEntra() throws Exception {
        String id = crearCuenta("TC-18", "Bloqueada", unico("dis"));
        http("TC-18", json(post("/api/usuarios/" + id + "/pin"), "{\"pin\":\"1111\"}"));
        http("TC-18", patch("/api/usuarios/" + id + "/deshabilitar"));
        Resp pin = http("TC-18", json(post("/api/usuarios/" + id + "/pin/verificar"), "{\"pin\":\"1111\"}"));
        Resp login = http("TC-18", post("/api/usuarios/" + id + "/login"));
        boolean ok = !pin.json().path("exito").asBoolean() && !login.json().path("exito").asBoolean();
        veredicto("TC-18", "RN-01", "Con la cuenta deshabilitada ni el PIN correcto ni el inicio de sesión dan acceso",
                "PIN correcto → exito=" + pin.json().path("exito") + ", login → exito=" + login.json().path("exito"), ok);
    }

    @Test
    void tc19_bloqueoTrasCincoPinIncorrectos() throws Exception {
        String id = crearCuenta("TC-19", "Fuerza Bruta", unico("blq"));
        http("TC-19", json(post("/api/usuarios/" + id + "/pin"), "{\"pin\":\"2222\"}"));
        List<Integer> estados = new ArrayList<>();
        Resp ultimo = null;
        for (int i = 0; i < 5; i++) {
            ultimo = http("TC-19", json(post("/api/usuarios/" + id + "/pin/verificar"), "{\"pin\":\"0000\"}"));
            estados.add(ultimo.status());
        }
        Resp correctoBloqueado = http("TC-19", json(post("/api/usuarios/" + id + "/pin/verificar"), "{\"pin\":\"2222\"}"));
        boolean ok = estados.subList(0, 4).stream().allMatch(s -> s == 200) && estados.get(4) == 429
                && ultimo.retryAfter() != null && correctoBloqueado.status() == 429;
        veredicto("TC-19", "RN-02", "Los primeros 4 fallos → 200 con intentos restantes; el 5.º → 429 con Retry-After; el PIN correcto también se rechaza (429) mientras dure el bloqueo",
                "estados=" + estados + ", Retry-After=" + (ultimo == null ? "-" : ultimo.retryAfter()) + ", PIN correcto bloqueado=" + correctoBloqueado.status(), ok);
    }

    @Test
    void tc20_datosAjenosSinAutenticacion() throws Exception {
        String victima = crearCuenta("TC-20", "Paciente Reservado", unico("vic"));
        http("TC-20", post("/api/smartwatch/connect?usuarioId=" + victima));
        http("TC-20", json(post("/api/smartwatch/sync?usuarioId=" + victima),
                "{\"pasos\":1234,\"calorias\":99,\"sueñoHoras\":6.0,\"frecuenciaCardiaca\":88,\"bateria\":70,\"timestamp\":\"2026-10-22T10:00:00Z\"}"));
        http("TC-20", json(post("/api/chat/" + victima + "/mensajes"), "{\"emisor\":\"MEDICO\",\"texto\":\"diagnóstico reservado\"}"));
        // un tercero, sin haber iniciado sesión ni haber verificado ningún PIN:
        Resp metricas = http("TC-20", get("/api/smartwatch/metrics?usuarioId=" + victima));
        Resp historial = http("TC-20", get("/api/smartwatch/historial?usuarioId=" + victima));
        Resp chat = http("TC-20", get("/api/chat/" + victima + "/mensajes?desde=0"));
        Resp lista = http("TC-20", get("/api/usuarios"));

        boolean protegido = metricas.status() == 401 || metricas.status() == 403;
        boolean protegidoChat = chat.status() == 401 || chat.status() == 403;
        veredicto("TC-20", "RN-03", "Sin sesión ni PIN, consultar métricas, historial, chat o la lista de cuentas de otra persona se rechaza (401/403)",
                "métricas=" + metricas.status() + ", historial=" + historial.status() + ", chat=" + chat.status() + ", cuentas=" + lista.status(),
                protegido && protegidoChat);
    }

    // ==================================================================== Errores

    @Test
    void tc21_recursosInexistentes() throws Exception {
        String fantasma = UUID.randomUUID().toString();
        Resp obtener = http("TC-21", get("/api/usuarios/" + fantasma));
        Resp habilitar = http("TC-21", patch("/api/usuarios/" + fantasma + "/habilitar"));
        Resp eliminar = http("TC-21", delete("/api/usuarios/" + fantasma));
        Resp pin = http("TC-21", json(post("/api/usuarios/" + fantasma + "/pin/verificar"), "{\"pin\":\"1234\"}"));
        boolean ok = obtener.status() == 404 && habilitar.status() == 404 && eliminar.status() == 404 && pin.status() == 404
                && obtener.json().path("error").asText().contains(fantasma);
        veredicto("TC-21", "RE-01", "Una cuenta inexistente responde 404 con un mensaje claro en cualquier operación, sin romper el servidor",
                "consultar=" + obtener.status() + ", habilitar=" + habilitar.status() + ", eliminar=" + eliminar.status() + ", PIN=" + pin.status(), ok);
    }

    @Test
    void tc22_cuerpoMalFormado() throws Exception {
        String id = crearCuenta("TC-22", "Cuerpo Roto", unico("rot"));
        Resp a = http("TC-22", json(post("/api/usuarios"), "{esto no es json"));
        Resp b = http("TC-22", json(post("/api/usuarios/" + id + "/pin"), "no-json"));
        Resp c = http("TC-22", json(post("/api/chat/" + unico("p") + "/mensajes"), "[]"));
        boolean ok = a.status() == 400 && b.status() == 400 && c.status() == 400;
        veredicto("TC-22", "RE-01", "Un cuerpo que no es JSON válido se rechaza con 400 (no con 500)",
                "usuarios=" + a.status() + ", pin=" + b.status() + ", chat=" + c.status(), ok);
    }

    @Test
    void tc23_pinYaRegistradoYPinSinRegistrar() throws Exception {
        String id = crearCuenta("TC-23", "Dos PIN", unico("dos"));
        Resp sinPin = http("TC-23", json(post("/api/usuarios/" + id + "/pin/verificar"), "{\"pin\":\"1234\"}"));
        http("TC-23", json(post("/api/usuarios/" + id + "/pin"), "{\"pin\":\"1234\"}"));
        Resp otraVez = http("TC-23", json(post("/api/usuarios/" + id + "/pin"), "{\"pin\":\"5678\"}"));
        Resp sigueIgual = http("TC-23", json(post("/api/usuarios/" + id + "/pin/verificar"), "{\"pin\":\"1234\"}"));
        boolean ok = sinPin.status() == 409 && otraVez.status() == 409 && sigueIgual.json().path("exito").asBoolean();
        veredicto("TC-23", "RE-01", "Verificar sin PIN → 409; registrar un segundo PIN → 409 y el original sigue vigente",
                "verificar sin PIN=" + sinPin.status() + ", segundo registro=" + otraVez.status() + ", PIN original vigente=" + sigueIgual.json().path("exito"), ok);
    }

    // =========================================================== Evidencia

    @AfterAll
    static void escribirEvidencia() throws Exception {
        Path dir = Path.of("target", "caja-negra");
        Files.createDirectories(dir);
        Files.writeString(dir.resolve("evidencia-api.txt"), String.join("\n", EVIDENCIA), StandardCharsets.UTF_8);
        StringBuilder tsv = new StringBuilder("caso\trequisito\tesperado\tobtenido\testado\n");
        RESULTADOS.stream().sorted((a, b) -> a[0].compareTo(b[0]))
                .forEach(r -> tsv.append(String.join("\t", r)).append('\n'));
        Files.writeString(dir.resolve("resultados-api.tsv"), tsv.toString(), StandardCharsets.UTF_8);
        assertThat(RESULTADOS).as("se ejecutaron los casos de caja negra").isNotEmpty();
    }
}
