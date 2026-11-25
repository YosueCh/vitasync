package com.vitasync.backend.automatizacion;

import com.vitasync.backend.blackbox.RepositoriosEnMemoria;
import com.vitasync.backend.metas.ActualizarMetasDTO;
import com.vitasync.backend.metas.ConflictoDeVersionException;
import com.vitasync.backend.metas.MetasCuentaDTO;
import com.vitasync.backend.metas.MetasService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * PRÁCTICAS 13 y 14 · AUT-03 · Pruebas UNITARIAS de la lógica de negocio del servicio de metas (MetasService): entrada válida,
 * vacía o nula, valores fuera de rango, resultado esperado y manejo de excepciones. Repositorio en memoria: solo se prueba la lógica.
 */
class Aut03MetasServicioUnitariasTest {

    private MetasService servicio;

    private static ActualizarMetasDTO cambio(Integer pasos, Integer calorias, Double sueno, Long version) {
        return new ActualizarMetasDTO(pasos, calorias, sueno, version, "Teléfono");
    }

    @BeforeEach
    void preparar() {
        servicio = new MetasService(Optional.of(new RepositoriosEnMemoria.Metas()));
    }

    // ---- entrada válida y resultado esperado ----

    @Test
    void entradaValida_guardaSoloLoEnviado_yConservaLoDemas() {
        MetasCuentaDTO r = servicio.actualizar("c1", cambio(8000, null, null, null), null);

        assertThat(r.metaPasos()).isEqualTo(8000);
        assertThat(r.metaCalorias()).isEqualTo(600); // lo que no se envió queda en el valor predeterminado
        assertThat(r.metaSueno()).isEqualTo(8.0);
        assertThat(r.version()).isEqualTo(1);
    }

    @Test
    void loslimites_incluidos_sonValidos() {
        assertThat(servicio.actualizar("c1", cambio(1000, 100, 4.0, null), null).metaPasos()).isEqualTo(1000);
        assertThat(servicio.actualizar("c1", cambio(50000, 5000, 12.0, null), null).metaPasos()).isEqualTo(50000);
    }

    @Test
    void elSuenoSeRedondeaAUnDecimal() {
        assertThat(servicio.actualizar("c1", cambio(null, null, 7.26, null), null).metaSueno()).isEqualTo(7.3);
    }

    @Test
    void quienLoHizo_loDecideElServidorSiHayRol_yLaEtiquetaSoloSinSesion() {
        assertThat(servicio.actualizar("c1", cambio(8000, null, null, null), "Médico").actualizadaPor()).isEqualTo("Médico");
        assertThat(servicio.actualizar("c2", cambio(8000, null, null, null), null).actualizadaPor()).isEqualTo("Teléfono");
        assertThat(servicio.actualizar("c3", new ActualizarMetasDTO(8000, null, null, null, "  "), null).actualizadaPor()).isEqualTo("Sin identificar");
    }

    // ---- entrada vacía o nula ----

    @Test
    void cuerpoNulo_seRechazaConMensajeClaro() {
        assertThatThrownBy(() -> servicio.actualizar("c1", null, null))
                .isInstanceOf(MetasService.DatoInvalidoException.class)
                .hasMessage("Indica al menos una meta para cambiar.");
    }

    @Test
    void sinNingunaMeta_seRechaza() {
        assertThatThrownBy(() -> servicio.actualizar("c1", cambio(null, null, null, 0L), null))
                .isInstanceOf(MetasService.DatoInvalidoException.class);
    }

    // ---- valores fuera de rango ----

    @ParameterizedTest
    @ValueSource(ints = {-1, 0, 999, 50001, Integer.MAX_VALUE})
    void pasosFueraDeRango_seRechazan(int pasos) {
        assertThatThrownBy(() -> servicio.actualizar("c1", cambio(pasos, null, null, null), null))
                .isInstanceOf(MetasService.DatoInvalidoException.class).hasMessageContaining("pasos");
    }

    @ParameterizedTest
    @ValueSource(ints = {-5, 99, 5001})
    void caloriasFueraDeRango_seRechazan(int calorias) {
        assertThatThrownBy(() -> servicio.actualizar("c1", cambio(null, calorias, null, null), null))
                .isInstanceOf(MetasService.DatoInvalidoException.class).hasMessageContaining("calorías");
    }

    @ParameterizedTest
    @ValueSource(doubles = {-1.0, 3.9, 12.1, Double.NaN, Double.POSITIVE_INFINITY})
    void suenoFueraDeRangoONoNumerico_seRechaza(double horas) {
        assertThatThrownBy(() -> servicio.actualizar("c1", cambio(null, null, horas, null), null))
                .isInstanceOf(MetasService.DatoInvalidoException.class).hasMessageContaining("sueño");
    }

    @Test
    void versionNegativa_seRechaza() {
        assertThatThrownBy(() -> servicio.actualizar("c1", cambio(8000, null, null, -1L), null))
                .isInstanceOf(MetasService.DatoInvalidoException.class).hasMessage("La versión no es válida.");
    }

    @Test
    void unDatoInvalido_noModificaNada() {
        servicio.actualizar("c1", cambio(8000, null, null, null), null);
        assertThatThrownBy(() -> servicio.actualizar("c1", cambio(5, 300, null, null), null)).isInstanceOf(MetasService.DatoInvalidoException.class);
        assertThat(servicio.obtener("c1").metaCalorias()).as("la meta válida del mismo cuerpo tampoco se aplicó").isEqualTo(600);
        assertThat(servicio.obtener("c1").version()).isEqualTo(1);
    }

    // ---- manejo de excepciones: control de versión ----

    @Test
    void versionEsperadaDistintaALaActual_lanzaConflictoConLasMetasActuales() {
        servicio.actualizar("c1", cambio(12000, null, null, 0L), "Médico");

        assertThatThrownBy(() -> servicio.actualizar("c1", cambio(7000, null, null, 0L), "Paciente"))
                .isInstanceOfSatisfying(ConflictoDeVersionException.class, e -> {
                    assertThat(e.getActual().metaPasos()).isEqualTo(12000);
                    assertThat(e.getActual().version()).isEqualTo(1);
                });
    }

    @Test
    void obtenerSinHaberEditadoNunca_devuelvePredeterminadasVersionCero() {
        assertThat(servicio.obtener("nueva")).isEqualTo(MetasCuentaDTO.PREDETERMINADAS);
    }

    @Test
    void sinFirebase_elServicioNoEstaDisponible() {
        assertThat(new MetasService(Optional.empty()).isDisponible()).isFalse();
    }
}
