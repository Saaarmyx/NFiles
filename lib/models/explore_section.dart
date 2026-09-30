// lib/models/explore_section.dart
//
// Taxonomía de la pantalla "Explorar".
//
// La lista es explícita y en orden fijo a propósito: es navegación, no una
// consulta a la base de datos. El orden va de lo más usado a lo menos, y
// "Archivos" hace de cajón para lo que no encaja en ningún grupo.
import 'package:flutter/material.dart';

import '../controllers/files_controller.dart';
import 'file_model.dart';

/// Una fila de Explorar: cómo se resuelve y cómo se muestra.
class ExploreEntry {
  final String id;
  final String title;
  final IconData icon;
  final Color tint;

  /// Subtítulo: si es `null`, se calcula como "N elementos" o "Vacía".
  final String? Function(FilesController controller)? subtitle;

  /// Los archivos a los que lleva. Vacío = destino no implementado aún.
  final List<FileModel> Function(FilesController controller) files;

  const ExploreEntry({
    required this.id,
    required this.title,
    required this.icon,
    required this.tint,
    required this.files,
    this.subtitle,
  });
}

/// Ubicación de almacenamiento: NCloud o el dispositivo.
class StorageLocation {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color tint;

  /// `false` mientras no haya backend: la fila se muestra pero avisa en vez
  /// de fingir que se puede abrir.
  final bool isRemote;

  const StorageLocation({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tint,
    this.isRemote = false,
  });
}

/// Ubicaciones de la cabecera.
const List<StorageLocation> kStorageLocations = [
  StorageLocation(
    id: 'ncloud',
    title: 'NCloud',
    subtitle: 'Sin conexión. Requiere iniciar sesión.',
    icon: Icons.cloud_outlined,
    tint: Color(0xFF14B8A6),
    isRemote: true,
  ),
  StorageLocation(
    id: 'device',
    title: 'Este dispositivo',
    subtitle: 'Almacenamiento interno',
    icon: Icons.smartphone_outlined,
    tint: Color(0xFF15803D),
  ),
];

/// Categorías por tipo. Sin título de grupo: van justo debajo de
/// Ubicaciones.
List<ExploreEntry> kTypeEntries() => [
  ExploreEntry(
    id: 'documents',
    title: 'Documentos',
    icon: Icons.description_outlined,
    tint: const Color(0xFF0EA5E9),
    files: (c) => c.documentFiles,
  ),
  ExploreEntry(
    id: 'images',
    title: 'Imágenes',
    icon: Icons.image_outlined,
    tint: const Color(0xFFEC4899),
    files: (c) => c.imageFiles,
  ),
  ExploreEntry(
    id: 'videos',
    title: 'Vídeos',
    icon: Icons.videocam_outlined,
    tint: const Color(0xFFEF4444),
    files: (c) => c.videos,
  ),
  ExploreEntry(
    id: 'music',
    title: 'Música',
    icon: Icons.music_note_outlined,
    tint: Color(0xFFF97316),
    files: (c) => c.musicFiles,
  ),
  ExploreEntry(
    id: 'files',
    title: 'Archivos',
    icon: Icons.insert_drive_file_outlined,
    tint: const Color(0xFF64748B),
    files: (c) => c.otherFiles,
  ),
  ExploreEntry(
    id: 'apks',
    title: 'APKs',
    icon: Icons.android,
    tint: Color(0xFF84CC16),
    files: (c) => c.apkFiles,
  ),
];

/// Carpetas del usuario.
List<ExploreEntry> kFolderEntries() => [
  ExploreEntry(
    id: 'downloads',
    title: 'Descargas',
    icon: Icons.download_outlined,
    tint: const Color(0xFF3B82F6),
    files: (c) => c.downloadFiles,
  ),
  ExploreEntry(
    id: 'favorites',
    title: 'Favoritos',
    icon: Icons.favorite_border,
    tint: Colors.pink,
    files: (c) => c.favoriteFiles,
  ),
];

/// Recursos del dispositivo por origen.
List<ExploreEntry> kResourceEntries() => [
  ExploreEntry(
    id: 'camera',
    title: 'Cámara',
    icon: Icons.photo_camera_outlined,
    tint: Colors.blue,
    files: (c) => c.cameraFiles,
  ),
  ExploreEntry(
    id: 'screenshots',
    title: 'Capturas',
    icon: Icons.screenshot_monitor_outlined,
    tint: Colors.purple,
    files: (c) => c.screenshotFiles,
  ),
  ExploreEntry(
    id: 'recorder',
    title: 'Grabaciones',
    icon: Icons.mic_none_outlined,
    tint: const Color(0xFF22C55E),
    files: (c) => c.recorderFiles,
  ),
];

/// Un grupo con título dentro de Explorar.
class ExploreGroup {
  final String? title;
  final List<ExploreEntry> entries;

  const ExploreGroup({required this.title, required this.entries});
}

/// Los tres grupos, en el orden pedido.
List<ExploreGroup> exploreGroups() => [
  ExploreGroup(title: null, entries: kTypeEntries()),
  ExploreGroup(title: 'Carpetas', entries: kFolderEntries()),
  ExploreGroup(title: 'Recursos', entries: kResourceEntries()),
];
