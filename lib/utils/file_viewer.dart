import 'package:flutter/material.dart';
import 'package:NexoraUi/NexoraUi.dart';
import 'package:share_plus/share_plus.dart';

import '../controllers/files_controller.dart';
import '../models/file_model.dart';
import '../screens/files/file_viewer_screen.dart';

/// Abre el visor de pantalla completa sobre cualquier lista de archivos.
///
/// Úsalo desde cualquier screen (explorador, álbumes, colecciones, etc.):
/// ```dart
/// onTap: () => openFileViewer(
///   context,
///   controller: controller,
///   files: album.files,
///   initialId: file.id,
/// ),
/// ```
/// Comparte varios archivos/vídeos a la vez.
///
/// Si el sistema no admite selección múltiple, cae a archivos de uno en
/// uno para no perder la acción.
Future<void> shareFiles(
  BuildContext context,
  List<FileModel> files,
) async {
  if (files.isEmpty) return;
  // `xFiles` y no `files`: el nombre lo ocupa el parametro de dominio.
  final xFiles = [for (final file in files) XFile(file.path)];
  try {
    await SharePlus.instance.share(
      ShareParams(
        files: xFiles,
        subject: files.length == 1 ? files.first.title : 'NFiles',
      ),
    );
  } catch (_) {
    // Algunos SHARE_SHEET no aceptan N archivos: se comparten de a uno.
    for (final xFile in xFiles) {
      try {
        await SharePlus.instance.share(ShareParams(files: [xFile]));
      } catch (_) {
        break;
      }
    }
  }
}

Future<void> openFileViewer(
  BuildContext context, {
  required FilesController controller,
  required List<FileModel> files,
  int initialIndex = 0,
  String? initialId,
}) {
  if (files.isEmpty) return Future.value();
  var index = initialIndex;
  if (initialId != null) {
    final found = files.indexWhere((p) => p.id == initialId);
    if (found != -1) index = found;
  }
  return pushNPage<void>(
    context,
    FileViewerScreen(
      controller: controller,
      initialIndex: index.clamp(0, files.length - 1),
      filesOverride: files,
    ),
  );
}
