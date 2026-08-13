package com.vitasync.backend.cast.model;

/**
 * POJO mapeado a un documento de la colección "tv_sessions" en Firestore.
 * Modela el emparejamiento entre el dashboard (emisor) y una Smart TV
 * (Práctica 9-10): un código corto que la TV debe ingresar para
 * confirmar el enlace, con expiración para no dejar códigos abiertos
 * indefinidamente.
 */
public class CastSession {
    private String codigo; // también es el id del documento
    private String estado; // ESPERANDO_TV | EMPAREJADO | EXPIRADO
    private String creadoEn; // ISO-8601
    private String expiraEn; // ISO-8601
    private String emparejadoEn; // ISO-8601, null hasta que la TV confirma

    public CastSession() {
    } // requerido por Firestore

    public String getCodigo() {
        return codigo;
    }

    public void setCodigo(String codigo) {
        this.codigo = codigo;
    }

    public String getEstado() {
        return estado;
    }

    public void setEstado(String estado) {
        this.estado = estado;
    }

    public String getCreadoEn() {
        return creadoEn;
    }

    public void setCreadoEn(String creadoEn) {
        this.creadoEn = creadoEn;
    }

    public String getExpiraEn() {
        return expiraEn;
    }

    public void setExpiraEn(String expiraEn) {
        this.expiraEn = expiraEn;
    }

    public String getEmparejadoEn() {
        return emparejadoEn;
    }

    public void setEmparejadoEn(String emparejadoEn) {
        this.emparejadoEn = emparejadoEn;
    }
}
