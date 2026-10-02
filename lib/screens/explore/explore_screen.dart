// lib/screens/explore/explore_screen.dart
//
// Pantalla "Explorar": dónde está cada cosa, en cuatro bloques.
//
// Estructura, de arriba abajo:
//   Almacenamiento → NCloud + Mi Teléfono (medidor X / Y GB por fila)
//   Acceso Rápido  → Descargas + Favoritos (solo si hay)
//   Categorías     → documentos, hojas, presentaciones, comprimidos,
//                    imágenes, vídeos, música, archivos, apks
//   Recursos       → cámara, capturas, NRecorder (deshabilitado),
//                    Instagram, WhatsApp
//
// Cada bloque va en [NGroupedCardContainer] del kit: una tarjeta por
// sección en vez de una lista corrida. La estética de las filas es la de
// las tarjetas del kit (icono en cuadro tintado + título + subtítulo +
// chevron) para que la lista se lea de un vistazo sin abrir nada.
//
// ## La regla de lo vacío
//
// Una categoría con 0 elementos no se pinta, y si un grupo se queda sin
// filas tampoco se pinta su título. Nueve tarjetas que llevan a "Nada por
// aquí" son Worse que ninguna: obligan a leerlas todas para encontrar la
// única que tiene algo. Lo que no cambia nunca es el bloque de
// almacenamiento (siemprehay algo que medir) y NRecorder, que es un
// marcador de lo que viene y no una categoría.
//
// Cuando no queda nada se dice con [NEmptyState] en vez de dejar la
// pantalla a medio vacía: sin archivos, casi siempre es el permiso.
import 'package:flutter/material.dart';
import 'package:NexoraCore/NexoraCore.dart';
import 'package:NexoraUi/NexoraUi.dart';

import '../../controllers/files_controller.dart';
import '../../models/explore_section.dart';
import '../../models/file_model.dart';
import '../listing/file_listing_screen.dart';

/// Una fila de Explorar con sus archivos ya resueltos.
///
/// Se resuelven UNA vez y se pasan a la fila: `entry.files(controller)`
/// filtra la biblioteca entera, y llamarlo dos veces por fila (una para
/// decidir si se muestra y otra para pintar) duplicaba el paseo en cada
/// rebuild de la pantalla.
class _ResolvedEntry {
  final ExploreEntry entry;
  final List<FileModel> files;

  const _ResolvedEntry(this.entry, this.files);
}

/// Filtra las entradas con contenido y resuelve sus archivos de paso.
List<_ResolvedEntry> _resolveEntries(
  List<ExploreEntry> entries,
  FilesController controller,
) {
  final out = <_ResolvedEntry>[];
  for (final entry in entries) {
    final files = entry.files(controller);
    // Las deshabilitadas se quedan siempre: son marcadores, y su
    // subtítulo ya dice "Próximamente".
    if (!entry.enabled && files.isEmpty) {
      out.add(_ResolvedEntry(entry, files));
      continue;
    }
    if (files.isEmpty) continue;
    out.add(_ResolvedEntry(entry, files));
  }
  return out;
}

class ExploreScreen extends StatelessWidget {
  final FilesController controller;

  const ExploreScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (controller.state == FilesState.loading ||
            controller.state == FilesState.initial) {
          return const Center(child: NLoader(size: 44));
        }
        final quick = _resolveEntries(kQuickEntries(), controller);
        final types = _resolveEntries(kTypeEntries(), controller);
        final resources = _resolveEntries(kResourceEntries(), controller);
        // "Vacío" es que no hay NINGÚN archivo detrás de ninguna fila, no
        // que no haya filas: NRecorder siempre está y no cuenta.
        final hayArchivos = [
          ...quick,
          ...types,
          ...resources,
        ].any((resolved) => resolved.files.isNotEmpty);
        return ListView(
          padding: const EdgeInsets.only(bottom: NSpacing.spaceXl),
          children: [
            const _GroupTitle('Almacenamiento'),
            _StorageBlock(controller: controller),
            if (!hayArchivos) ...[
              const SizedBox(height: NSpacing.spaceMd),
              const _NothingToShow(),
            ],
            _group('Acceso Rápido', quick),
            _group('Categorías', types),
            _group('Recursos', resources),
            const SizedBox(height: NSpacing.spaceSm),
          ],
        );
      },
    );
  }

  /// Título + tarjeta, o nada si el grupo se quedó sin filas.
  Widget _group(String title, List<_ResolvedEntry> entries) {
    if (entries.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: NSpacing.spaceSm),
        _GroupTitle(title),
        _GroupCard(entries: entries, controller: controller),
      ],
    );
  }
}

