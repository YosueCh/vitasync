package com.vitasync.backend.smartwatch.service;

import com.vitasync.backend.smartwatch.dto.DispositivoDTO;
import com.vitasync.backend.smartwatch.dto.EstadoRespuestaDTO;
import com.vitasync.backend.smartwatch.dto.MetasDTO;
import com.vitasync.backend.smartwatch.dto.MetricasDTO;
import com.vitasync.backend.smartwatch.model.Dispositivo;
import com.vitasync.backend.smartwatch.repository.DispositivoRepository;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Random;
import java.util.concurrent.ConcurrentHashMap;

@Service
public class SmartwatchService {

    private final Optional<DispositivoRepository> repo;
    private final Random rnd = new Random();
    // Caché de la última lectura, una por usuario (no un solo dato global).
    private final Map<String, MetricasDTO> metricasPorUsuario = new ConcurrentHashMap<>();

    public SmartwatchService(Optional<DispositivoRepository> repo) {
        this.repo = repo;
    }

    /** false mientras no exista serviceAccountKey.json (ver FirebaseConfig). */
    public boolean isDisponible() {
        return repo.isPresent();
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
        repo.orElseThrow().guardar(usuarioId, d);
        return new EstadoRespuestaDTO("CONECTADO", toDTO(d), "Dispositivo conectado correctamente");
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

    /** Devuelve las últimas métricas del usuario dado (para GET /metrics). */
    public MetricasDTO metricas(String usuarioId) {
        return metricasPorUsuario.getOrDefault(usuarioId, generarMetricas());
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
