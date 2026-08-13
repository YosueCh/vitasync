export type EstadoCast = 'ESPERANDO_TV' | 'EMPAREJADO' | 'EXPIRADO';

/** Sesión de enlace con Smart TV (Práctica 9-10). */
export interface CastSession {
  codigo: string;
  estado: EstadoCast;
  creadoEn: string;
  expiraEn: string;
  emparejadoEn: string | null;
}
