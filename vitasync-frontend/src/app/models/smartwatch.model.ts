/** Estados posibles de la conexión con el smartwatch. */
export type EstadoConexion = 'DESCONECTADO' | 'CONECTANDO' | 'CONECTADO' | 'SINCRONIZANDO' | 'ERROR';

/** Información del dispositivo emparejado. */
export interface Dispositivo {
  id: string;
  nombre: string; // p.ej. "VitaSync Watch R1"
  modelo: string; // wearable redondo genérico
  bateria: number; // 0-100 (%)
  firmware: string;
  ultimaSync: string | null; // ISO timestamp
}

/** Métricas de salud capturadas por el smartwatch. */
export interface Metricas {
  pasos: number;
  calorias: number;
  sueñoHoras: number;
  frecuenciaCardiaca: number; // bpm
  bateria: number; // %
  timestamp: string; // ISO
}

/** Metas y avisos que el sistema envía de regreso al reloj. */
export interface Metas {
  metaPasos: number;
  metaCalorias: number;
  metaSueñoHoras: number;
  notificaciones: string[];
  recordatorios: string[];
}

/** Respuesta de estado consumida por el indicador visual. */
export interface EstadoRespuesta {
  estado: EstadoConexion;
  dispositivo: Dispositivo | null;
  mensaje: string;
}
