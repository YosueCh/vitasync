/// Los tres estados posibles de una pantalla que carga datos. Al ser una
/// clase sellada, el compilador obliga a que todo `switch` los cubra todos.
sealed class EstadoVista<T> {
  const EstadoVista();
}

final class Cargando<T> extends EstadoVista<T> {
  const Cargando();
}

final class Exito<T> extends EstadoVista<T> {
  const Exito(this.datos);

  final T datos;
}

final class Fallo<T> extends EstadoVista<T> {
  const Fallo(this.mensaje);

  final String mensaje;
}
