import { RUTA_VISTA_MOVIL, debeIrALaVistaMovil, esAgenteMovil, pideEscritorio } from './vista-movil';

const ANDROID = 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36';
const IPHONE = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1';
const ESCRITORIO = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36';
const base = { ruta: '/', consulta: '', escritorioGuardado: false };

describe('Detección de la vista móvil (Parcial 3 de la propuesta)', () => {
  it('reconoce teléfonos Android y iPhone, y no reconoce una computadora', () => {
    expect(esAgenteMovil(ANDROID)).toBe(true);
    expect(esAgenteMovil(IPHONE)).toBe(true);
    expect(esAgenteMovil(ESCRITORIO)).toBe(false);
  });

  it('agente vacío o nulo no es móvil', () => {
    expect(esAgenteMovil('')).toBe(false);
    expect(esAgenteMovil(null)).toBe(false);
    expect(esAgenteMovil(undefined)).toBe(false);
  });

  it('un teléfono que abre el sitio es enviado a /movil/', () => {
    expect(debeIrALaVistaMovil({ ...base, agente: ANDROID })).toBe(true);
    expect(debeIrALaVistaMovil({ ...base, agente: IPHONE, ruta: '/acceso' })).toBe(true);
    expect(RUTA_VISTA_MOVIL).toBe('/movil/');
  });

  it('una computadora nunca es redirigida', () => {
    expect(debeIrALaVistaMovil({ ...base, agente: ESCRITORIO })).toBe(false);
  });

  it('nunca redirige si ya está en /movil/ (sin bucles)', () => {
    expect(debeIrALaVistaMovil({ ...base, agente: ANDROID, ruta: '/movil/' })).toBe(false);
    expect(debeIrALaVistaMovil({ ...base, agente: ANDROID, ruta: '/movil' })).toBe(false);
    expect(debeIrALaVistaMovil({ ...base, agente: ANDROID, ruta: '/movil/index.html' })).toBe(false);
  });

  it('«?escritorio=1» o la preferencia guardada permiten ver el sitio completo en el teléfono', () => {
    expect(pideEscritorio('?escritorio=1')).toBe(true);
    expect(pideEscritorio('?otra=1')).toBe(false);
    expect(debeIrALaVistaMovil({ ...base, agente: ANDROID, consulta: '?escritorio=1' })).toBe(false);
    expect(debeIrALaVistaMovil({ ...base, agente: ANDROID, escritorioGuardado: true })).toBe(false);
  });
});
