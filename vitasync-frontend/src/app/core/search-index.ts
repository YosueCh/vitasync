/**
 * Índice de contenido buscable del sitio VitaSync.
 *
 * En este proyecto cada entrada representa un fragmento de contenido real
 * de las páginas (no rutas completas), para que el buscador pueda llevar
 * al usuario directamente a la sección donde está la respuesta —tal como
 * exige la práctica: "encontrar contenido sin salir del sitio".
 *
 * En producción, este mismo arreglo de documentos es el que se indexaría
 * en Elasticsearch (ver `docs-elasticsearch` más abajo en este proyecto
 * para el backend real con Spring Boot).
 */
export interface DocumentoBuscable {
  id: string;
  titulo: string;
  contenido: string;
  ruta: string;       // a dónde navega Angular Router al hacer clic
  fragmento?: string;  // ancla opcional dentro de la página (#id)
  categoria: string;   // agrupador mostrado en los resultados
}

export const INDICE_BUSQUEDA: DocumentoBuscable[] = [
  // ---- Inicio ----
  {
    id: 'home-hero',
    titulo: 'Tu reloj, tu cuerpo, tu progreso',
    contenido: 'VitaSync conecta tu smartwatch con un dashboard claro y accionable: pasos, sueño, calorías y frecuencia cardiaca, sincronizados en segundos.',
    ruta: '/', categoria: 'Inicio',
  },
  {
    id: 'feature-pasos',
    titulo: 'Pasos',
    contenido: 'Convierte cada caminata en una meta visible, sin esfuerzo de registrar nada a mano.',
    ruta: '/', fragmento: 'caracteristicas', categoria: 'Características',
  },
  {
    id: 'feature-calorias',
    titulo: 'Calorías',
    contenido: 'Sigue tu gasto energético diario y entiende cómo responde tu cuerpo a cada rutina.',
    ruta: '/', fragmento: 'caracteristicas', categoria: 'Características',
  },
  {
    id: 'feature-sueno',
    titulo: 'Sueño',
    contenido: 'Descubre patrones reales de descanso y recibe recordatorios para dormir mejor.',
    ruta: '/', fragmento: 'caracteristicas', categoria: 'Características',
  },
  {
    id: 'feature-fc',
    titulo: 'Frecuencia cardiaca',
    contenido: 'Monitorea tu ritmo en reposo y durante el ejercicio, en una sola vista clara.',
    ruta: '/', fragmento: 'caracteristicas', categoria: 'Características',
  },
  {
    id: 'stats',
    titulo: 'Estadísticas de uso',
    contenido: 'Más de 12,400 usuarios activos, 3.2 millones de pasos registrados por semana y 87% de adherencia a metas diarias.',
    ruta: '/', fragmento: 'estadisticas', categoria: 'Estadísticas',
  },

  // ---- Dashboard ----
  {
    id: 'dashboard-stats',
    titulo: 'Dashboard de tareas',
    contenido: 'Panel de control de tareas en Angular con un widget de estadísticas compilado en Flutter Web e incrustado en vivo.',
    ruta: '/dashboard', categoria: 'Dashboard',
  },

  // ---- Configuración de Dispositivo ----
  {
    id: 'dispositivo-config',
    titulo: 'Configuración de Dispositivo',
    contenido: 'Empareja y sincroniza tu smartwatch VitaSync: estado de conexión, batería, última sincronización y métricas en tiempo real.',
    ruta: '/dispositivo', categoria: 'Configuración',
  },

  // ---- Gestión de Usuarios ----
  {
    id: 'usuarios-gestion',
    titulo: 'Gestión de Usuarios',
    contenido: 'Crea cuentas, habilítalas o deshabilítalas, elimínalas y prueba el efecto de cada estado con "Probar inicio de sesión".',
    ruta: '/usuarios', categoria: 'Administración',
  },

  // ---- Enlazar Smart TV ----
  {
    id: 'smart-tv-enlace',
    titulo: 'Enlazar Smart TV',
    contenido: 'Genera un código de 6 dígitos y emparéjalo desde la pantalla de tu Smart TV para reflejar el dashboard ahí.',
    ruta: '/smart-tv', categoria: 'Smart TV',
  },

  // ---- Nosotros ----
  {
    id: 'nosotros-historia',
    titulo: 'Nuestra historia',
    contenido: 'Empezamos como un equipo de estudiantes frustrados por lo difícil que era conectar los datos de un smartwatch con algo realmente útil.',
    ruta: '/nosotros', categoria: 'Nosotros',
  },
  {
    id: 'nosotros-mision',
    titulo: 'Nuestra misión',
    contenido: 'Hacer que cualquier persona, sin saber de tecnología, entienda sus señales de salud todos los días y actúe a partir de ellas.',
    ruta: '/nosotros', categoria: 'Nosotros',
  },
  {
    id: 'nosotros-valores',
    titulo: 'Valores del equipo',
    contenido: 'Claridad, privacidad, constancia y cercanía guían cada decisión de producto en VitaSync.',
    ruta: '/nosotros', categoria: 'Nosotros',
  },

  // ---- Contacto ----
  {
    id: 'contacto-datos',
    titulo: 'Datos de contacto',
    contenido: 'Av. Tecnológico 1000, Querétaro, México. Teléfono +52 442 555 0199. Correo hola@vitasync.app. Horario lunes a viernes de 9:00 a 18:00.',
    ruta: '/contacto', categoria: 'Contacto',
  },
  {
    id: 'contacto-formulario',
    titulo: 'Formulario de contacto',
    contenido: 'Envía tu nombre, correo, motivo y mensaje para solicitar una demo, soporte técnico o una alianza.',
    ruta: '/contacto', categoria: 'Contacto',
  },

  // ---- FAQ ----
  {
    id: 'faq-smartwatches',
    titulo: '¿Con qué smartwatches funciona VitaSync?',
    contenido: 'Funciona con cualquier wearable redondo genérico compatible con Bluetooth Low Energy (BLE); no requiere un modelo de marca específica.',
    ruta: '/faq', categoria: 'Preguntas frecuentes',
  },
  {
    id: 'faq-celular',
    titulo: '¿Necesito mi celular cerca del reloj todo el tiempo?',
    contenido: 'Sí: el reloj se conecta por Bluetooth a la app de tu celular, y es ésta la que sincroniza los datos hacia el dashboard a través de internet.',
    ruta: '/faq', categoria: 'Preguntas frecuentes',
  },
  {
    id: 'faq-seguridad',
    titulo: '¿Mis datos de salud están seguros?',
    contenido: 'Tus métricas se almacenan en Cloud Firestore con reglas de acceso restringidas; nunca se comparten con terceros sin tu autorización.',
    ruta: '/faq', categoria: 'Preguntas frecuentes',
  },
  {
    id: 'faq-sin-smartwatch',
    titulo: '¿Puedo usar VitaSync sin smartwatch?',
    contenido: 'Sí, puedes registrar tareas y metas manualmente desde el dashboard, aunque la experiencia completa requiere un wearable sincronizado.',
    ruta: '/faq', categoria: 'Preguntas frecuentes',
  },
  {
    id: 'faq-sync',
    titulo: '¿Cuánto tarda la sincronización?',
    contenido: 'Normalmente entre 2 y 5 segundos por ciclo, dependiendo de tu conexión y de la distancia entre el reloj y el celular.',
    ruta: '/faq', categoria: 'Preguntas frecuentes',
  },
  {
    id: 'faq-demos',
    titulo: '¿Ofrecen demos para equipos o instituciones?',
    contenido: 'Sí, agenda una demo desde la página de contacto y te mostramos el dashboard adaptado a tu caso de uso.',
    ruta: '/faq', categoria: 'Preguntas frecuentes',
  },
];
