package com.vitasync.backend.smartwatch.model;

/**
 * POJO mapeado a un documento de la colección "devices" en Firestore.
 * Firestore usa el constructor vacío + getters/setters para (de)serializar,
 * por eso NO lleva anotaciones de persistencia.
 */
public class Dispositivo {
    private String id;
    private String usuarioId;
    private String nombre;
    private String modelo;
    private int bateria;
    private String firmware;
    private String estado;       // CONECTADO / DESCONECTADO
    private String ultimaSync;   // ISO-8601 (Firestore mapea String de forma nativa)

    // Práctica 10: el firmware se identifica con una clave propia del dispositivo (no con el token de una
    // persona). Solo se guarda SHA-256 de la clave; la clave en claro se entrega una vez, al conectar.
    private String claveHash;

    public Dispositivo() {
    } // requerido por Firestore

    public String getClaveHash() {
        return claveHash;
    }

    public void setClaveHash(String claveHash) {
        this.claveHash = claveHash;
    }

    public String getId() {
        return id;
    }

    public void setId(String id) {
        this.id = id;
    }

    public String getUsuarioId() {
        return usuarioId;
    }

    public void setUsuarioId(String usuarioId) {
        this.usuarioId = usuarioId;
    }

    public String getNombre() {
        return nombre;
    }

    public void setNombre(String nombre) {
        this.nombre = nombre;
    }

    public String getModelo() {
        return modelo;
    }

    public void setModelo(String modelo) {
        this.modelo = modelo;
    }

    public int getBateria() {
        return bateria;
    }

    public void setBateria(int bateria) {
        this.bateria = bateria;
    }

    public String getFirmware() {
        return firmware;
    }

    public void setFirmware(String firmware) {
        this.firmware = firmware;
    }

    public String getEstado() {
        return estado;
    }

    public void setEstado(String estado) {
        this.estado = estado;
    }

    public String getUltimaSync() {
        return ultimaSync;
    }

    public void setUltimaSync(String ultimaSync) {
        this.ultimaSync = ultimaSync;
    }
}
