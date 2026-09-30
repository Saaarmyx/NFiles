// lib/models/file_model.dart
import 'package:path/path.dart' as p;

class FileModel {
  final String id;
  final String path;
  final String? thumbnailPath;
  final String title;
  final DateTime dateCreated;
  final DateTime dateModified;
  final int sizeInBytes;
  final bool isFavorite;
  final bool isVideo;
  final int? width;
  final int? height;

  /// Duración solo para vídeos. Null si aún no se resolvió (badge genérico).
  final Duration? duration;

  /// Archivo animado / motion photo (p. ej. MVIMG, motion).
  final bool isMotionPhoto;

  /// Selfie / cámara frontal (heurística por nombre/carpeta).
  final bool isSelfie;

  /// GPS EXIF en decimal. Null = el archivo no trae ubicación.
  final double? latitude;
  final double? longitude;

  /// Etiqueta geográfica legible (ciudad, lugar). Nunca la ruta de archivo.
  /// Null = ubicación desconocida (el visor la oculta).
  final String? locationLabel;

  const FileModel({
    required this.id,
    required this.path,
    this.thumbnailPath,
    required this.title,
    required this.dateCreated,
    required this.dateModified,
    required this.sizeInBytes,
    this.isFavorite = false,
    this.isVideo = false,
    this.width,
    this.height,
    this.duration,
    this.isMotionPhoto = false,
    this.isSelfie = false,
    this.latitude,
    this.longitude,
    this.locationLabel,
  });

  /// True cuando el EXIF trae GPS válido.
  bool get hasLocation => latitude != null && longitude != null;

  /// Carpeta que lo contiene: el "lugar de guardado" de la fila.
  ///
  /// OJO: NO es [locationLabel]. Ese es la etiqueta geográfica (EXIF);
  /// esta es dónde está guardado el archivo. En un explorador la fila
  /// muestra "DCIM" o "Descargas", no `/storage/emulated/0/DCIM`.
  String get folderName => p.basename(p.dirname(path));

  /// `'12,4 MB'`. Formato español: coma decimal y espacio de millar.
  String get formattedSize => formatBytes(sizeInBytes);

  /// `'imagen.png'`: nombre con extensión, como lo ve el usuario.
  String get displayName => title;

  /// Extensión en minúsculas con punto, o cadena vacía si no tiene.
  String get extension => p.extension(path).toLowerCase();

  /// Tamaño legible, en español.
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '—';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    // Sin decimales si el valor es redondo (1 GB, no "1,0 GB") o si ya
    // es grande (12 MB, no "12,3 MB"). Con uno solo por debajo de 10.
    final whole = value == value.roundToDouble();
    final digits = (whole || value >= 10) ? 0 : 1;
    return '${value.toStringAsFixed(digits).replaceAll('.', ',')} ${units[unit]}';
  }

  /// Megapíxeles cuando hay dimensiones, null si se desconocen.
  double? get megapixels {
    if (width == null || height == null) return null;
    return width! * height! / 1000000.0;
  }

  /// Alta definición: +50MP o 8K aprox. Solo archivos.
  bool get isHighResolution {
    if (isVideo) return false;
    final mp = megapixels;
    if (mp != null) return mp >= 50.0;
    // Sin dimensiones no se afirma HD (evita badges falsos).
    return false;
  }

  /// 'mm:ss' para el badge inferior central de vídeos.
  String? get formattedDuration {
    final d = duration;
    if (!isVideo || d == null) return null;
    final totalSeconds = d.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  FileModel copyWith({
    String? id,
    String? path,
    String? thumbnailPath,
    String? title,
    DateTime? dateCreated,
    DateTime? dateModified,
    int? sizeInBytes,
    bool? isFavorite,
    bool? isVideo,
    int? width,
    int? height,
    Duration? duration,
    bool? isMotionPhoto,
    bool? isSelfie,
    double? latitude,
    double? longitude,
    String? locationLabel,
  }) {
    return FileModel(
      id: id ?? this.id,
      path: path ?? this.path,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      title: title ?? this.title,
      dateCreated: dateCreated ?? this.dateCreated,
      dateModified: dateModified ?? this.dateModified,
      sizeInBytes: sizeInBytes ?? this.sizeInBytes,
      isFavorite: isFavorite ?? this.isFavorite,
      isVideo: isVideo ?? this.isVideo,
      width: width ?? this.width,
      height: height ?? this.height,
      duration: duration ?? this.duration,
      isMotionPhoto: isMotionPhoto ?? this.isMotionPhoto,
      isSelfie: isSelfie ?? this.isSelfie,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationLabel: locationLabel ?? this.locationLabel,
    );
  }
}
