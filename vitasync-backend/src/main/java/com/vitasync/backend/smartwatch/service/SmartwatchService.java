package com.vitasync.backend.smartwatch.service;

import com.vitasync.backend.smartwatch.dto.DispositivoDTO;
import com.vitasync.backend.smartwatch.dto.EstadoRespuestaDTO;
import com.vitasync.backend.smartwatch.dto.MetasDTO;
import com.vitasync.backend.smartwatch.dto.MetricasDTO;
import com.vitasync.backend.smartwatch.model.Dispositivo;
import com.vitasync.backend.smartwatch.repository.DispositivoRepository;
import com.vitasync.backend.smartwatch.repository.HistorialMetricasRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Random;
import java.util.concurrent.ConcurrentHashMap;

@Service
public class SmartwatchService implements com.vitasync.backend.usuarios.service.LimpiezaDeCuenta {

    private static final Logger log = LoggerFactory.getLogger(SmartwatchService.class);
    static final int LIMITE_MAXIMO_HISTORIAL = 200;

    private final Optional<DispositivoRepository> repo;
    // Historial de lecturas en la base de datos (Firestore). Vacío si no hay Firebase.
    private final Optional<HistorialMetricasRepository> historial;
    private final Random rnd = new Random();
    // Caché de la última lectura, una por usuario (no un solo dato global).
    private final Map<String, MetricasDTO> metricasPorUsuario = new ConcurrentHashMap<>();

    // PRÁCTICA 12 (PER-11): caché del historial de lecturas. Las apps consultan el mismo historial una y otra vez
    // (sondeo de la pantalla, varias cards) y cada consulta cuesta una ida y vuelta a Firestore (≈90 ms y N lecturas
    // facturadas). La caché guarda el resultado unos segundos y se INVALIDA al guardar una lectura nueva o borrar la
    // cuenta, así que el usuario nunca ve un historial que ya se sabe viejo desde este servidor.
    static final int MAX_ENTRADAS_CACHE = 500;
    private final long vigenciaCacheMs;
    private record EntradaHistorial(List<MetricasDTO> datos, long expiraEnMs) {}
    private final Map<String, EntradaHistorial> cacheHistorial = new ConcurrentHashMap<>();
    // Se incrementa en cada invalidación: una consulta que empezó ANTES de una escritura no puede guardar su resultado viejo.
    private final java.util.concurrent.atomic.AtomicLong generacion = new java.util.concurrent.atomic.AtomicLong();

    /**
     * @param vigenciaCacheMs milisegundos que se reutiliza una consulta del historial; 0 apaga la caché
     *                        ({@code vitasync.cache-historial.vigencia-ms}, por omisión 5000).
     */
    @Autowired
    public SmartwatchService(Optional<DispositivoRepository> repo,
                             Optional<HistorialMetricasRepository> historial,
                             @org.springframework.beans.factory.annotation.Value("${vitasync.cache-historial.vigencia-ms:5000}") long vigenciaCacheMs) {
        this.repo = repo;
        this.historial = historial;
        this.vigenciaCacheMs = Math.max(0, vigenciaCacheMs);
    }

    /** Sin caché (comportamiento anterior a la Práctica 12). */
    public SmartwatchService(Optional<DispositivoRepository> repo,
                             Optional<HistorialMetricasRepository> historial) {
        this(repo, historial, 0);
    }

    /** Sin historial en base de datos (solo la última lectura en memoria). */
    public SmartwatchService(Optional<DispositivoRepository> repo) {
        this(repo, Optional.empty());
    }

    /** false mientras no exista serviceAccountKey.json (ver FirebaseConfig). */
    public boolean isDisponible() {
        return repo.isPresent();
    }

