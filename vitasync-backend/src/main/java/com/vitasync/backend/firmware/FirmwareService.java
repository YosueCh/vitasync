package com.vitasync.backend.firmware;

import com.vitasync.backend.smartwatch.model.Dispositivo;
import com.vitasync.backend.smartwatch.repository.DispositivoRepository;
import org.springframework.stereotype.Service;

import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Gestión de versiones de firmware (actualización "por aire", OTA).
 *
 * Flujo: la vista móvil o la web piden actualizar ({@link #solicitar}); el
 * firmware del dispositivo consulta periódicamente si hay una orden
 * ({@link #ordenPendiente}), la aplica y reporta la versión nueva
 * ({@link #aplicar}), que es la que se guarda en el dispositivo.
 */
@Service
public class FirmwareService implements com.vitasync.backend.usuarios.service.LimpiezaDeCuenta {

    static final FirmwareDTO ULTIMA = new FirmwareDTO(
            "v2.4.0",
            "Mejora la precisión del ritmo cardíaco y reduce el consumo de batería.");

    private final Optional<DispositivoRepository> repo;
    // Órdenes de actualización pendientes: usuarioId -> versión a instalar.
    private final Map<String, String> ordenes = new ConcurrentHashMap<>();

    public FirmwareService(Optional<DispositivoRepository> repo) {
        this.repo = repo;
    }

    /** Al eliminar la cuenta se descarta su orden de actualización pendiente. */
    @Override
    public void borrarDatosDe(String usuarioId) {
        ordenes.remove(usuarioId);
    }

    public boolean isDisponible() {
        return repo.isPresent();
    }

    public FirmwareDTO ultima() {
        return ULTIMA;
    }

    public EstadoFirmwareDTO estado(String usuarioId) {
        Dispositivo d = repo.orElseThrow().buscarPorUsuario(usuarioId);
        String actual = d == null ? null : d.getFirmware();
        boolean hay = actual != null && !actual.equals(ULTIMA.version());
        return new EstadoFirmwareDTO(actual, ULTIMA, hay, ordenes.containsKey(usuarioId));
    }

    /** Registra la orden de actualizar. Solo si hay dispositivo y una versión nueva. */
    public EstadoFirmwareDTO solicitar(String usuarioId) {
        EstadoFirmwareDTO actual = estado(usuarioId);
        if (actual.hayActualizacion()) {
            ordenes.put(usuarioId, ULTIMA.version());
        }
        return estado(usuarioId);
    }

    /** Lo consulta el firmware: versión a instalar, o vacío si no hay orden. */
    public Optional<String> ordenPendiente(String usuarioId) {
        return Optional.ofNullable(ordenes.get(usuarioId));
    }

    /** El firmware reporta que ya instaló la versión; se guarda y se limpia la orden. */
    public EstadoFirmwareDTO aplicar(String usuarioId, String version) {
        Dispositivo d = repo.orElseThrow().buscarPorUsuario(usuarioId);
        if (d != null) {
            d.setFirmware(version);
            repo.orElseThrow().guardar(usuarioId, d);
        }
        ordenes.remove(usuarioId);
        return estado(usuarioId);
    }
}
