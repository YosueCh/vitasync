package com.vitasync.backend.blackbox;

import com.vitasync.backend.chat.ChatController;
import com.vitasync.backend.chat.ChatService;
import com.vitasync.backend.config.CorsConfig;
import com.vitasync.backend.firmware.FirmwareController;
import com.vitasync.backend.firmware.FirmwareService;
import com.vitasync.backend.seguridad.ControlDeAcceso;
import com.vitasync.backend.seguridad.VerificadorToken;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import com.vitasync.backend.smartwatch.controller.SmartwatchController;
import com.vitasync.backend.smartwatch.repository.DispositivoRepository;
import com.vitasync.backend.smartwatch.repository.HistorialMetricasRepository;
import com.vitasync.backend.smartwatch.service.SmartwatchService;
import com.vitasync.backend.usuarios.controller.UsuarioController;
import com.vitasync.backend.usuarios.dto.CrearUsuarioDTO;
import com.vitasync.backend.usuarios.repository.UsuarioRepository;
import com.vitasync.backend.usuarios.service.PinService;
import com.vitasync.backend.usuarios.service.UsuarioService;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.SpringBootConfiguration;
import org.springframework.boot.autoconfigure.EnableAutoConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;

import java.util.List;

/**
 * Backend de VitaSync para las pruebas de caja negra (Práctica 8).
 *
 * Levanta los controladores y servicios REALES (usuarios, PIN, smartwatch,
 * firmware y chat) pero con repositorios en memoria en lugar de Firestore, y
 * sin Elasticsearch. Así el sistema se puede probar completo (por HTTP y
 * desde la app móvil) sin tocar la nube del proyecto. NO es parte del
 * producto: vive en las clases de prueba.
 *
 * Arranque manual (puerto 8081, el mismo que el backend real):
 * <pre>
 *   mvn spring-boot:run -Dspring-boot.run.useTestClasspath=true \
 *       -Dspring-boot.run.mainClass=com.vitasync.backend.blackbox.ServidorPruebas
 * </pre>
 */
@SpringBootConfiguration
@EnableAutoConfiguration(excludeName = {
        "org.springframework.boot.autoconfigure.elasticsearch.ElasticsearchRestClientAutoConfiguration",
        "org.springframework.boot.autoconfigure.data.elasticsearch.ElasticsearchDataAutoConfiguration",
        "org.springframework.boot.autoconfigure.data.elasticsearch.ElasticsearchRepositoriesAutoConfiguration",
        "org.springframework.boot.autoconfigure.data.elasticsearch.ReactiveElasticsearchRepositoriesAutoConfiguration",
        "org.springframework.boot.autoconfigure.data.elasticsearch.ReactiveElasticsearchRestClientAutoConfiguration"
})
@Import({
        UsuarioController.class, UsuarioService.class, PinService.class,
        SmartwatchController.class, SmartwatchService.class,
        FirmwareController.class, FirmwareService.class,
        ChatController.class, ChatService.class,
        com.vitasync.backend.contactos.ContactoController.class, com.vitasync.backend.contactos.ContactoService.class,
        com.vitasync.backend.metas.MetasController.class, com.vitasync.backend.metas.MetasService.class,
        com.vitasync.backend.admin.RolesController.class, com.vitasync.backend.admin.RolesService.class,
        ControlDeAcceso.class,
        CorsConfig.class
})
public class ServidorPruebas {

    @Bean
    UsuarioRepository usuarioRepository() {
        return new RepositoriosEnMemoria.Usuarios();
    }

    @Bean
    DispositivoRepository dispositivoRepository() {
        return new RepositoriosEnMemoria.Dispositivos();
    }

    @Bean
    com.vitasync.backend.admin.GestorDeRoles gestorDeRoles() {
        return new RepositoriosEnMemoria.Roles();
    }

    @Bean
    com.vitasync.backend.metas.MetasRepository metasRepository() {
        return new RepositoriosEnMemoria.Metas();
    }

    @Bean
    com.vitasync.backend.contactos.ContactoRepository contactoRepository() {
        return new RepositoriosEnMemoria.Contactos();
    }

    @Bean
    HistorialMetricasRepository historialMetricasRepository() {
        return new RepositoriosEnMemoria.Historial();
    }

    /**
     * Con --vitasync.seguridad.activa=true el servidor exige token (Práctica 10). Aquí se aceptan los tokens
     * sin firma del emulador de Authentication; ver VerificadorTokenEmulador.
     */
    @Bean
    @ConditionalOnProperty(name = "vitasync.seguridad.activa", havingValue = "true")
    VerificadorToken verificadorToken() {
        return new VerificadorTokenEmulador();
    }

    /** Las mismas tres cuentas que siembra UsuarioSeeder en el backend real. */
    @Bean
    ApplicationRunner sembrar(UsuarioService usuarios) {
        return args -> {
            usuarios.crear(new CrearUsuarioDTO("Alumno Uno", "alumno1", List.of("alumnos")));
            usuarios.crear(new CrearUsuarioDTO("Alumno Dos", "alumno2", List.of("alumnos")));
            usuarios.crear(new CrearUsuarioDTO("Invitado", "invitado", List.of("invitados")));
        };
    }

    public static void main(String[] args) {
        SpringApplication app = new SpringApplication(ServidorPruebas.class);
        app.setDefaultProperties(java.util.Map.of("server.port", "8081"));
        app.run(args);
    }
}
