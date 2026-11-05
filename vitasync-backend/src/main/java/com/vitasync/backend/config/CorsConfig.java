package com.vitasync.backend.config;

import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.Ordered;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;
import org.springframework.web.filter.CorsFilter;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

import java.util.List;

/**
 * CORS global. Además de Angular (localhost:4200), la vista móvil se abre
 * desde otro puerto (flutter run) o desde la IP de la PC en la red local
 * cuando se prueba en un teléfono, por lo que se aceptan por patrón
 * localhost y los rangos de red privada.
 *
 * Se aplica también como FILTRO que corre antes que el control de acceso: el 401 y el 403 los emite ese filtro,
 * antes de llegar a Spring MVC, y sin las cabeceras CORS el navegador los vería como un error de red (estado 0) y
 * el sitio web no sabría que la sesión venció.
 */
@Configuration
public class CorsConfig {

    static final List<String> ORIGENES = List.of(
            "http://localhost:*",
            "http://127.0.0.1:*",
            "http://192.168.*.*:*",
            "http://10.*.*.*:*");

    /** La configuración de CORS de /api/**, reutilizable (también en las pruebas). */
    public static CorsFilter nuevoFiltro() {
        CorsConfiguration c = new CorsConfiguration();
        c.setAllowedOriginPatterns(ORIGENES);
        c.setAllowedMethods(List.of("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"));
        c.setAllowedHeaders(List.of("*"));
        UrlBasedCorsConfigurationSource fuente = new UrlBasedCorsConfigurationSource();
        fuente.registerCorsConfiguration("/api/**", c);
        return new CorsFilter(fuente);
    }

    @Bean
    public FilterRegistrationBean<CorsFilter> corsComoFiltro() {
        FilterRegistrationBean<CorsFilter> registro = new FilterRegistrationBean<>(nuevoFiltro());
        registro.setOrder(Ordered.HIGHEST_PRECEDENCE);
        return registro;
    }

    @Bean
    public WebMvcConfigurer corsGlobal() {
        return new WebMvcConfigurer() {
            @Override
            public void addCorsMappings(CorsRegistry registry) {
                registry.addMapping("/api/**")
                        .allowedOriginPatterns(ORIGENES.toArray(new String[0]))
                        .allowedMethods("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS");
            }
        };
    }
}