    /** Al eliminar la cuenta: se borran el reloj vinculado, su historial y la última lectura en memoria. */
    @Override
    public void borrarDatosDe(String usuarioId) {
        metricasPorUsuario.remove(usuarioId);
        invalidarCacheDe(usuarioId);
        repo.ifPresent(r -> r.eliminar(usuarioId));
        historial.ifPresent(h -> h.eliminarTodo(usuarioId));
    }

    /** Empareja y persiste el dispositivo del usuario dado en Firestore. */
    public EstadoRespuestaDTO conectar(String usuarioId) {
        Dispositivo d = new Dispositivo();
        d.setId("WATCH-" + usuarioId);
        d.setUsuarioId(usuarioId);
        d.setNombre("VitaSync Watch R1");
        d.setModelo("Wearable redondo genérico");
        d.setBateria(87);
        d.setFirmware("v2.3.1");
        d.setEstado("CONECTADO");
        d.setUltimaSync(null);
        String clave = nuevaClave();
        d.setClaveHash(hash(clave));
        repo.orElseThrow().guardar(usuarioId, d);
        return new EstadoRespuestaDTO("CONECTADO", toDTO(d), "Dispositivo conectado correctamente", clave);
    }

    /**
     * ¿La clave que manda el firmware es la del dispositivo de esa cuenta? (Práctica 10). Compara en tiempo
     * constante; una cuenta sin dispositivo o un dispositivo creado antes de existir las claves nunca valida.
     */
    public boolean claveValida(String usuarioId, String clave) {
        if (usuarioId == null || clave == null || clave.isBlank() || repo.isEmpty()) return false;
        Dispositivo d = repo.get().buscarPorUsuario(usuarioId);
        if (d == null || d.getClaveHash() == null) return false;
        return java.security.MessageDigest.isEqual(
                d.getClaveHash().getBytes(java.nio.charset.StandardCharsets.UTF_8),
                hash(clave).getBytes(java.nio.charset.StandardCharsets.UTF_8));
    }

    private static String nuevaClave() {
        byte[] b = new byte[24];
        new java.security.SecureRandom().nextBytes(b);
        return java.util.HexFormat.of().formatHex(b);
    }

