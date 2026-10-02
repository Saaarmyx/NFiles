// lib/models/file_filter.dart
//
// Criterios de filtrado de un listado: extensión, fecha de modificación y
// tamaño.
//
// # Por qué un modelo y no tres parámetros sueltos
//
// Los tres se combinan (y se combinan con la búsqueda por texto y con el
// orden, que ya vivían en el controller). Con parámetros sueltos, la firma
// crecería en cada sitio que filtra y no habría un sitio donde responder
// "¿hay algún filtro activo?" — que es lo que necesita la barra de chips
// para offering "Limpiar".
//
// # Por qué se filtra al construir la lista y no al pintar
//
// El filtro va dentro de [visibleFiles], que ya está memoizado e
// inmutable: el coste se paga una vez por cambio de criterio, no una vez
// por fila ni una vez por rebuild. Un `where` en el `itemBuilder` pagaría
// el paseo completo del almacenamiento por cada ficha que se pintara.
import 'package:flutter/material.dart' show DateTimeRange;

import 'file_model.dart';

/// Rangos de tamaño ofrecidos en el selector.
enum FileSizeBucket {
  any('Cualquiera'),
  small('Hasta 1 MB', 0, 1024 * 1024),
  medium('1 – 10 MB', 1024 * 1024, 10 * 1024 * 1024),
  large('10 – 100 MB', 10 * 1024 * 1024, 100 * 1024 * 1024),
  huge('Más de 100 MB', 100 * 1024 * 1024, null);

  const FileSizeBucket(this.label, [this.minBytes, this.maxBytes]);

  final String label;

  /// Cota inferior EXCLUYENTE del tamaño: 0 = sin cota.
  final int? minBytes;

  /// Cota superior EXCLUYENTE. `null` = sin tope.
  final int? maxBytes;

  bool matches(int bytes) {
    if (minBytes != null && bytes <= minBytes!) return false;
    if (maxBytes != null && bytes >= maxBytes!) return false;
    return true;
  }
}

/// Filtro activo de un listado. Todos los campos son opcionales y `null`
/// significa "sin criterio".
class FileFilter {
  /// Extensiones elegidas, en minúsculas y con punto (`.pdf`).
  final Set<String> extensions;

  /// Rango de modificación. `null` = cualquier fecha.
  final DateTimeRange? modified;

  /// Rango de tamaño en bytes. `null` = cualquier tamaño.
  final FileSizeBucket size;

  const FileFilter({
    this.extensions = const {},
    this.modified,
    this.size = FileSizeBucket.any,
  });

  /// Sin ningún criterio: la lista se comporta como si no filtrara.
  static const FileFilter none = FileFilter();

  bool get isEmpty =>
      extensions.isEmpty && modified == null && size == FileSizeBucket.any;

  /// `true` si toca pintar el botón de limpiar.
  bool get isActive => !isEmpty;

  FileFilter copyWith({
    Set<String>? extensions,
    DateTimeRange? modified,
    FileSizeBucket? size,
    bool clearDate = false,
  }) {
    return FileFilter(
      extensions: extensions ?? this.extensions,
      modified: clearDate ? null : (modified ?? this.modified),
      size: size ?? this.size,
    );
  }

  /// Enciende o apaga una extensión. Devuelve un filtro NUEVO: el modelo
  /// es inmutable porque el controller lo memoiza y mutarlo en sitio
  /// dejaría la caché de la lista desincronizada sin avisar.
  FileFilter toggleExtension(String ext) {
    final next = Set<String>.of(extensions);
    final limpia = ext.toLowerCase();
    if (!next.remove(limpia)) next.add(limpia);
    return copyWith(extensions: next);
  }

  /// ¿Este archivo pasa el filtro?
  ///
  /// Los criterios van en AND: elegir PDF y "más de 100 MB" tiene que
  /// dar los PDF grandes. Es lo que espera cualquiera que haya usado un
  /// buscador de archivos, y lo contrario devolvería una lista imposible
  /// de explicar.
  bool matches(FileModel file) {
    if (extensions.isNotEmpty) {
      final ext = _extensionOf(file.path);
      if (!extensions.contains(ext)) return false;
    }
    final rango = modified;
    if (rango != null) {
      final m = file.dateModified;
      if (m.isBefore(rango.start) || m.isAfter(rango.end)) return false;
    }
    if (!size.matches(file.sizeInBytes)) return false;
    return true;
  }

  /// Extensión en minúsculas y con punto, sin depender de `path` para no
  /// arrastrar el paquete entero al modelo.
  static String _extensionOf(String path) {
    final slash = path.lastIndexOf('/');
    final name = slash == -1 ? path : path.substring(slash + 1);
    final dot = name.lastIndexOf('.');
    if (dot <= 0) return '';
    return name.substring(dot).toLowerCase();
  }
}

/// Extensiones que se ofrecen como chips.
///
/// No son todas las que la app conoce: son las que alguien filtra de
/// verdad. Una tira de 40 chips donde 35 nunca se encienden es ruido, y
/// para lo raro está la búsqueda por texto.
const List<String> kQuickFilterExtensions = [
  '.pdf',
  '.doc',
  '.xlsx',
  '.pptx',
  '.jpg',
  '.png',
  '.mp4',
  '.mp3',
  '.zip',
  '.apk',
];
