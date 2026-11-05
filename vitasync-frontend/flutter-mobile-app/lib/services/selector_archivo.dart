import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../models/mensaje_chat.dart';

/// Un archivo elegido por la persona, ya leído en memoria.
class ArchivoElegido {
  const ArchivoElegido({required this.nombre, required this.bytes});

  final String nombre;
  final Uint8List bytes;
}

/// Abre el selector de archivos del sistema, limitado a los tipos que acepta el chat. null = canceló.
/// Las pruebas lo reemplazan por uno falso (no hay selector real en `flutter test`).
Future<ArchivoElegido?> elegirArchivoDelSistema() async {
  final r = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ReglasArchivo.tipos.keys.toList(),
    withData: true,
  );
  final f = r?.files.single;
  if (f == null || f.bytes == null) return null;
  return ArchivoElegido(nombre: f.name, bytes: f.bytes!);
}
