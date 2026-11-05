package com.vitasync.backend.seguridad;

import com.vitasync.backend.smartwatch.service.SmartwatchService;
import com.vitasync.backend.usuarios.service.UsuarioService;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Optional;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Control de acceso del backend (Práctica 10, defecto D-03 de la Práctica 8).
 *
 * Autenticación: toda petición a /api/usuarios, /api/smartwatch, /api/chat y /api/firmware debe traer
 * «Authorization: Bearer &lt;token&gt;» válido; si no, 401.
 * Autorización: la cuenta que se toca ({id} en la ruta o ?usuarioId=) debe ser de quien pide, o éste debe ser
 * administrador; el chat también admite al rol «medico». Si no, 403 (se responde igual cuando la cuenta
 * no existe, para no revelar qué cuentas hay).
 *
 * Dispositivo: el firmware no es una persona. Sus tres llamadas (sync, orden y aplicar) se autentican con la
 * clave del dispositivo en la cabecera «X-Clave-Dispositivo» (la entrega /api/smartwatch/connect una sola vez);
 * una clave mala es 401 y solo vale para la cuenta a la que pertenece el dispositivo.
 *
 * Se activa con vitasync.seguridad.activa=true.
 */
@Component
@ConditionalOnProperty(name = "vitasync.seguridad.activa", havingValue = "true")
public class ControlDeAcceso extends OncePerRequestFilter {

    /** Atributo de la petición con la {@link Identidad} verificada, para los controladores. */
    public static final String ATRIBUTO = "vitasync.identidad";

    /** Cabecera con la que el firmware presenta la clave de su dispositivo. */
    public static final String CABECERA_DISPOSITIVO = "X-Clave-Dispositivo";

    private static final Pattern RUTA_USUARIO = Pattern.compile("^/api/usuarios/([^/]+)(/.*)?$");
    private static final Pattern RUTA_CHAT = Pattern.compile("^/api/chat/([^/]+)(/.*)?$");

    private final VerificadorToken verificador;
    private final UsuarioService usuarios;
    private final SmartwatchService smartwatch;

    public ControlDeAcceso(VerificadorToken verificador, UsuarioService usuarios, SmartwatchService smartwatch) {
        this.verificador = verificador;
        this.usuarios = usuarios;
        this.smartwatch = smartwatch;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest req) {
        String ruta = req.getRequestURI();
        boolean protegida = ruta.startsWith("/api/usuarios") || ruta.startsWith("/api/smartwatch")
                || ruta.startsWith("/api/chat") || ruta.startsWith("/api/firmware") || ruta.startsWith("/api/contactos")
                || ruta.startsWith("/api/metas");
        boolean publica = "GET".equals(req.getMethod()) && "/api/firmware/ultima".equals(ruta);
        return !protegida || publica || "OPTIONS".equals(req.getMethod());
    }

    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain cadena)
            throws ServletException, IOException {
        String claveDispositivo = req.getHeader(CABECERA_DISPOSITIVO);
        if (claveDispositivo != null && esLlamadaDeDispositivo(req)) {
            if (smartwatch.claveValida(req.getParameter("usuarioId"), claveDispositivo)) {
                cadena.doFilter(req, res);
            } else {
                error(res, HttpServletResponse.SC_UNAUTHORIZED, "Clave de dispositivo inválida.");
            }
            return;
        }

        Optional<Identidad> quien = token(req).flatMap(verificador::verificar);
        if (quien.isEmpty()) {
            res.setHeader("WWW-Authenticate", "Bearer");
            error(res, HttpServletResponse.SC_UNAUTHORIZED, "Inicia sesión para continuar.");
            return;
        }
        Identidad id = quien.get();
        req.setAttribute(ATRIBUTO, id);

        String objetivo = cuentaObjetivo(req);
        if (objetivo != null && !id.esAdmin() && usuarios.isDisponible()) {
            boolean esDueno = usuarios.propietarioDe(objetivo).map(id.uid()::equals).orElse(false);
            // Un médico puede atender el chat de un paciente y fijarle metas; nada más (no administra cuentas).
            boolean medicoAutorizado = id.esMedico()
                    && (req.getRequestURI().startsWith("/api/chat/") || req.getRequestURI().startsWith("/api/metas"));
            if (!esDueno && !medicoAutorizado) {
                error(res, HttpServletResponse.SC_FORBIDDEN, "No tienes permiso para acceder a esta cuenta.");
                return;
            }
        }
        cadena.doFilter(req, res);
    }

    private static boolean esLlamadaDeDispositivo(HttpServletRequest req) {
        String ruta = req.getRequestURI();
        String metodo = req.getMethod();
        return ("POST".equals(metodo) && "/api/smartwatch/sync".equals(ruta))
                || ("GET".equals(metodo) && "/api/firmware/orden".equals(ruta))
                || ("POST".equals(metodo) && "/api/firmware/aplicar".equals(ruta));
    }

    private static Optional<String> token(HttpServletRequest req) {
        String h = req.getHeader("Authorization");
        if (h == null || !h.regionMatches(true, 0, "Bearer ", 0, 7) || h.length() <= 7) return Optional.empty();
        return Optional.of(h.substring(7).trim());
    }

    /** Id de la cuenta a la que se refiere la petición, o null si no apunta a una (p. ej. listar). */
    private static String cuentaObjetivo(HttpServletRequest req) {
        String ruta = req.getRequestURI();
        Matcher u = RUTA_USUARIO.matcher(ruta);
        if (u.matches()) return u.group(1);
        Matcher c = RUTA_CHAT.matcher(ruta);
        if (c.matches()) return c.group(1);
        return req.getParameter("usuarioId");
    }

    private static void error(HttpServletResponse res, int estado, String mensaje) throws IOException {
        res.setStatus(estado);
        res.setContentType("application/json");
        res.setCharacterEncoding(StandardCharsets.UTF_8.name());
        res.getWriter().write("{\"error\":\"" + mensaje + "\"}");
    }
}
