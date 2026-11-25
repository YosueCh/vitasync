package com.vitasync.backend.practica12;

import com.vitasync.backend.chat.ChatService;
import org.junit.jupiter.api.Test;

import java.util.Arrays;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * PRÁCTICA 12 · Fase 1/2 · Riesgo de memoria: el chat guarda en el montón de Java hasta 2 MB de archivos y 500 mensajes por
 * conversación, y las conversaciones no se descartan hasta que se elimina la cuenta. Se mide el montón REAL (después de un
 * GC) con conversaciones llenas hasta el tope para ver cuánto crece con el número de pacientes.
 */
class MemoriaChatTest {

    private static long usadoMB() {
        for (int i = 0; i < 4; i++) {
            System.gc();
            try { Thread.sleep(100); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
        }
        Runtime r = Runtime.getRuntime();
        return (r.totalMemory() - r.freeMemory()) / (1024 * 1024);
    }

    @Test
    void conversacionesLlenasHastaElTope_ocupanMemoriaProporcionalAlNumeroDePacientes() {
        ChatService chat = new ChatService();
        byte[] texto = new byte[100 * 1024];
        Arrays.fill(texto, (byte) 'a');
        long base = usadoMB();
        long maxHeapMB = Runtime.getRuntime().maxMemory() / (1024 * 1024);
        System.out.println("P12|MEM|montón máximo de la JVM (MB)|" + maxHeapMB);
        System.out.println("P12|MEM|montón usado al empezar (MB)|" + base);

        int conversaciones = 0;
        long ultimo = base;
        for (int paciente = 1; paciente <= 60; paciente++) {
            String id = "paciente" + paciente;
            for (int a = 0; a < ChatService.MAX_ARCHIVOS; a++) {
                chat.enviarArchivo(id, "PACIENTE", "estudio" + a + ".txt", "text/plain", texto);
            }
            for (int m = 0; m < 200; m++) chat.enviar(id, "MEDICO", "mensaje de prueba " + m);
            conversaciones++;
            if (paciente == 1 || paciente == 10 || paciente == 30 || paciente == 60) {
                ultimo = usadoMB();
                System.out.println("P12|MEM|" + paciente + " conversaciones llenas → montón usado (MB)|" + ultimo
                        + " (+" + (ultimo - base) + " MB; ≈" + ((ultimo - base) * 10 / paciente) / 10.0 + " MB por paciente)");
            }
        }
        assertThat(conversaciones).isEqualTo(60);
        assertThat(ultimo - base).as("la memoria crece con el número de conversaciones: no hay tope global").isGreaterThan(60);
    }
}
