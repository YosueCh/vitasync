package com.vitasync.backend.search;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.CommandLineRunner;
import org.springframework.stereotype.Component;

import java.util.List;

/**
 * Carga en Elasticsearch, al arrancar, el mismo contenido que
 * src/app/core/search-index.ts define para el modo local (FlexSearch).
 * Asi el buscador devuelve resultados identicos sin importar si el
 * frontend esta en MODO_LOCAL=true o false.
 *
 * Solo siembra el indice si esta vacio, para no duplicar documentos
 * en cada reinicio de la aplicacion.
 */
@Component
public class SearchIndexSeeder implements CommandLineRunner {

    private static final Logger log = LoggerFactory.getLogger(SearchIndexSeeder.class);

    private final SearchDocumentRepository repository;

    public SearchIndexSeeder(SearchDocumentRepository repository) {
        this.repository = repository;
    }

    @Override
    public void run(String... args) {
        long total = repository.count();
        if (total > 0) {
            log.info("Indice vitasync-content ya tiene {} documentos, se omite la siembra.", total);
            return;
        }

        List<SearchDocument> contenido = contenidoInicial();
        repository.saveAll(contenido);
        log.info("Indice vitasync-content sembrado con {} documentos.", contenido.size());
    }

    private List<SearchDocument> contenidoInicial() {
        return List.of(
                // ---- Inicio ----
                new SearchDocument("home-hero",
                        "Tu reloj, tu cuerpo, tu progreso",
                        "VitaSync conecta tu smartwatch con un dashboard claro y accionable: pasos, sueño, calorías y frecuencia cardiaca, sincronizados en segundos.",
                        "/", null, "Inicio"),
                new SearchDocument("feature-pasos",
                        "Pasos",
                        "Convierte cada caminata en una meta visible, sin esfuerzo de registrar nada a mano.",
                        "/", "caracteristicas", "Características"),
                new SearchDocument("feature-calorias",
                        "Calorías",
                        "Sigue tu gasto energético diario y entiende cómo responde tu cuerpo a cada rutina.",
                        "/", "caracteristicas", "Características"),
                new SearchDocument("feature-sueno",
                        "Sueño",
                        "Descubre patrones reales de descanso y recibe recordatorios para dormir mejor.",
                        "/", "caracteristicas", "Características"),
                new SearchDocument("feature-fc",
                        "Frecuencia cardiaca",
                        "Monitorea tu ritmo en reposo y durante el ejercicio, en una sola vista clara.",
                        "/", "caracteristicas", "Características"),
                new SearchDocument("stats",
                        "Estadísticas de uso",
                        "Más de 12,400 usuarios activos, 3.2 millones de pasos registrados por semana y 87% de adherencia a metas diarias.",
                        "/", "estadisticas", "Estadísticas"),

                // ---- Dashboard ----
                new SearchDocument("dashboard-stats",
                        "Dashboard de tareas",
                        "Panel de control de tareas en Angular con un widget de estadísticas compilado en Flutter Web e incrustado en vivo.",
                        "/dashboard", null, "Dashboard"),

                // ---- Configuración de Dispositivo ----
                new SearchDocument("dispositivo-config",
                        "Configuración de Dispositivo",
                        "Empareja y sincroniza tu smartwatch VitaSync: estado de conexión, batería, última sincronización y métricas en tiempo real.",
                        "/dispositivo", null, "Configuración"),

                // ---- Gestión de Usuarios ----
                new SearchDocument("usuarios-gestion",
                        "Gestión de Usuarios",
                        "Crea cuentas, habilítalas o deshabilítalas, elimínalas y prueba el efecto de cada estado con \"Probar inicio de sesión\".",
                        "/usuarios", null, "Administración"),

                // ---- Enlazar Smart TV ----
                new SearchDocument("smart-tv-enlace",
                        "Enlazar Smart TV",
                        "Genera un código de 6 dígitos y emparéjalo desde la pantalla de tu Smart TV para reflejar el dashboard ahí.",
                        "/smart-tv", null, "Smart TV"),

                // ---- Nosotros ----
                new SearchDocument("nosotros-historia",
                        "Nuestra historia",
                        "Empezamos como un equipo de estudiantes frustrados por lo difícil que era conectar los datos de un smartwatch con algo realmente útil.",
                        "/nosotros", null, "Nosotros"),
                new SearchDocument("nosotros-mision",
                        "Nuestra misión",
                        "Hacer que cualquier persona, sin saber de tecnología, entienda sus señales de salud todos los días y actúe a partir de ellas.",
                        "/nosotros", null, "Nosotros"),
                new SearchDocument("nosotros-valores",
                        "Valores del equipo",
                        "Claridad, privacidad, constancia y cercanía guían cada decisión de producto en VitaSync.",
                        "/nosotros", null, "Nosotros"),

                // ---- Contacto ----
                new SearchDocument("contacto-datos",
                        "Datos de contacto",
                        "Av. Tecnológico 1000, Querétaro, México. Teléfono +52 442 555 0199. Correo hola@vitasync.app. Horario lunes a viernes de 9:00 a 18:00.",
                        "/contacto", null, "Contacto"),
                new SearchDocument("contacto-formulario",
                        "Formulario de contacto",
                        "Envía tu nombre, correo, motivo y mensaje para solicitar una demo, soporte técnico o una alianza.",
                        "/contacto", null, "Contacto"),

                // ---- FAQ ----
                new SearchDocument("faq-smartwatches",
                        "¿Con qué smartwatches funciona VitaSync?",
                        "Funciona con cualquier wearable redondo genérico compatible con Bluetooth Low Energy (BLE); no requiere un modelo de marca específica.",
                        "/faq", null, "Preguntas frecuentes"),
                new SearchDocument("faq-celular",
                        "¿Necesito mi celular cerca del reloj todo el tiempo?",
                        "Sí: el reloj se conecta por Bluetooth a la app de tu celular, y es ésta la que sincroniza los datos hacia el dashboard a través de internet.",
                        "/faq", null, "Preguntas frecuentes"),
                new SearchDocument("faq-seguridad",
                        "¿Mis datos de salud están seguros?",
                        "Tus métricas se almacenan en Cloud Firestore con reglas de acceso restringidas; nunca se comparten con terceros sin tu autorización.",
                        "/faq", null, "Preguntas frecuentes"),
                new SearchDocument("faq-sin-smartwatch",
                        "¿Puedo usar VitaSync sin smartwatch?",
                        "Sí, puedes registrar tareas y metas manualmente desde el dashboard, aunque la experiencia completa requiere un wearable sincronizado.",
                        "/faq", null, "Preguntas frecuentes"),
                new SearchDocument("faq-sync",
                        "¿Cuánto tarda la sincronización?",
                        "Normalmente entre 2 y 5 segundos por ciclo, dependiendo de tu conexión y de la distancia entre el reloj y el celular.",
                        "/faq", null, "Preguntas frecuentes"),
                new SearchDocument("faq-demos",
                        "¿Ofrecen demos para equipos o instituciones?",
                        "Sí, agenda una demo desde la página de contacto y te mostramos el dashboard adaptado a tu caso de uso.",
                        "/faq", null, "Preguntas frecuentes")
        );
    }
}
