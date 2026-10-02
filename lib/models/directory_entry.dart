// lib/models/directory_entry.dart
//
// Una carpeta dentro del directorio que se está viendo.
//
// # Por qué un modelo aparte y no reusing `FileModel`
//
// Reusar `FileModel` fue lo primero que se probó y es un error. `FileModel`
// describe algo que se puede abrir, compartir y buscar: tiene `sizeInBytes`,
// `isVideo` y se pasa al visor de archivos. Una carpeta no tiene nada de eso,
// y al verla en la lista de archivos el usuario puede tocar un `FileModel`
// vacío y abrir el visor con una carpeta dentro, que es un camino a un error
// que no se puede recuperar.
//
// Además, el orden de la vista es "carpetas primero, luego archivos", y son
// dos listas distintas. Con un solo tipo habría que marcar cada archivo con
// un `isDirectory` y filtrar en tres sitios, que es donde se cuelan bugs.
import 'package:NexoraCore/NexoraCore.dart';

/// Una carpeta en el listado del directorio actual.
class DirectoryEntry {
  /// Ruta absoluta. Es la identidad, igual que en `FileModel`: la misma
  /// carpeta con otro mtime sigue siendo la misma carpeta.
  final String path;

  /// Nombre de la carpeta, sin su ruta.
  final String name;

  final DateTime modified;

  final bool hidden;

  const DirectoryEntry({
    required this.path,
    required this.name,
    required this.modified,
    this.hidden = false,
  });

  /// Constructor desde una entrada nativa.
  ///
  /// Vive aquí y no en el controlador para que la conversión esté junto al
  /// modelo que produce, y no repartida por quien la usa.
  factory DirectoryEntry.fromNative(FileEntry entry) => DirectoryEntry(
        path: entry.path,
        name: entry.name,
        modified: entry.modified,
        hidden: entry.isHidden,
      );

  @override
  bool operator ==(Object other) =>
      other is DirectoryEntry && other.path == path;

  /// Por ruta, no por contenido: dos listados del mismo directorio tienen
  /// que considerarse la misma carpeta aunque el mtime haya cambiado entre
  /// ellos, que es justo lo que pasa al entrar y salir.
  @override
  int get hashCode => path.hashCode;

  @override
  String toString() => 'DirectoryEntry($path)';
}
