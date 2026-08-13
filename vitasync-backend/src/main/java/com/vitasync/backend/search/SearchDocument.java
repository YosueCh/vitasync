package com.vitasync.backend.search;

import org.springframework.data.annotation.Id;
import org.springframework.data.elasticsearch.annotations.Document;
import org.springframework.data.elasticsearch.annotations.Field;
import org.springframework.data.elasticsearch.annotations.FieldType;

/**
 * Documento indexado en Elasticsearch (indice "vitasync-content").
 * Refleja 1:1 la interfaz DocumentoBuscable de src/app/core/search-index.ts
 * en el frontend, para que ambos lados de la busqueda hablen el mismo idioma.
 */
@Document(indexName = "vitasync-content")
public class SearchDocument {

    @Id
    private String id;

    @Field(type = FieldType.Text, analyzer = "spanish")
    private String titulo;

    @Field(type = FieldType.Text, analyzer = "spanish")
    private String contenido;

    @Field(type = FieldType.Keyword)
    private String ruta;

    @Field(type = FieldType.Keyword)
    private String fragmento;

    @Field(type = FieldType.Keyword)
    private String categoria;

    public SearchDocument() {
    }

    public SearchDocument(String id, String titulo, String contenido, String ruta, String fragmento, String categoria) {
        this.id = id;
        this.titulo = titulo;
        this.contenido = contenido;
        this.ruta = ruta;
        this.fragmento = fragmento;
        this.categoria = categoria;
    }

    public String getId() {
        return id;
    }

    public void setId(String id) {
        this.id = id;
    }

    public String getTitulo() {
        return titulo;
    }

    public void setTitulo(String titulo) {
        this.titulo = titulo;
    }

    public String getContenido() {
        return contenido;
    }

    public void setContenido(String contenido) {
        this.contenido = contenido;
    }

    public String getRuta() {
        return ruta;
    }

    public void setRuta(String ruta) {
        this.ruta = ruta;
    }

    public String getFragmento() {
        return fragmento;
    }

    public void setFragmento(String fragmento) {
        this.fragmento = fragmento;
    }

    public String getCategoria() {
        return categoria;
    }

    public void setCategoria(String categoria) {
        this.categoria = categoria;
    }
}
