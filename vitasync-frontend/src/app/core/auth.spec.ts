import { TestBed } from '@angular/core/testing';
import { HttpClient, provideHttpClient, withInterceptors } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { Router, provideRouter } from '@angular/router';

import { AUTH_CONFIG } from './auth.config';
import { AuthService } from './auth.service';
import { authGuard, authInterceptor } from './auth.interceptor';
import { Acceso } from '../pages/acceso/acceso';
import { routes } from '../app.routes';

const URL_ENTRAR = `${AUTH_CONFIG.base}/v1/accounts:signInWithPassword?key=${AUTH_CONFIG.apiKey}`;
const URL_CREAR = `${AUTH_CONFIG.base}/v1/accounts:signUp?key=${AUTH_CONFIG.apiKey}`;
const RESPUESTA = { localId: 'uid-1', email: 'ana@uteq.test', idToken: 'token-de-ana', expiresIn: '3600' };

function preparar() {
  sessionStorage.clear();
  TestBed.configureTestingModule({
    providers: [
      provideRouter(routes),
      provideHttpClient(withInterceptors([authInterceptor])),
      provideHttpClientTesting(),
    ],
  });
  return {
    auth: TestBed.inject(AuthService),
    http: TestBed.inject(HttpClient),
    mock: TestBed.inject(HttpTestingController),
    router: TestBed.inject(Router),
  };
}

describe('Inicio de sesión del sitio (Práctica 10)', () => {
  afterEach(() => sessionStorage.clear());

  it('entrar guarda la sesión y manda correo y contraseña a Firebase Authentication', () => {
    const { auth, mock } = preparar();
    let sesion: unknown;
    auth.iniciarSesion('ana@uteq.test', 'Clave123').subscribe((s) => (sesion = s));
    const req = mock.expectOne(URL_ENTRAR);
    expect(req.request.body).toEqual({ email: 'ana@uteq.test', password: 'Clave123', returnSecureToken: true });
    req.flush(RESPUESTA);
    expect(sesion).toBeTruthy();
    expect(auth.sesion()?.correo).toBe('ana@uteq.test');
    expect(auth.token()).toBe('token-de-ana');
  });

  it('crear cuenta usa signUp', () => {
    const { auth, mock } = preparar();
    auth.registrarse('ana@uteq.test', 'Clave123').subscribe();
    mock.expectOne(URL_CREAR).flush(RESPUESTA);
    expect(auth.sesion()?.uid).toBe('uid-1');
  });

  it('contraseña incorrecta: mensaje genérico y no hay sesión', () => {
    const { auth, mock } = preparar();
    let mensaje = '';
    auth.iniciarSesion('ana@uteq.test', 'mala').subscribe({ error: (e: Error) => (mensaje = e.message) });
    mock.expectOne(URL_ENTRAR).flush({ error: { message: 'INVALID_LOGIN_CREDENTIALS' } }, { status: 400, statusText: 'Bad Request' });
    expect(mensaje).toBe('Correo o contraseña incorrectos.');
    expect(auth.sesion()).toBeNull();
  });

  it('mensajes claros para correo repetido, contraseña débil y sin conexión', () => {
    const { auth, mock } = preparar();
    const dichos: string[] = [];
    const caso = (cuerpo: object, status: number) => {
      auth.registrarse('a@b.c', 'x').subscribe({ error: (e: Error) => dichos.push(e.message) });
      mock.expectOne(URL_CREAR).flush(cuerpo, { status, statusText: 'x' });
    };
    caso({ error: { message: 'EMAIL_EXISTS' } }, 400);
    caso({ error: { message: 'WEAK_PASSWORD : Password should be at least 6 characters' } }, 400);
    auth.registrarse('a@b.c', 'x').subscribe({ error: (e: Error) => dichos.push(e.message) });
    mock.expectOne(URL_CREAR).error(new ProgressEvent('error'));
    expect(dichos).toEqual([
      'Ya existe una cuenta con ese correo.',
      'La contraseña debe tener al menos 6 caracteres.',
      'No se pudo conectar con el servicio de acceso.',
    ]);
  });

  it('la sesión sobrevive a una recarga (sessionStorage) y cerrar la sesión la borra', () => {
    const { auth, mock } = preparar();
    auth.iniciarSesion('ana@uteq.test', 'Clave123').subscribe();
    mock.expectOne(URL_ENTRAR).flush(RESPUESTA);
    TestBed.resetTestingModule();
    const { auth: nueva } = preparar_sinLimpiar();
    expect(nueva.sesion()?.correo).toBe('ana@uteq.test');
    nueva.cerrarSesion();
    expect(nueva.sesion()).toBeNull();
    expect(sessionStorage.getItem('vitasync_sesion')).toBeNull();
  });

  it('un token vencido no se usa: se cierra la sesión', () => {
    const { auth, mock } = preparar();
    auth.iniciarSesion('ana@uteq.test', 'Clave123').subscribe();
    mock.expectOne(URL_ENTRAR).flush({ ...RESPUESTA, expiresIn: '0' });
    expect(auth.token()).toBeNull();
    expect(auth.sesion()).toBeNull();
  });
});

function preparar_sinLimpiar() {
  TestBed.configureTestingModule({
    providers: [provideRouter(routes), provideHttpClient(withInterceptors([authInterceptor])), provideHttpClientTesting()],
  });
  return { auth: TestBed.inject(AuthService) };
}

