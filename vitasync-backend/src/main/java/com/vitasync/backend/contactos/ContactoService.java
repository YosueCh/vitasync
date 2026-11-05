package com.vitasync.backend.contactos;

import com.vitasync.backend.usuarios.service.LimpiezaDeCuenta;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.regex.Pattern;

/**
 * Contactos de emergencia (Actividad 1 integrada en VitaSync): capturar, guardar en la nube y consultar.
 * Todas las reglas se validan AQUÍ, en el servidor, aunque la app ya las revise:
 * nombre de 2 a 60 caracteres; teléfono de 7 a 15 dígitos (puede llevar «+», espacios, guiones y paréntesis, que
 * se quitan al guardar); relación opcional de hasta 30 caracteres; máximo {@value #MAX_POR_CUENTA} contactos
 * por cuenta y sin teléfonos repetidos en la misma cuenta.
 */
@Service
public class ContactoService implements LimpiezaDeCuenta {

    public static final int MAX_POR_CUENTA = 5;
    private static final Pattern TELEFONO_VALIDO = Pattern.compile("^\\+?[0-9]{7,15}$");
    private static final Pattern SEPARADORES = Pattern.compile("[\\s().-]");

    private final Optional<ContactoRepository> repo;

    public ContactoService(Optional<ContactoRepository> repo) {
        this.repo = repo;
    }

    /** false mientras no exista serviceAccountKey.json (ver FirebaseConfig). */
    public boolean isDisponible() {
        return repo.isPresent();
    }

    public List<ContactoDTO> listar(String cuentaId) {
        return repo.orElseThrow().listar(cuentaId);
    }

    public ContactoDTO crear(String cuentaId, CrearContactoDTO datos) {
        String nombre = datos == null || datos.nombre() == null ? "" : datos.nombre().trim();
        String telefono = datos == null || datos.telefono() == null ? "" : SEPARADORES.matcher(datos.telefono()).replaceAll("");
        String relacion = datos == null || datos.relacion() == null || datos.relacion().isBlank() ? "Otro" : datos.relacion().trim();
        if (nombre.length() < 2 || nombre.length() > 60) {
            throw new DatoInvalidoException("El nombre es obligatorio (2 a 60 caracteres).");
        }
        if (!TELEFONO_VALIDO.matcher(telefono).matches()) {
            throw new DatoInvalidoException("El teléfono debe tener de 7 a 15 dígitos (puede empezar con +).");
        }
        if (relacion.length() > 30) {
            throw new DatoInvalidoException("La relación no puede pasar de 30 caracteres.");
        }
        List<ContactoDTO> actuales = repo.orElseThrow().listar(cuentaId);
        if (actuales.size() >= MAX_POR_CUENTA) {
            throw new ConflictoException("Solo se pueden guardar " + MAX_POR_CUENTA
                    + " contactos de emergencia. Elimina uno para agregar otro.");
        }
        final String telefonoFinal = telefono;
        if (actuales.stream().anyMatch(c -> telefonoFinal.equals(c.telefono()))) {
            throw new ConflictoException("Ya hay un contacto con ese teléfono.");
        }
        ContactoDTO nuevo = new ContactoDTO(UUID.randomUUID().toString(), nombre, telefono, relacion);
        repo.orElseThrow().guardar(cuentaId, nuevo);
        return nuevo;
    }

    public void eliminar(String cuentaId, String contactoId) {
        if (!repo.orElseThrow().eliminar(cuentaId, contactoId)) {
            throw new ContactoNoEncontradoException(contactoId);
        }
    }

    /** Al eliminar la cuenta desaparecen también sus contactos. */
    @Override
    public void borrarDatosDe(String usuarioId) {
        repo.ifPresent(r -> r.eliminarTodos(usuarioId));
    }

    /** Datos que no cumplen las reglas (400). */
    public static class DatoInvalidoException extends RuntimeException {
        public DatoInvalidoException(String mensaje) {
            super(mensaje);
        }
    }

    /** Teléfono repetido o límite de contactos alcanzado (409). */
    public static class ConflictoException extends RuntimeException {
        public ConflictoException(String mensaje) {
            super(mensaje);
        }
    }

    /** El contacto no existe en esa cuenta (404). */
    public static class ContactoNoEncontradoException extends RuntimeException {
        public ContactoNoEncontradoException(String id) {
            super("No existe un contacto con id " + id);
        }
    }
}