/// Lo que se ve cuando no hay ni una categoría con contenido.
class _NothingToShow extends StatelessWidget {
  const _NothingToShow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: NSpacing.spaceMd),
      child: NGroupedCardContainer(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: NSpacing.spaceMd,
              vertical: NSpacing.spaceSm,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.folder_open_outlined,
                  size: 20,
                  color: context.nMutedTextColor,
                ),
                const SizedBox(width: NSpacing.spaceSm),
                Expanded(
                  child: Text(
                    'No hay archivos en el almacenamiento',
                    style: TextStyle(
                      fontFamily: NTypography.fontFamilyBase,
                      fontSize: NTypography.sizeSm,
                      color: context.nMutedTextColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bloque "Almacenamiento": NCloud + Mi Teléfono con medidor por fila.
///
/// La tarjeta respira con el mismo margen que el resto de bloques: pegada
/// al borde se lee como un error de layout, no como una sección.
class _StorageBlock extends StatelessWidget {
  final FilesController controller;

  const _StorageBlock({required this.controller});

  static const _gb = 1024 * 1024 * 1024;

  @override
  Widget build(BuildContext context) {
    // `statvfs` son microsegundos: lectura síncrona al pintar, sin esperar
    // al escaneo. Sin motor, la fila sale en ceros como "sin medir".
    final info = StorageService.quick(StorageService.defaultMount());
    final accent = NOptionTileColors.accentOf(context);

    NStorageSpecTile tile(StorageLocation location) {
      final isRemote = location.isRemote;
      return NStorageSpecTile(
        icon: location.icon,
        color: accent,
        title: location.title,
        usedGb: isRemote ? 0 : (info?.usedBytes ?? 0) / _gb,
        totalGb: isRemote ? 0 : (info?.totalBytes ?? 0) / _gb,
        onTap: () => _onLocationTap(context, location),
      );
    }

    final locations = kStorageLocations;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: NSpacing.spaceMd),
      child: NGroupedCardContainer(
        children: [for (final location in locations) tile(location)],
      ),
    );
  }

  void _onLocationTap(BuildContext context, StorageLocation location) {
    // NCloud todavía no tiene backend. Se declara en vez de abrir una
    // pantalla vacía: prometer algo que no existe es peor que decir que
    // falta.
    if (location.isRemote) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('NCloud: todavía no disponible')),
        );
      return;
    }
    pushNPage(
      context,
      FileListingScreen(
        controller: controller,
        title: 'Mi Teléfono',
        icon: location.icon,
        files: controller.visibleFiles,
      ),
    );
  }
}

/// Título de grupo ("Almacenamiento", "Acceso Rápido", ...).
class _GroupTitle extends StatelessWidget {
  final String title;

  const _GroupTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NSpacing.spaceMd,
        NSpacing.spaceSm,
        NSpacing.spaceMd,
        NSpacing.space2xs,
      ),
      child: NSectionLabel(
        title: title,
        color: context.nMutedTextColor,
      ),
    );
  }
}

/// Tarjeta de un grupo de entradas, con aire a los bordes.
class _GroupCard extends StatelessWidget {
  final List<_ResolvedEntry> entries;
  final FilesController controller;

  const _GroupCard({required this.entries, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: NSpacing.spaceMd),
      child: NGroupedCardContainer(
        children: [
          for (final resolved in entries)
            _EntryTile(resolved: resolved, controller: controller),
        ],
      ),
    );
  }
}

/// Fila: icono con el acento de la app + título + subtítulo + chevron.
///
/// Todos los iconos comparten el acento: el color ya no distingue
/// familias, solo marca que la fila es tocable. Las deshabilitadas
/// (NRecorder) se pintan atenuadas y sin navegación: un marcador de lo
/// que viene no puede llevar a una categoría vacía.
class _EntryTile extends StatelessWidget {
  final _ResolvedEntry resolved;
  final FilesController controller;

  const _EntryTile({required this.resolved, required this.controller});

  @override
  Widget build(BuildContext context) {
    final entry = resolved.entry;
    final files = resolved.files;
    final count = files.length;
    final subtitle = entry.subtitle?.call(controller) ??
        (count == 0 ? 'Vacía' : '$count ${count == 1 ? 'elemento' : 'elementos'}');
    final muted = context.nMutedTextColor;
    final accent = NOptionTileColors.accentOf(context);

    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NSpacing.spaceMd,
        vertical: NSpacing.spaceSm,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(entry.icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: NSpacing.spaceSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: NTypography.fontFamilyBase,
                    fontWeight: NTypography.weightSemibold,
                    fontSize: NTypography.sizeMd,
                    color: context.nPrimaryTextColor,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: NTypography.fontFamilyBase,
                    fontSize: NTypography.sizeXs,
                    color: muted,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 20, color: muted),
        ],
      ),
    );

    if (!entry.enabled) return Opacity(opacity: 0.6, child: row);
    return InkWell(
      onTap: () => pushNPage(
        context,
        FileListingScreen(
          controller: controller,
          title: entry.title,
          icon: entry.icon,
          files: files,
        ),
      ),
      child: row,
    );
  }
}
