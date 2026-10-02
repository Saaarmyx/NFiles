// lib/screens/recent/recents_screen.dart
//
// Pantalla inicial: archivos recientes, del más nuevo al más viejo.
// Renderiza con [NRecentFileCard] del kit: icono o miniatura + nombre +
// peso • origen, agrupados por día en [NGroupedCardContainer].
//
// Un solo `CustomScrollView` con una cabecera por día ("Hoy • N
// elementos") y su tarjeta de grupo. El colapso de cada día vive en el
// State, no en el controlador: es estado efímero de la vista, y al
// recargar no debe perderlo ni reiniciarlo.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:NexoraCore/NexoraCore.dart';
import 'package:NexoraUi/NexoraUi.dart';

import '../../controllers/files_controller.dart';
import '../../models/file_model.dart';
import '../files/file_preview_screen.dart';
import '../../widgets/day_header.dart';

/// Un día de la pantalla: su clave (día natural) y sus archivos.
class _DayGroup {
  final DateTime day;
  final List<FileModel> files;

  const _DayGroup(this.day, this.files);

  /// "Hoy", "Ayer", "Hace 3 días", y a partir de una semana la fecha.
  String get label {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    return switch (diff) {
      0 => 'Hoy',
      1 => 'Ayer',
      < 7 => 'Hace $diff días',
      _ => '${day.day}/${day.month}/${day.year}',
    };
  }
}

class RecentsScreen extends StatefulWidget {
  final FilesController controller;

  const RecentsScreen({super.key, required this.controller});

  @override
  State<RecentsScreen> createState() => _RecentsScreenState();
}

class _RecentsScreenState extends State<RecentsScreen> {
  /// Días plegados por el usuario. Clave: `yyyy-mm-dd`.
  final Set<String> _collapsed = {};

  /// Petición de miniaturas en curso, para no abrir un isolate por build.
  Future<void>? _thumbTask;

  /// Providers ya creados por miniatura: identidad estable entre rebuilds
  /// para que la imagen no se recargue (y parpadee) en cada filtro.
  final Map<String, ImageProvider> _thumbProviders = {};

  /// Pide las miniaturas UNA vez por conjunto, nunca durante el pintado.
  ///
  /// Se piden para todo lo visible y no solo para lo que cabe en pantalla:
  /// el `SliverList.builder` construye bajo demanda, así que pedir solo lo
  /// visible dejaría esperando a las fichas de más abajo. El controlador
  /// avisa al terminar y las fichas aparecen solas.
  void _ensureThumbnails(List<_DayGroup> groups) {
    final paths = [
      for (final g in groups)
        for (final f in g.files) f.path,
    ];
    if (paths.isEmpty) return;
    _thumbTask ??= widget.controller
        .ensureThumbnails(paths)
        .then((_) => _thumbTask = null);
  }

  /// Miniatura de [file] para la card: la generada por el motor si ya
  /// existe, y si no el archivo original cuando es imagen o vídeo.
  ///
  /// Sin miniatura de ningún tipo devuelve `null` y la card cae al icono
  /// de familia. Los providers se memoizan por ruta para una identidad
  /// estable entre rebuilds: recrearlos parpadearía la lista en cada
  /// filtro o recarga.
  ImageProvider? _thumbOf(FileModel file) {
    final cached = widget.controller.thumbnailFor(file.path);
    if (cached != null) {
      return _thumbProviders.putIfAbsent(
        'gen:$cached',
        () => FileImage(File(cached)),
      );
    }
    final isMedia =
        file.isVideo || kindForPath(file.path) == FileKind.image;
    if (!isMedia) return null;
    return _thumbProviders.putIfAbsent(
      'orig:${file.path}',
      () => FileImage(File(file.path)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final groups = _groupsOf(controller);

        return switch (controller.state) {
          FilesState.initial ||
          FilesState.loading => groups.isEmpty
              ? const Center(child: NLoader(size: 44))
              : _buildList(groups),
          FilesState.permissionDenied => NPermissionDeniedView(
            icon: Icons.folder_off_outlined,
            title: 'Permiso necesario',
            message: 'Se requiere permiso para leer tus archivos',
            actionLabel: 'Conceder permiso',
            // Reintenta medios y, si sigue denegado, abre los Ajustes del
            // sistema para "Acceso a todos los archivos".
            onAction: controller.resolveStorageAccess,
          ),
          FilesState.error => NErrorView(
            message: controller.errorMessage ?? 'Error al leer los archivos',
            retryLabel: 'Reintentar',
            onRetry: controller.fetchFiles,
          ),
          FilesState.loaded => groups.isEmpty
              ? NEmptyState(
                  icon: Icons.folder_open_outlined,
                  title: 'Sin archivos',
                  subtitle: _emptyHint(controller),
                )
              : _buildList(groups),
        };
      },
    );
  }