    private static String hash(String clave) {
        try {
            byte[] h = java.security.MessageDigest.getInstance("SHA-256")
                    .digest(clave.getBytes(java.nio.charset.StandardCharsets.UTF_8));
            return java.util.HexFormat.of().formatHex(h);
        } catch (java.security.NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    /** Consulta el estado del dispositivo conectado del usuario dado. */
    public EstadoRespuestaDTO estado(String usuarioId) {
        Dispositivo d = repo.orElseThrow().buscarPorUsuario(usuarioId);
        if (d == null || !"CONECTADO".equals(d.getEstado())) {
            return new EstadoRespuestaDTO("DESCONECTADO", null, "Sin dispositivo conectado");
        }
        return new EstadoRespuestaDTO("CONECTADO", toDTO(d), "Dispositivo activo");
    }

    /**
     * Recibe las métricas del smartwatch de un usuario, las persiste y
     * devuelve las metas/notificaciones (comunicación bidireccional).
     */
    public MetasDTO sincronizar(String usuarioId, MetricasDTO entrada) {
        // El botón "Sincronizar" de la web manda un body vacío ({}) para pedir
        // una lectura nueva simulada; Jackson lo deserializa como un objeto
        // válido con todo en cero (NO como null), así que "entrada != null"
        // no basta para detectar "no se mandó una lectura real". Una lectura
        // real (del reloj) siempre trae timestamp; una petición vacía no.
        boolean sinLecturaReal = entrada == null || entrada.timestamp() == null;
        MetricasDTO m = sinLecturaReal ? generarMetricas() : entrada;
        metricasPorUsuario.put(usuarioId, m);
        guardarEnHistorial(usuarioId, m);

        Dispositivo d = repo.orElseThrow().buscarPorUsuario(usuarioId);
        if (d != null) {
            d.setBateria(m.bateria());
            d.setUltimaSync(Instant.now().toString());
            repo.orElseThrow().guardar(usuarioId, d);
        }

        return new MetasDTO(
                10000, 600, 8.0,
                List.of("¡Vas por buen camino!", "Recuerda hidratarte"),
                List.of("Mover a las 18:00", "Dormir antes de las 23:30")
        );
    }

    /**
     * Devuelve las últimas métricas del usuario dado (para GET /metrics): la
     * lectura en memoria o, si el servidor se reinició, la última guardada en
     * la base de datos. Si nunca hubo una devuelve vacío: ya NO se inventan valores de ejemplo (D-05 de la
     * Práctica 8); el controlador responde 204 y los clientes muestran «aún no hay lecturas».
     */
    public Optional<MetricasDTO> metricas(String usuarioId) {
        MetricasDTO enMemoria = metricasPorUsuario.get(usuarioId);
        if (enMemoria != null) {
            return Optional.of(enMemoria);
        }
        List<MetricasDTO> guardadas = consultarHistorial(usuarioId, 1);
        return guardadas.isEmpty() ? Optional.empty() : Optional.of(guardadas.get(0));
    }

    /**
     * Historial de lecturas del usuario (GET /historial), de la más reciente a
     * la más antigua. El límite se acota entre 1 y {@value #LIMITE_MAXIMO_HISTORIAL}.
     */
    public List<MetricasDTO> historial(String usuarioId, int limite) {
        int acotado = Math.max(1, Math.min(limite, LIMITE_MAXIMO_HISTORIAL));
        return consultarHistorial(usuarioId, acotado);
    }

    private List<MetricasDTO> consultarHistorial(String usuarioId, int limite) {
        if (historial.isEmpty()) return List.of();
        if (vigenciaCacheMs == 0) return historial.get().ultimas(usuarioId, limite);

        String clave = usuarioId + "|" + limite;
        long ahora = System.currentTimeMillis();
        EntradaHistorial guardada = cacheHistorial.get(clave);
        if (guardada != null && guardada.expiraEnMs() > ahora) return guardada.datos();

        long generacionAlEmpezar = generacion.get();
        List<MetricasDTO> datos = historial.get().ultimas(usuarioId, limite);
        if (generacion.get() == generacionAlEmpezar) {
            if (cacheHistorial.size() >= MAX_ENTRADAS_CACHE) cacheHistorial.clear(); // tope de memoria
            cacheHistorial.put(clave, new EntradaHistorial(datos, ahora + vigenciaCacheMs));
        }
        return datos;
    }

    private void invalidarCacheDe(String usuarioId) {
        generacion.incrementAndGet();
        String prefijo = usuarioId + "|";
        cacheHistorial.keySet().removeIf(k -> k.startsWith(prefijo));
    }

    /** Un fallo al guardar el historial no debe impedir la sincronización del reloj. */
    private void guardarEnHistorial(String usuarioId, MetricasDTO m) {
        historial.ifPresent(h -> {
            try {
                h.guardar(usuarioId, m);
            } catch (RuntimeException e) {
                log.warn("No se pudo guardar la lectura en el historial: {}", e.getMessage());
            } finally {
                invalidarCacheDe(usuarioId); // la lectura nueva debe verse en la siguiente consulta
            }
        });
    }

    private MetricasDTO generarMetricas() {
        return new MetricasDTO(
                4000 + rnd.nextInt(8000),
                250 + rnd.nextInt(550),
                Math.round((5 + rnd.nextDouble() * 4) * 10) / 10.0,
                62 + rnd.nextInt(33),
                40 + rnd.nextInt(55),
                Instant.now()
        );
    }

    private DispositivoDTO toDTO(Dispositivo d) {
        Instant ultima = (d.getUltimaSync() == null) ? null : Instant.parse(d.getUltimaSync());
        return new DispositivoDTO(d.getId(), d.getNombre(), d.getModelo(),
                d.getBateria(), d.getFirmware(), ultima);
    }
}