describe('Interceptor y guardia', () => {
  afterEach(() => sessionStorage.clear());

  it('manda el token SOLO al backend de VitaSync', () => {
    const { auth, http, mock } = preparar();
    auth.iniciarSesion('ana@uteq.test', 'Clave123').subscribe();
    mock.expectOne(URL_ENTRAR).flush(RESPUESTA);

    http.get(`${AUTH_CONFIG.api}/usuarios`).subscribe();
    expect(mock.expectOne(`${AUTH_CONFIG.api}/usuarios`).request.headers.get('Authorization')).toBe('Bearer token-de-ana');

    http.get('https://otro-sitio.example/datos').subscribe();
    expect(mock.expectOne('https://otro-sitio.example/datos').request.headers.has('Authorization')).toBe(false);
  });

  it('sin sesión no se manda cabecera', () => {
    const { http, mock } = preparar();
    http.get(`${AUTH_CONFIG.api}/usuarios`).subscribe({ error: () => undefined });
    expect(mock.expectOne(`${AUTH_CONFIG.api}/usuarios`).request.headers.has('Authorization')).toBe(false);
  });

  it('un 401 del backend cierra la sesión y lleva a «Iniciar sesión»', async () => {
    const { auth, http, mock, router } = preparar();
    auth.iniciarSesion('ana@uteq.test', 'Clave123').subscribe();
    mock.expectOne(URL_ENTRAR).flush(RESPUESTA);
    http.get(`${AUTH_CONFIG.api}/usuarios`).subscribe({ error: () => undefined });
    mock.expectOne(`${AUTH_CONFIG.api}/usuarios`).flush({ error: 'Inicia sesión' }, { status: 401, statusText: 'Unauthorized' });
    await Promise.resolve();
    expect(auth.sesion()).toBeNull();
    await new Promise((r) => setTimeout(r));
    expect(router.url).toContain('/acceso');
  });

  it('un 403 no cierra la sesión (es un permiso, no una sesión vencida)', () => {
    const { auth, http, mock } = preparar();
    auth.iniciarSesion('ana@uteq.test', 'Clave123').subscribe();
    mock.expectOne(URL_ENTRAR).flush(RESPUESTA);
    http.get(`${AUTH_CONFIG.api}/usuarios/x`).subscribe({ error: () => undefined });
    mock.expectOne(`${AUTH_CONFIG.api}/usuarios/x`).flush({ error: 'sin permiso' }, { status: 403, statusText: 'Forbidden' });
    expect(auth.sesion()).not.toBeNull();
  });

  it('la guardia deja pasar con sesión y redirige a «Iniciar sesión» sin ella, recordando a dónde iba', () => {
    const { auth, mock, router } = preparar();
    const estado = { url: '/dashboard' } as never;
    const sinSesion = TestBed.runInInjectionContext(() => authGuard({} as never, estado));
    expect(router.serializeUrl(sinSesion as never)).toBe('/acceso?volver=%2Fdashboard');

    auth.iniciarSesion('ana@uteq.test', 'Clave123').subscribe();
    mock.expectOne(URL_ENTRAR).flush(RESPUESTA);
    expect(TestBed.runInInjectionContext(() => authGuard({} as never, estado))).toBe(true);
  });

  it('dashboard, dispositivo y usuarios están protegidos; inicio, faq y acceso no', () => {
    const protegidas = routes.filter((r) => r.canActivate?.includes(authGuard)).map((r) => r.path);
    expect(protegidas).toEqual(['dashboard', 'dispositivo', 'usuarios']);
    expect(routes.find((r) => r.path === 'acceso')?.canActivate).toBeUndefined();
    expect(routes.find((r) => r.path === '')?.canActivate).toBeUndefined();
  });
});

describe('Pantalla «Iniciar sesión»', () => {
  afterEach(() => sessionStorage.clear());

  function montar() {
    const base = preparar();
    const fixture = TestBed.createComponent(Acceso);
    fixture.detectChanges();
    const el = fixture.nativeElement as HTMLElement;
    const escribir = (id: string, valor: string) => {
      const i = el.querySelector<HTMLInputElement>(id)!;
      i.value = valor;
      i.dispatchEvent(new Event('input'));
    };
    return { ...base, fixture, el, escribir };
  }

  it('con campos vacíos avisa y no llama a Firebase', () => {
    const { el, fixture, mock } = montar();
    el.querySelector<HTMLButtonElement>('#acceso-entrar')!.click();
    fixture.detectChanges();
    expect(el.querySelector('#acceso-error')?.textContent).toContain('Escribe tu correo y tu contraseña');
    mock.expectNone(URL_ENTRAR);
  });

  it('entrar con datos válidos llama a Firebase y, al responder, lleva al dashboard', async () => {
    const { el, fixture, mock, router, escribir } = montar();
    escribir('#acceso-correo', 'ana@uteq.test');
    escribir('#acceso-clave', 'Clave123');
    el.querySelector<HTMLButtonElement>('#acceso-entrar')!.click();
    mock.expectOne(URL_ENTRAR).flush(RESPUESTA);
    await fixture.whenStable();
    expect(router.url).toBe('/dashboard');
  });

  it('un error de Firebase se muestra y la contraseña no se borra sola del formulario del error', () => {
    const { el, fixture, mock, escribir } = montar();
    escribir('#acceso-correo', 'ana@uteq.test');
    escribir('#acceso-clave', 'mala');
    el.querySelector<HTMLButtonElement>('#acceso-entrar')!.click();
    mock.expectOne(URL_ENTRAR).flush({ error: { message: 'INVALID_PASSWORD' } }, { status: 400, statusText: 'x' });
    fixture.detectChanges();
    expect(el.querySelector('#acceso-error')?.textContent).toContain('Correo o contraseña incorrectos.');
  });
});
