package com.vitasync.backend.usuarios.service;

/**
 * Lo que cada parte del sistema que guarda datos de una cuenta (reloj, lecturas, chat, órdenes de firmware)
 * borra cuando la cuenta se elimina. Corrige el defecto D-04 de la Práctica 8: antes quedaban huérfanos el
 * reloj vinculado, el historial y la conversación.
 */
public interface LimpiezaDeCuenta {
    void borrarDatosDe(String usuarioId);
}
