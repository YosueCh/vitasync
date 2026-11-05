package com.vitasync.backend.metas;

/**
 * Cuerpo de PUT /api/metas. Dos modos según venga o no {@code version}:
 * <ul>
 *   <li>Con {@code version} (CONTROL DE VERSIÓN): solo se guarda si nadie cambió las metas desde que se
 *       leyeron; si otro dispositivo se adelantó, el servidor responde 409 con las metas actuales y no guarda.</li>
 *   <li>Sin {@code version} (FUSIÓN POR CAMPOS): se guardan solo los campos enviados y los demás conservan lo que
 *       tenga el servidor; si dos dispositivos cambian el mismo campo, gana el último en llegar.</li>
 * </ul>
 * Cualquier campo de meta puede ir vacío (null); debe venir al menos uno.
 */
public record ActualizarMetasDTO(Integer metaPasos, Integer metaCalorias, Double metaSueno, Long version, String dispositivo) {
}
