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

    public Usuario() {
    } // requerido por Firestore

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
}
