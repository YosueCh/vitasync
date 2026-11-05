package com.vitasync.backend.usuarios.model;

import java.util.List;

/**
 * POJO mapeado a un documento de la colección "usuarios" en Firestore.
 * Modela los mismos conceptos que la Práctica 13 (administración de
 * cuentas de un sistema operativo) pero como cuentas reales de VitaSync:
 * una cuenta puede estar habilitada o deshabilitada (se conserva su
 * información), y eliminarla es una operación distinta y más drástica.
 */
public class Usuario {
    private String id;
    private String nombreCompleto;
    private String username;
    private List<String> grupos;
    private boolean habilitado;
    private boolean requiereCambioPassword;
    private String fechaCreacion; // ISO-8601
    private String ultimoInicioSesion; // ISO-8601, null si nunca ha iniciado sesión

    // PIN de la vista móvil (Parcial 2). Nunca se guarda el PIN: solo un salt
    // aleatorio y SHA-256(salt:pin). Ninguno de estos campos sale en UsuarioDTO.
    private String pinSalt; // hex de 16 bytes aleatorios, null si no hay PIN
    private String pinHash; // hex de SHA-256("salt:pin"), null si no hay PIN
    private int pinIntentosFallidos;
    private String pinBloqueadoHasta; // ISO-8601, null si no está bloqueada

    // Práctica 10: UID de Firebase Authentication de la persona dueña de esta cuenta.
    // null = cuenta sin dueño (sembrada antes de activar la seguridad): solo un administrador la ve.
    private String propietarioUid;

    public Usuario() {
    } // requerido por Firestore

    public String getPropietarioUid() {
        return propietarioUid;
    }

    public void setPropietarioUid(String propietarioUid) {
        this.propietarioUid = propietarioUid;
    }

    public String getId() {
        return id;
    }

    public void setId(String id) {
        this.id = id;
    }

    public String getNombreCompleto() {
        return nombreCompleto;
    }

    public void setNombreCompleto(String nombreCompleto) {
        this.nombreCompleto = nombreCompleto;
    }

    public String getUsername() {
        return username;
    }

    public void setUsername(String username) {
        this.username = username;
    }

    public List<String> getGrupos() {
        return grupos;
    }

    public void setGrupos(List<String> grupos) {
        this.grupos = grupos;
    }

    public boolean isHabilitado() {
        return habilitado;
    }

    public void setHabilitado(boolean habilitado) {
        this.habilitado = habilitado;
    }

    public boolean isRequiereCambioPassword() {
        return requiereCambioPassword;
    }

    public void setRequiereCambioPassword(boolean requiereCambioPassword) {
        this.requiereCambioPassword = requiereCambioPassword;
    }

    public String getFechaCreacion() {
        return fechaCreacion;
    }

    public void setFechaCreacion(String fechaCreacion) {
        this.fechaCreacion = fechaCreacion;
    }

    public String getUltimoInicioSesion() {
        return ultimoInicioSesion;
    }

    public void setUltimoInicioSesion(String ultimoInicioSesion) {
        this.ultimoInicioSesion = ultimoInicioSesion;
    }

    public String getPinSalt() {
        return pinSalt;
    }

    public void setPinSalt(String pinSalt) {
        this.pinSalt = pinSalt;
    }

    public String getPinHash() {
        return pinHash;
    }

    public void setPinHash(String pinHash) {
        this.pinHash = pinHash;
    }

    public int getPinIntentosFallidos() {
        return pinIntentosFallidos;
    }

    public void setPinIntentosFallidos(int pinIntentosFallidos) {
        this.pinIntentosFallidos = pinIntentosFallidos;
    }

    public String getPinBloqueadoHasta() {
        return pinBloqueadoHasta;
    }

    public void setPinBloqueadoHasta(String pinBloqueadoHasta) {
        this.pinBloqueadoHasta = pinBloqueadoHasta;
    }
}
