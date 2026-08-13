/** Cuenta de usuario de VitaSync (Práctica 13, reinterpretada como feature real). */
export interface Usuario {
  id: string;
  nombreCompleto: string;
  username: string;
  grupos: string[];
  habilitado: boolean;
  requiereCambioPassword: boolean;
  fechaCreacion: string; // ISO
  ultimoInicioSesion: string | null; // ISO
}

export interface CrearUsuario {
  nombreCompleto: string;
  username: string;
  grupos: string[];
}

export interface LoginResultado {
  exito: boolean;
  mensaje: string;
}
