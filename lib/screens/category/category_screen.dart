// lib/screens/category/category_screen.dart
//
// Contenido de una categoría de Explorar (Documentos, Imágenes, Música,
// Favoritos, Cámara...).
//
// UNA sola pantalla genérica para todas. Antes cada categoría tenía la
// suya (FavoritesScreen, VideosScreen...) y eran el mismo `GridView` con un
// título distinto: cualquier cambio de comportamiento había que replicarlo
// N veces. Aquí la lista llega ya filtrada y solo cambia el título.
import 'package:flutter/material.dart';
import 'package:NexoraUi/NexoraUi.dart';

import '../../controllers/files_controller.dart';
import '../../models/file_model.dart';
import '../../utils/file_viewer.dart';
import '../../widgets/file_row.dart';
import '../../widgets/file_tile.dart';

class CategoryScreen extends StatelessWidget {
  final FilesController controller;

  final String title;
  final IconData icon;

  /// Archivos de la categoría, ya filtrados por quien la abre.
  final List<FileModel> files;

  /// Agrupa por subcarpeta (lugar de guardado). Solo tiene efecto en
  /// cuadrícula: en lista el `FileRow` ya muestra la carpeta.
  final bool groupByFolder;

  const CategoryScreen({
    super.key,
    required this.controller,
    required this.title,
    required this.icon,
    required this.files,
    this.groupByFolder = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: NSecondaryTopBar(title: title),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          if (files.isEmpty) {
            return NEmptyState(
              icon: icon,
              title: 'Nada por aquí',
              subtitle: 'No hay archivos en $title.',
            );
          }
          return controller.categoryLayout == CategoryLayout.list
              ? _buildList(context)
              : _buildGrid(context);
        },
      ),
    );
  }

  List<FileModel> _sorted(FilesController controller) =>
      controller.applyCategorySort(files);

  Widget _buildList(BuildContext context) {
    final sorted = _sorted(controller);
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: NSpacing.spaceXl),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final file = sorted[index];
        return FileRow(
          file: file,
          onTap: () => openFileViewer(
            context,
            controller: controller,
            files: sorted,
            initialId: file.id,
          ),
        );
      },
    );
  }

  Widget _buildGrid(BuildContext context) {
    final sorted = _sorted(controller);
    if (!groupByFolder) return _gridOf(context, sorted, null);

    // Agrupado por "lugar de guardado": en un gestor de archivos saber
    // dónde está cada cosa es tan útil como saber qué es.
    final byFolder = <String, List<FileModel>>{};
    for (final file in sorted) {
      byFolder.putIfAbsent(file.folderName, () => []).add(file);
    }
    final folders = byFolder.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.only(bottom: NSpacing.spaceXl),
      children: [
        for (final folder in folders) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NSpacing.spaceMd,
              NSpacing.spaceMd,
              NSpacing.spaceMd,
              NSpacing.space2xs,
            ),
            child: NSectionLabel(
              title: folder,
              color: context.nMutedTextColor,
            ),
          ),
          _gridOf(context, byFolder[folder]!, folder),
        ],
      ],
    );
  }

  Widget _gridOf(BuildContext context, List<FileModel> list, String? folder) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
        ),
        itemCount: list.length,
        itemBuilder: (context, index) {
          final file = list[index];
          return GestureDetector(
            onTap: () => openFileViewer(
              context,
              controller: controller,
              files: list,
              initialId: file.id,
            ),
            child: FileTile(file: file, path: file.path),
          );
        },
      ),
    );
  }
}
