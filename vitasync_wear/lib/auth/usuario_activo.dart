/// Cuenta de VitaSync elegida para esta sesión del reloj. Se limpia al
/// cerrar sesión (no se guarda en disco a propósito): cada vez que
/// alguien entra con el PIN, vuelve a elegir de cuál cuenta son los
/// datos, igual que pasaría si distintas personas comparten el mismo
/// reloj físico.
class UsuarioActivo {
  UsuarioActivo._();

  static String? id;
  static String? nombreCompleto;

  static void establecer(String id, String nombreCompleto) {
    UsuarioActivo.id = id;
    UsuarioActivo.nombreCompleto = nombreCompleto;
  }

  static void limpiar() {
    id = null;
    nombreCompleto = null;
  }
}
