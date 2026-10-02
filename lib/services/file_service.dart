import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:NexoraCore/NexoraCore.dart';
import '../models/file_model.dart';

class FileService {
  /// Imágenes: única familia con metadatos EXIF/dimensiones (sonda de NexoraCore).
  static const Set<String> imageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.heic',
    '.heif',
    '.bmp',
    '.tiff',
    '.tif',
    '.avif',
  };

  static const Set<String> videoExtensions = {
    '.mp4',
    '.mov',
    '.m4v',
    '.3gp',
    '.mkv',
    '.webm',
    '.avi',
    '.mpg',
    '.mpeg',
    '.wmv',
    '.flv',
  };

  /// Extensiones que la app CONOCE y clasifica.
  ///
  /// Ya no es una lista blanca de escaneo (el gestor acepta cualquier
  /// archivo; ver [_isValidMediaFile]). Sirve para saber qué formatos
  /// reciben trato especial: los de [kProbeableExtensions] pasan por la
  /// sonda de metadatos, y el resto se clasifican por [kindForPath].
  static final Set<String> supportedExtensions = kAllKnownExtensions;

  /// Directorios raíz a escanear. Si es `null` se usan los de la plataforma.
  /// Existe para tests y futuras fuentes personalizadas.
  final List<Directory>? roots;

  /// Si el barrido corre en un isolate aparte.
  ///
  /// `true` (por defecto) es lo correcto: no bloquea el hilo de UI con
  /// bibliotecas grandes. `false` ejecuta el barrido en el isolate actual,
  /// que es lo único viable bajo el reloj falso de `testWidgets` (donde
  /// `compute` nunca completa) y también lo razonable cuando las raíces
  /// son pocas y pequeñas, porque el salto de isolate se paga entero.
  final bool useIsolate;

  /// Si el barrido incluye los archivos ocultos (los que empiezan por `.`)
  /// y los que viven dentro de carpetas ocultas (`.thumbnails`, `.trash`).
  ///
  /// Por defecto `false`, que es lo que espera un gestor: `.thumbnails`
  /// puede tener una copia de cada imagen del móvil y, al incluirlo, el
  /// conteo de cada categoría se duplica. El ajuste "Archivos ocultos" de
  /// Ajustes conmuta esto y dispara un reescaneo.
  final bool showHidden;

  FileService({this.roots, this.useIsolate = true, this.showHidden = false});

  /// Copia con [showHidden] distinto, conservando raíces y modo de barrido.
  ///
  /// El servicio es inmutable y vive en el controlador, pero el ajuste de
  /// ocultos cambia durante la sesión: en vez de mutarlo (y que el
  /// reescaneo concurrente vea un estado a medias) cada barrido pide una
  /// copia con el valor vigente.
  FileService withHidden(bool value) => FileService(
        roots: roots,
        useIsolate: useIsolate,
        showHidden: value,
      );

  Future<List<FileModel>> loadFiles() async {
    if (roots != null) {
      return _loadFromDirectories(roots!, label: 'Custom');
    }
    if (Platform.isAndroid) {
      return _loadFromDirectories(_androidDirs(), label: 'Android');
    } else if (Platform.isLinux) {
      return _loadFromDirectories(_ubuntuDirs(), label: 'Ubuntu');
    }
    return [];
  }

  /// Raíces existentes, listas para observar con [Directory.watch].
  /// Es la misma fuente que usa [loadFiles]: lo que se detecte aquí es
  /// lo que aparecerá en el explorador tras recargar.
  Future<List<Directory>> existingRoots() async {
    final List<Directory> dirs;
    if (roots != null) {
      dirs = roots!;
    } else if (Platform.isAndroid) {
      dirs = _androidDirs();
    } else if (Platform.isLinux) {
      dirs = _ubuntuDirs();
    } else {
      return [];
    }
    final existing = <Directory>[];
    for (final dir in dirs) {
      try {
        if (await dir.exists()) existing.add(dir);
      } catch (_) {
        continue;
      }
    }
    return existing;
  }

  List<Directory> _ubuntuDirs() {
    final home = Platform.environment['HOME'];
    if (home == null) return [];
    // `home` recursivo cubre todo; se listan las carpetas conocidas para
    // que las consultas por ubicación (Descargas, Documentos) tengan una
    // ruta aunque el home sea inaccesible por separado.
    return [
      Directory(home),
      Directory(p.join(home, 'Pictures')),
      Directory(p.join(home, 'Downloads')),
      Directory(p.join(home, 'Documents')),
      Directory(p.join(home, 'Music')),
      Directory(p.join(home, 'Videos')),
      Directory(p.join(home, 'Imágenes')),
    ];
  }

  /// Raíces en Android.
  ///
  /// Un gestor de archivos tiene que cubrir TODO el almacenamiento
  /// compartido, no solo DCIM: por eso se incluye la raíz y las carpetas
  /// de sistema más usadas. Las que no existen se filtran después
  /// ([existingRoots] y el propio escaneo las saltan).
  List<Directory> _androidDirs() {
    const String basePath = '/storage/emulated/0';
    return [
      Directory(basePath),
      Directory(p.join(basePath, 'DCIM')),
      Directory(p.join(basePath, 'Download')),
      Directory(p.join(basePath, 'Documents')),
      Directory(p.join(basePath, 'Music')),
      Directory(p.join(basePath, 'Movies')),
      Directory(p.join(basePath, 'Pictures')),
    ];
  }

  /// Recorre [dirs] y construye la lista de archivos ordenada por modificación.
  ///
  /// El barrido del disco corre en un isolate ([compute]) para no bloquear
  /// el hilo de UI con bibliotecas grandes; aquí solo se materializan
  /// los [FileModel] a partir de filas simples (transferibles entre isolates).
  Future<List<FileModel>> _loadFromDirectories(
    List<Directory> dirs, {
    required String label,
  }) async {
    final existing = <String>[];
    for (final dir in dirs) {
      if (await dir.exists()) existing.add(dir.path);
    }
    if (existing.isEmpty) return [];

    List<Map<String, Object>> rows;
    try {
      // `compute` toma UN argumento, así que el flag viaja en un registro
      // (`(List<String>, bool)`) y no en un Map: los registros son
      // transferibles entre isolates y no hay claves que puedan quedar sin
      // leer por un lado.
      final request = (existing, showHidden);
      rows = useIsolate
          ? await compute(_scan, request)
          : await _scan(request);
    } catch (e) {
      debugPrint('Error escaneando directorios $label: $e');
      return [];
    }

    final files = rows
        .map(
          (row) => FileModel(
            id: row['path'] as String,
            path: row['path'] as String,
            // Todo lo derivable del nombre ya viene resuelto del isolate:
            // recalcularlo aquí por fila es lo que atascaba el hilo UI con
            // decenas de miles de archivos.
            title: row['title'] as String,
            dateCreated: DateTime.fromMillisecondsSinceEpoch(
              row['created'] as int,
            ),
            dateModified: DateTime.fromMillisecondsSinceEpoch(
              row['modified'] as int,
            ),
            sizeInBytes: row['size'] as int,
            isVideo: (row['isVideo'] as bool?) ?? false,
            width: row['width'] as int?,
            height: row['height'] as int?,
            latitude: (row['lat'] as num?)?.toDouble(),
            longitude: (row['lng'] as num?)?.toDouble(),
            locationLabel: row['loc'] as String?,
            isMotionPhoto: (row['motion'] as bool?) ?? false,
            isSelfie: (row['selfie'] as bool?) ?? false,
            // duration se resuelve bajo demanda en el visor (media_kit).
          ),
        )
        .toList();

    // Ya vienen ordenadas del isolate (ver `_scanPaths`): ordenar aquí de
    // nuevo sería pagar el O(N log N) en el hilo de UI.
    return files;
  }

  /// Etiqueta geográfica legible a partir de coordenadas EXIF.
  /// Sin red (sin geocodificación inversa): coordenadas con 4 decimales
  /// (~11 m). Null = el visor oculta la ubicación.
  static String? _locationLabel(double? lat, double? lng) {
    if (lat == null || lng == null) return null;
    return '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
  }

  /// Heurística Motion FileModel por nombre (MVIMG, motion, live).
  static bool _isMotionPhoto(String filePath) {
    final name = p.basename(filePath).toUpperCase();
    return name.contains('MVIMG') ||
        name.contains('MOTION') ||
        name.contains('LIVE');
  }

  /// Heurística selfie por nombre/carpeta (frontal, selfie).
  static bool _isSelfie(String filePath) {
    final lower = filePath.toLowerCase();
    return lower.contains('selfie') ||
        lower.contains('front') ||
        lower.contains('img_f');
  }

  /// Barrido asíncrono pensado para correr en background vía `compute`.
  /// Solo devuelve tipos primitivos porque cruza el límite del isolate.
  ///
  /// Dos fases: (1) caminata síncrona rápida con `stat` y (2) sonda de
  /// cabecera (dimensiones + GPS EXIF) en lotes concurrentes. Un fallo
  /// por archivo nunca rompe el barrido: esa archivo queda sin metadatos.
  /// Al salir, las filas van ordenadas por modificación descendente y con
  /// lo derivable del nombre ya calculado, para que el hilo de UI solo
  /// materialice modelos en una pasada.
  static Future<List<Map<String, Object>>> _scan(
    (List<String>, bool) request,
  ) =>
      _scanPaths(request.$1, showHidden: request.$2);

  static Future<List<Map<String, Object>>> _scanPaths(
    List<String> dirPaths, {
    bool showHidden = false,
  }) async {
    final found = <_FoundFile>[];
    // Las raíces se solapan a propósito (la base cubre a las subcarpetas,
    // que se listan para cuando la base no es legible): sin este visto, un
    // archivo saldría una vez por cada raíz que lo contenga e inflaría
    // conteos y categorías.
    final seen = <String>{};
    for (final dirPath in dirPaths) {
      try {
        final entities = Directory(
          dirPath,
        ).listSync(recursive: true, followLinks: false);
        for (final entity in entities) {
          if (!_isValidMediaFile(entity, showHidden: showHidden)) continue;
          final file = entity as File;

          FileStat stat;
          try {
            stat = file.statSync();
          } catch (_) {
            continue;
          }
          // Ignorar archivos vacíos / corruptos de 0 bytes
          if (stat.size == 0) continue;
          // Ya visto por otra raíz solapada: fuera duplicados.
          if (!seen.add(file.path)) continue;

          found.add(
            _FoundFile(
              path: file.path,
              created: stat.changed.millisecondsSinceEpoch,
              modified: stat.modified.millisecondsSinceEpoch,
              size: stat.size,
              isVideo: videoExtensions.contains(
                p.extension(file.path).toLowerCase(),
              ),
            ),
          );
        }
      } catch (e) {
        debugPrint('Error leyendo directorio ($dirPath): $e');
      }
    }

    final rows = <Map<String, Object>>[];
    // Lotes concurrentes: I/O en paralelo sin saturar descriptores.
    for (var i = 0; i < found.length; i += 24) {
      final batch = found.sublist(
        i,
        i + 24 > found.length ? found.length : i + 24,
      );
      final probed = await Future.wait(batch.map(_probeFound));
      rows.addAll(probed);
    }
    // El orden descendente se fija AQUÍ, dentro del isolate: ordenar los
    // mapas por un entero es barato, y evita el O(N log N) con objetos
    // DateTime en el hilo de UI al materializar.
    rows.sort(
      (a, b) => (b['modified'] as int).compareTo(a['modified'] as int),
    );
    return rows;
  }

  /// Materializa la fila de un archivo + su sonda (si es imagen).
  ///
  /// También precalcula lo derivable del nombre (título, heurísticas) y la
  /// etiqueta de ubicación: hacerlo aquí, dentro del isolate, evita
  /// repetirlo por fila en el hilo de UI al materializar los modelos.
  static Future<Map<String, Object>> _probeFound(_FoundFile file) async {
    final row = <String, Object>{
      'path': file.path,
      'title': p.basename(file.path),
      'created': file.created,
      'modified': file.modified,
      'size': file.size,
      'isVideo': file.isVideo,
      'motion': _isMotionPhoto(file.path),
      'selfie': _isSelfie(file.path),
    };
    // La sonda solo sabe leer cabeceras de imagen. Para el resto de
    // familias se guardan igualmente, pero sin dimensiones ni EXIF: en
    // un gestor de archivos el archivo está igual aunque no sepamos
    // cuánto mide su foto.
    final isImage =
        kProbeableExtensions.contains(p.extension(file.path).toLowerCase());
    if (!isImage) return row;
    try {
      final probe = await probeImageFile(file.path);
      if (probe == null) return row;
      if (probe.width != null) row['width'] = probe.width!;
      if (probe.height != null) row['height'] = probe.height!;
      if (probe.latitude != null) row['lat'] = probe.latitude!;
      if (probe.longitude != null) row['lng'] = probe.longitude!;
      final loc = _locationLabel(probe.latitude, probe.longitude);
      if (loc != null) row['loc'] = loc;
    } catch (_) {
      // Sonda best-effort: el archivo entra igual, sin metadatos.
    }
    return row;
  }

  /// Helper para validar si un archivo es válido (y oculto solo si [showHidden]).
  static bool _isValidMediaFile(
    FileSystemEntity entity, {
    bool showHidden = false,
  }) {
    if (entity is! File) return false;

    // Los puntos 2 y 3 (oculto el archivo / dentro de una carpeta oculta)
    // solo aplican si el usuario no ha pedido verlos. Con el ajuste
    // activado entran también `.thumbnails` y `.trash`, que en Android
    // guardan copias de todo lo multimedia.
    if (!showHidden) {
      // 1. Obtener el nombre del archivo
      final filename = p.basename(entity.path);

      // 2. Descartar si el archivo es oculto (empieza por '.')
      if (filename.startsWith('.')) return false;

      // 3. Descartar si está dentro de una carpeta oculta (ej. .cache, .trash, .thumbnails)
      final parts = p.split(entity.path);
      if (parts.any(
        (part) => part.startsWith('.') && part != '.' && part != '..',
      )) {
        return false;
      }
    }

    // 4. Sin filtro de extensión: en un gestor de archivos TODO archivo es
    //    un archivo. La versión galería solo aceptaba foto/vídeo, y hacía
    //    que la fila "Archivos" de Explorar no pudiera mostrar nunca un
    //    `.xyz`, un `.iso` o un binario sin extensión.
    //    La clasificación por familia la hace [kindForPath] al pintar, no
    //    al escanear, así que lo desconocido cae en [FileKind.other].
    return true;
  }
}

/// Archivo candidato hallado en la caminata (fase 1 del escaneo).
class _FoundFile {
  final String path;
  final int created;
  final int modified;
  final int size;
  final bool isVideo;

  const _FoundFile({
    required this.path,
    required this.created,
    required this.modified,
    required this.size,
    required this.isVideo,
  });
}
