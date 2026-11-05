package com.vitasync.backend.metas;

/** Otro dispositivo cambió las metas desde que este las leyó (409). Lleva las metas ACTUALES del servidor. */
public class ConflictoDeVersionException extends RuntimeException {

    private final MetasCuentaDTO actual;

    public ConflictoDeVersionException(MetasCuentaDTO actual) {
        super("Otro dispositivo cambió tus metas (versión " + actual.version() + ").");
        this.actual = actual;
    }

    public MetasCuentaDTO getActual() {
        return actual;
    }
}
