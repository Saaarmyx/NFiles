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

  /// `false` = marcador deshabilitado (p. ej. NRecorder): se pinta sin
  /// navegación, con su subtítulo de estado. Nunca finge llevar a algo.
  final bool enabled;

  /// Subtítulo: si es `null`, se calcula como "N elementos" o "Vacía".
  final String? Function(FilesController controller)? subtitle;

  /// Los archivos a los que lleva. Vacío = destino no implementado aún.
  final List<FileModel> Function(FilesController controller) files;

  const ExploreEntry({
    required this.id,
    required this.title,
    required this.icon,
    required this.files,
    this.subtitle,
    this.enabled = true,
  });
}

/// Ubicación de almacenamiento: NCloud o el dispositivo.
class StorageLocation {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;

  /// `false` mientras no haya backend: la fila se muestra pero avisa en vez
  /// de fingir que se puede abrir.
  final bool isRemote;

  const StorageLocation({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
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
    isRemote: true,
  ),
  StorageLocation(
    id: 'device',
    title: 'Mi Teléfono',
    subtitle: 'Almacenamiento interno',
    icon: Icons.smartphone_outlined,
  ),
];

/// Categorías por tipo. Sin título de grupo: van justo debajo de
/// Ubicaciones.
List<ExploreEntry> kTypeEntries() => [
  ExploreEntry(
    id: 'documents',
    title: 'Documentos',
    icon: Icons.description_outlined,
    files: (c) => c.documentFiles,
  ),
  // Hojas y presentaciones tienen categoría propia desde que el sniffer
  // las distingue por el contenido del ZIP y no por la extensión. Antes
  // estaban dentro de "Documentos" y no había forma de llegar a un Excel
  // sin recorrerlos todos.
  ExploreEntry(
    id: 'spreadsheets',
    title: 'Hojas de cálculo',
    icon: Icons.table_chart_outlined,
    files: (c) => c.spreadsheetFiles,
  ),
  ExploreEntry(
    id: 'presentations',
    title: 'Presentaciones',
    icon: Icons.slideshow_outlined,
    files: (c) => c.presentationFiles,
  ),
  ExploreEntry(
    id: 'archives',
    title: 'Comprimidos',
    icon: Icons.folder_zip_outlined,
    files: (c) => c.archiveFiles,
  ),
  ExploreEntry(
    id: 'images',
    title: 'Imágenes',
    icon: Icons.image_outlined,
    files: (c) => c.imageFiles,
  ),
  ExploreEntry(
    id: 'videos',
    title: 'Vídeos',
    icon: Icons.videocam_outlined,
    files: (c) => c.videos,
  ),
  ExploreEntry(
    id: 'music',
    title: 'Música',
    icon: Icons.music_note_outlined,
    files: (c) => c.musicFiles,
  ),
  ExploreEntry(
    id: 'files',
    title: 'Archivos',
    icon: Icons.insert_drive_file_outlined,
    files: (c) => c.otherFiles,
  ),
  ExploreEntry(
    id: 'apks',
    title: 'APKs',
    icon: Icons.android,
    files: (c) => c.apkFiles,
  ),
];

/// Acceso rápido: descargas siempre, favoritos solo si hay.
/// La condición la pone la pantalla (`favoriteFiles.isNotEmpty`).
List<ExploreEntry> kQuickEntries() => [
  ExploreEntry(
    id: 'downloads',
    title: 'Descargas',
    icon: Icons.download_outlined,
    files: (c) => c.downloadFiles,
  ),
  ExploreEntry(
    id: 'favorites',
    title: 'Favoritos',
    icon: Icons.favorite_border,
    files: (c) => c.favoriteFiles,
  ),
];

/// Recursos del dispositivo por origen.
///
/// NRecorder va deshabilitado a propósito: es un marcador de la función
/// que viene, no una carpeta. Sin `enabled: false` llevaría a una
/// categoría vacía que promete algo que no existe.
List<ExploreEntry> kResourceEntries() => [
  ExploreEntry(
    id: 'camera',
    title: 'Cámara',
    icon: Icons.photo_camera_outlined,
    files: (c) => c.cameraFiles,
  ),
  ExploreEntry(
    id: 'screenshots',
    title: 'Capturas',
    icon: Icons.screenshot_monitor_outlined,
    files: (c) => c.screenshotFiles,
  ),
  ExploreEntry(
    id: 'nrecorder',
    title: 'NRecorder',
    icon: Icons.mic_none_outlined,
    files: (_) => const [],
    subtitle: (_) => 'Próximamente',
    enabled: false,
  ),
  ExploreEntry(
    id: 'instagram',
    title: 'Instagram',
    icon: Icons.photo_library_outlined,
    files: (c) => c.instagramFiles,
  ),
  ExploreEntry(
    id: 'whatsapp',
    title: 'WhatsApp',
    icon: Icons.chat_outlined,
    files: (c) => c.whatsappFiles,
  ),
];
