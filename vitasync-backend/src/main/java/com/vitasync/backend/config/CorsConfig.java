package com.vitasync.backend.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * CORS global. Además de Angular (localhost:4200), la vista móvil se abre
 * desde otro puerto (flutter run) o desde la IP de la PC en la red local
 * cuando se prueba en un teléfono, por lo que se aceptan por patrón
 * localhost y los rangos de red privada.
 */
@Configuration
public class CorsConfig {

    @Bean
    public WebMvcConfigurer corsGlobal() {
        return new WebMvcConfigurer() {
            @Override
            public void addCorsMappings(CorsRegistry registry) {
                registry.addMapping("/api/**")
                        .allowedOriginPatterns(
                                "http://localhost:*",
                                "http://127.0.0.1:*",
                                "http://192.168.*.*:*",
                                "http://10.*.*.*:*")
                        .allowedMethods("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS");
            }
        };
    }
}