  String _emptyHint(FilesController controller) {
    if (controller.searchQuery.isNotEmpty) {
      return 'Prueba con otra búsqueda.';
    }
    return 'No hay archivos en las carpetas vigiladas.';
  }

  /// Agrupa por día natural, del más nuevo al más viejo.
  ///
  /// Solo lo de los últimos 7 días ([FilesController.recentFiles]): lo
  /// anterior no es "reciente" y tampoco pide miniaturas.
  List<_DayGroup> _groupsOf(FilesController controller) {
    final byDay = <DateTime, List<FileModel>>{};
    for (final file in controller.recentFiles) {
      final day = controller.dayKeyOf(file);
      byDay.putIfAbsent(day, () => []).add(file);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    return [for (final day in days) _DayGroup(day, byDay[day]!)];
  }

  static String _keyOf(DateTime day) =>
      '${day.year}-${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  Widget _buildList(List<_DayGroup> groups) {
    _ensureThumbnails(groups);

    // Compacto oculta la cabecera de texto, pero mantiene una tarjeta de
    // grupo por día: los días siguen separados visualmente.
    final byDate = widget.controller.viewMode == FilesViewMode.byDate;

    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: NSpacing.spaceXs)),
        for (final group in groups) ...[
          if (byDate)
            SliverToBoxAdapter(
              child: DayHeader(
                label: group.label,
                count: group.files.length,
                collapsed: _collapsed.contains(_keyOf(group.day)),
                onToggleCollapsed: () => setState(() {
                  final key = _keyOf(group.day);
                  if (!_collapsed.remove(key)) _collapsed.add(key);
                }),
              ),
            ),
          if (!byDate || !_collapsed.contains(_keyOf(group.day)))
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  NSpacing.spaceMd,
                  NSpacing.space2xs,
                  NSpacing.spaceMd,
                  NSpacing.spaceSm,
                ),
                child: NGroupedCardContainer(
                  children: [
                    for (final file in group.files)
                      _RecentCard(
                        file: file,
                        files: group.files,
                        controller: widget.controller,
                        thumbnail: _thumbOf(file),
                      ),
                  ],
                ),
              ),
            ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: NSpacing.spaceXl)),
      ],
    );
  }
}

/// Card de un archivo reciente: resuelve icono, miniatura, título y
/// subtítulo del modelo y delega el tap al visor. El kit solo pinta.
class _RecentCard extends StatelessWidget {
  final FileModel file;
  final List<FileModel> files;
  final FilesController controller;
  final ImageProvider? thumbnail;

  const _RecentCard({
    required this.file,
    required this.files,
    required this.controller,
    this.thumbnail,
  });

  @override
  Widget build(BuildContext context) {
    return NRecentFileCard(
      icon: iconForPath(file.path),
      thumbnail: thumbnail,
      title: file.displayNameFor(controller.showFileExtensions),
      subtitle: '${file.formattedSize} • ${file.folderName}',
      // Mismo enrutado que en Explorar: decide el visor.
      onTap: () => openFilePreview(
        context,
        controller: controller,
        file: file,
        files: files,
      ),
    );
  }
}
