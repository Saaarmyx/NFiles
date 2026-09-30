// lib/widgets/file_row.dart
//
// Fila de archivo del gestor: icono + nombre + peso · lugar de guardado.
//
// Es la unidad visual de "Recientes" y de las categorías. Deliberadamente
// NO es una miniatura: en un gestor de archivos conviven PDF, MP3 y APK,
// y una rejilla de miniaturas solo funciona para imágenes. El prefijo del
// nombre en gris da el matiz de cada tipo sin Portraites/Mountain variantes.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:NexoraUi/NexoraUi.dart';

import 'package:NexoraCore/NexoraCore.dart';
import '../models/file_model.dart';

/// Fila de un archivo.
class FileRow extends StatelessWidget {
  final FileModel file;

  /// Estado seleccionado (multiselección). `null` = sin selección.
  final bool? selected;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const FileRow({
    super.key,
    required this.file,
    this.selected,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final inSelection = selected != null;
    final muted = context.nMutedTextColor;
    final accent = NOptionTileColors.accentOf(context);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        // padding: EdgeInsets.zero,
        decoration: BoxDecoration(
          color: inSelection && selected == true
              ? accent.withValues(alpha: 0.10)
              : null,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const SizedBox(width: NSpacing.spaceMd),
            _FileIconTile(
              path: file.path,
              isVideo: file.isVideo,
              selected: selected,
            ),
            const SizedBox(width: NSpacing.spaceSm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    file.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: NTypography.fontFamilyBase,
                      fontWeight: NTypography.weightSemibold,
                      fontSize: NTypography.sizeMd,
                      color: context.nPrimaryTextColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    // "peso · lugar de guardado"
                    '${file.formattedSize} · ${file.folderName}',
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
            if (file.isFavorite)
              Padding(
                padding: const EdgeInsets.only(left: NSpacing.space2xs),
                child: Icon(Icons.favorite, size: 15, color: Colors.red),
              ),
            if (!inSelection)
              Icon(Icons.chevron_right, size: 20, color: muted),
            const SizedBox(width: NSpacing.spaceSm),
          ],
        ),
      ),
    );
  }
}

/// Cuadro de icono a la izquierda de la fila.
///
/// Las imágenes y vídeos sí muestran miniatura real (es lo que el usuario
/// espera ver); el resto muestra el icono de su familia, para no intentar
/// decodificar un PDF o un APK.
class _FileIconTile extends StatelessWidget {
  final String path;
  final bool isVideo;
  final bool? selected;

  const _FileIconTile({
    required this.path,
    required this.isVideo,
    required this.selected,
  });

  static const _size = 44.0;

  @override
  Widget build(BuildContext context) {
    final isMedia = isVideo || kindForPath(path) == FileKind.image;

    Widget child;
    if (!isMedia) {
      child = Icon(
        iconForPath(path),
        size: 22,
        color: NOptionTileColors.accentOf(context),
      );
    } else {
      child = Image.file(
        File(path),
        fit: BoxFit.cover,
        width: _size,
        height: _size,
        errorBuilder: (context, _, _) =>
            Icon(iconForPath(path), size: 22, color: context.nMutedTextColor),
      );
    }

    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: child,
          ),
          if (selected != null)
            NSelectionOverlay(selected: selected!),
        ],
      ),
    );
  }
}
