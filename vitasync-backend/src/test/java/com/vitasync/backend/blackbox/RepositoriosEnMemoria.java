package com.vitasync.backend.blackbox;

import com.vitasync.backend.smartwatch.dto.MetricasDTO;
import com.vitasync.backend.smartwatch.model.Dispositivo;
import com.vitasync.backend.smartwatch.repository.DispositivoRepository;
import com.vitasync.backend.smartwatch.repository.HistorialMetricasRepository;
import com.vitasync.backend.usuarios.model.Usuario;
import com.vitasync.backend.usuarios.repository.UsuarioRepository;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;

/**
 * Sustitutos en memoria de los repositorios de Firestore, SOLO para las
 * pruebas de caja negra (Práctica 8): permiten ejecutar el backend real
 * (controladores y servicios reales) sin tocar la nube del proyecto.
 *
 * Igual que Firestore, entregan y guardan COPIAS: un objeto modificado en el
 * servicio no cambia en la "base de datos" hasta que se llama a guardar.
 */
public final class RepositoriosEnMemoria {

    private RepositoriosEnMemoria() {
    }

    public static class Usuarios extends UsuarioRepository {
        private final Map<String, Usuario> datos = new ConcurrentHashMap<>();

        public Usuarios() {
            super(null);
        }

        @Override
        public void guardar(Usuario u) {
            datos.put(u.getId(), copiar(u));
        }

        @Override
        public Usuario buscarPorId(String id) {
            Usuario u = datos.get(id);
            return u == null ? null : copiar(u);
        }

        @Override
        public List<Usuario> listarTodos() {
            List<Usuario> lista = new ArrayList<>();
            datos.values().forEach(u -> lista.add(copiar(u)));
            lista.sort(Comparator.comparing(Usuario::getFechaCreacion));
            return lista;
        }

        @Override
        public void eliminar(String id) {
            datos.remove(id);
        }

        private static Usuario copiar(Usuario o) {
            Usuario u = new Usuario();
            u.setId(o.getId());
            u.setNombreCompleto(o.getNombreCompleto());
            u.setUsername(o.getUsername());
            u.setGrupos(o.getGrupos() == null ? null : new ArrayList<>(o.getGrupos()));
            u.setHabilitado(o.isHabilitado());
            u.setRequiereCambioPassword(o.isRequiereCambioPassword());
            u.setFechaCreacion(o.getFechaCreacion());
            u.setUltimoInicioSesion(o.getUltimoInicioSesion());
            u.setPinSalt(o.getPinSalt());
            u.setPinHash(o.getPinHash());
            u.setPinIntentosFallidos(o.getPinIntentosFallidos());
            u.setPinBloqueadoHasta(o.getPinBloqueadoHasta());
            u.setPropietarioUid(o.getPropietarioUid());
            return u;
        }
    }

    public static class Dispositivos extends DispositivoRepository {
        private final Map<String, Dispositivo> datos = new ConcurrentHashMap<>();

        public Dispositivos() {
            super(null);
        }

        @Override
        public void guardar(String usuarioId, Dispositivo d) {
            datos.put(usuarioId, copiar(d));
        }

        @Override
        public void eliminar(String usuarioId) {
            datos.remove(usuarioId);
        }

        @Override
        public Dispositivo buscarPorUsuario(String usuarioId) {
            Dispositivo d = datos.get(usuarioId);
            return d == null ? null : copiar(d);
        }

        private static Dispositivo copiar(Dispositivo o) {
            Dispositivo d = new Dispositivo();
            d.setId(o.getId());
            d.setUsuarioId(o.getUsuarioId());
            d.setNombre(o.getNombre());
            d.setModelo(o.getModelo());
            d.setBateria(o.getBateria());
            d.setFirmware(o.getFirmware());
            d.setEstado(o.getEstado());
            d.setUltimaSync(o.getUltimaSync());
            d.setClaveHash(o.getClaveHash());
            return d;
        }
    }

    /** Roles en memoria: el servidor de pruebas arranca con una administradora de prueba. */
    public static class Roles implements com.vitasync.backend.admin.GestorDeRoles {
        private final Map<String, Persona> personas = new java.util.concurrent.ConcurrentHashMap<>();

