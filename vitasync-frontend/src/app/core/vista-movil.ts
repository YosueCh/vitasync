/**
 * Propuesta (Parcial 3): en un teléfono el sitio entrega la vista móvil (Flutter Web / PWA, servida en /movil/) en lugar del
 * sitio de escritorio. Quien prefiera el sitio completo agrega «?escritorio=1» una vez y se recuerda en la sesión del navegador.
 */
export const RUTA_VISTA_MOVIL = '/movil/';
export const CLAVE_ESCRITORIO = 'vitasync-escritorio';

const AGENTE_MOVIL = /Android|iPhone|iPad|iPod|Mobile|Opera Mini|IEMobile|BlackBerry/i;

export interface EntornoNavegador {
  /** navigator.userAgent */
  agente: string;
  /** location.pathname */
  ruta: string;
  /** location.search */
  consulta: string;
  /** ¿la persona ya pidió el sitio de escritorio en esta sesión? */
  escritorioGuardado: boolean;
}

export function esAgenteMovil(agente: string | null | undefined): boolean {
  return !!agente && AGENTE_MOVIL.test(agente);
}

export function pideEscritorio(consulta: string): boolean {
  return new URLSearchParams(consulta).get('escritorio') === '1';
}

/** true = hay que mandar al teléfono a la vista móvil. Nunca redirige si ya está en /movil/ (evita bucles). */
export function debeIrALaVistaMovil(e: EntornoNavegador): boolean {
  if (e.ruta === RUTA_VISTA_MOVIL.slice(0, -1) || e.ruta.startsWith(RUTA_VISTA_MOVIL)) return false;
  if (e.escritorioGuardado || pideEscritorio(e.consulta)) return false;
  return esAgenteMovil(e.agente);
}
