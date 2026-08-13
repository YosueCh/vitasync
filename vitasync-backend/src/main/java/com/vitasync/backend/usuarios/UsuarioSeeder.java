package com.vitasync.backend.usuarios;

import com.vitasync.backend.usuarios.dto.CrearUsuarioDTO;
import com.vitasync.backend.usuarios.service.UsuarioService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.CommandLineRunner;
import org.springframework.stereotype.Component;

import java.util.List;

/**
 * Siembra los tres usuarios de ejemplo que pide la Práctica 13
 * (dos del mismo nivel + un invitado), solo si Firebase está configurado
 * y la colección "usuarios" está vacía. Igual que SearchIndexSeeder,
 * evita duplicar en cada reinicio.
 */
@Component
public class UsuarioSeeder implements CommandLineRunner {

    private static final Logger log = LoggerFactory.getLogger(UsuarioSeeder.class);

    private final UsuarioService service;

    public UsuarioSeeder(UsuarioService service) {
        this.service = service;
    }

    @Override
    public void run(String... args) {
        if (!service.isDisponible()) {
            return; // sin Firebase configurado, no hay dónde sembrar
        }
        if (!service.listar().isEmpty()) {
            log.info("La colección de usuarios ya tiene datos, se omite la siembra.");
            return;
        }
        service.crear(new CrearUsuarioDTO("Alumno Uno", "alumno1", List.of("alumnos")));
        service.crear(new CrearUsuarioDTO("Alumno Dos", "alumno2", List.of("alumnos")));
        service.crear(new CrearUsuarioDTO("Invitado", "invitado", List.of("invitados")));
        log.info("Usuarios sembrados: alumno1, alumno2, invitado.");
    }
}