        public Roles() {
        }

        public Roles agregar(String uid, String correo, String rol) {
            personas.put(uid, new Persona(uid, correo, rol));
            return this;
        }

        @Override
        public java.util.List<Persona> listar() {
            return personas.values().stream().sorted(java.util.Comparator.comparing(Persona::uid)).toList();
        }

        @Override
        public java.util.Optional<Persona> buscar(String uid) {
            return java.util.Optional.ofNullable(personas.get(uid));
        }

        @Override
        public void asignar(String uid, String rol) {
            Persona p = personas.get(uid);
            personas.put(uid, new Persona(uid, p.correo(), rol));
        }
    }

    public static class Metas extends com.vitasync.backend.metas.MetasRepository {
        private final Map<String, com.vitasync.backend.metas.MetasCuentaDTO> datos = new ConcurrentHashMap<>();

        public Metas() {
            super(null);
        }

        @Override
        public java.util.Optional<com.vitasync.backend.metas.MetasCuentaDTO> obtener(String cuentaId) {
            return java.util.Optional.ofNullable(datos.get(cuentaId));
        }

        /** Atómico por cuenta (equivale a la transacción de Firestore). */
        @Override
        public synchronized com.vitasync.backend.metas.MetasCuentaDTO actualizar(String cuentaId, Long versionEsperada,
                java.util.function.UnaryOperator<com.vitasync.backend.metas.MetasCuentaDTO> cambio) {
            var actual = datos.getOrDefault(cuentaId, com.vitasync.backend.metas.MetasCuentaDTO.PREDETERMINADAS);
            if (versionEsperada != null && versionEsperada != actual.version()) {
                throw new com.vitasync.backend.metas.ConflictoDeVersionException(actual);
            }
            var nuevo = cambio.apply(actual).conVersion(actual.version() + 1);
            datos.put(cuentaId, nuevo);
            return nuevo;
        }

        @Override
        public void eliminar(String cuentaId) {
            datos.remove(cuentaId);
        }
    }

    public static class Contactos extends com.vitasync.backend.contactos.ContactoRepository {
        private final Map<String, List<com.vitasync.backend.contactos.ContactoDTO>> datos = new ConcurrentHashMap<>();

        public Contactos() {
            super(null);
        }

        @Override
        public List<com.vitasync.backend.contactos.ContactoDTO> listar(String cuentaId) {
            return new ArrayList<>(datos.getOrDefault(cuentaId, List.of()));
        }

        @Override
        public void guardar(String cuentaId, com.vitasync.backend.contactos.ContactoDTO c) {
            datos.computeIfAbsent(cuentaId, k -> new CopyOnWriteArrayList<>()).add(c);
        }

        @Override
        public boolean eliminar(String cuentaId, String contactoId) {
            List<com.vitasync.backend.contactos.ContactoDTO> lista = datos.get(cuentaId);
            return lista != null && lista.removeIf(c -> c.id().equals(contactoId));
        }

        @Override
        public void eliminarTodos(String cuentaId) {
            datos.remove(cuentaId);
        }
    }

    public static class Historial extends HistorialMetricasRepository {
        private final Map<String, List<MetricasDTO>> datos = new ConcurrentHashMap<>();

        public Historial() {
            super(null);
        }

        @Override
        public void guardar(String usuarioId, MetricasDTO m) {
            datos.computeIfAbsent(usuarioId, k -> new CopyOnWriteArrayList<>()).add(m);
        }

        @Override
        public void eliminarTodo(String usuarioId) {
            datos.remove(usuarioId);
        }

        @Override
        public List<MetricasDTO> ultimas(String usuarioId, int limite) {
            List<MetricasDTO> lista = new ArrayList<>(datos.getOrDefault(usuarioId, List.of()));
            lista.sort(Comparator.comparing(
                    (MetricasDTO m) -> m.timestamp() == null ? java.time.Instant.EPOCH : m.timestamp()).reversed());
            return lista.stream().limit(limite).toList();
        }
    }
}
