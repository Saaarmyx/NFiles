// lib/utils/confirm_destructive.dart
//
// Confirmación de acciones destructivas, respetando el ajuste
// "Confirmar al eliminar" (`FilesController.confirmDelete`).
//
// ## Por qué vive aquí y no en el visor
//
// Estaba dentro de `file_viewer_screen.dart`, que era el único sitio que
// borraba algo. En cuanto el borrado aparece en dos sitios (visor,
// selección múltiple, papelera) importar la función desde la pantalla del
// visor era una dependencia sin sentido: un widget de una pantalla
// decidiendo el borrado de otra. Aquí vive al lado del resto de
// decisiones transversales.
//
// ## El ajuste
//
// Con `confirmDelete` en `true` (el valor por defecto) se pregunta, que es
// lo que se espera antes de perder un archivo. Con `false` la acción va
// directa: quien lo apaga sabe lo que hace y volver a preguntarle es
// ruido. El diálogo es el del kit ([showNConfirmDialog], que es
// [showNModal] con el chrome de la app), así que el respectar el
// rendimiento no se pierde por el camino.
import 'package:flutter/material.dart';
import 'package:NexoraUi/NexoraUi.dart';

import '../controllers/files_controller.dart';

/// Confirma una acción destructiva, o la da por buena si el ajuste dice
/// que no hay que preguntar.
///
/// Devuelve `true` para ejecutar. Con el ajuste apagado devuelve `true`
/// sin abrir nada, así que quien llama puede escribir el mismo código en
/// los dos casos:
///
/// ```dart
/// if (!await confirmDestructive(
///   context,
///   controller: controller,
///   title: 'Mover a la papelera',
///   message: 'Podrás restaurarla desde la papelera.',
/// )) return;
/// await controller.moveToTrash(file.id);
/// ```
Future<bool> confirmDestructive(
  BuildContext context, {
  required FilesController controller,
  required String title,
  required String message,
  IconData? icon,
  String confirmLabel = 'Eliminar',
}) async {
  if (!controller.confirmDelete) return true;
  return showNConfirmDialog(
    context,
    title: title,
    message: message,
    confirmLabel: confirmLabel,
    isDestructive: true,
    icon: icon,
  );
}
