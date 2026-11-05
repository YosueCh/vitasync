package com.vitasync.backend.metas;

/**
 * Metas de salud de una cuenta (pasos, calorías y horas de sueño por día). Es el dato que DOS teléfonos de la
 * misma cuenta pueden editar a la vez (Práctica 9 integrada en VitaSync), por eso lleva un número de
 * {@code version}: crece en cada cambio y sirve para detectar que otro dispositivo se adelantó.
 *
 * @param version 0 = nadie las ha editado todavía (valores predeterminados)
 * @param actualizadaPor etiqueta del dispositivo que hizo el último cambio
 */
public record MetasCuentaDTO(int metaPasos, int metaCalorias, double metaSueno, long version, String actualizadaPor) {

    public static final MetasCuentaDTO PREDETERMINADAS = new MetasCuentaDTO(10000, 600, 8.0, 0, "—");

    public MetasCuentaDTO conVersion(long nueva) {
        return new MetasCuentaDTO(metaPasos, metaCalorias, metaSueno, nueva, actualizadaPor);
    }
}
