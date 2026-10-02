// lib/widgets/folder_view_settings_popup.dart
//
// Menú ⋮ de vista y orden de un listado de archivos (carpetas y
// categorías): modo (cuadrícula / lista), campo de ordenación (nombre,
// tamaño, fecha, tipo) y dirección (ascendente / descendente).
//
// Las marcas se leen del controlador al ABRIR el menú (`itemBuilder` se
// ejecuta entonces), así que siempre reflejan lo vigente sin suscripciones.
import 'package:flutter/material.dart';

import '../controllers/files_controller.dart';
import 'nfiles_popup.dart';

/// Botón ⋮ que despliega [FolderViewSettingsPopup] para [controller].
class FolderViewSettingsPopup extends StatelessWidget {
  final FilesController controller;

  const FolderViewSettingsPopup({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.tune_rounded, size: 22),
      tooltip: 'Vista y orden',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
      itemBuilder: (_) => folderViewSettingsItems(controller),
    );
  }
}

/// Entradas del menú de vista y orden, para quien ya tenga su propio botón.
List<PopupMenuEntry<String>> folderViewSettingsItems(
  FilesController controller,
) {
  return [
    popupHeader('MODO'),
    _check(
      controller: controller,
      label: 'Cuadrícula',
      checked: () => controller.categoryLayout == FileViewMode.grid,
      onTap: () => controller.setCategoryLayout(FileViewMode.grid),
    ),
    _check(
      controller: controller,
      label: 'Lista',
      checked: () => controller.categoryLayout == FileViewMode.list,
      onTap: () => controller.setCategoryLayout(FileViewMode.list),
    ),
    popupGap(),
    popupHeader('ORDENAR POR'),
    _check(
      controller: controller,
      label: 'Nombre',
      checked: () => controller.listingField == ListingSortField.name,
      onTap: () => controller.setListingField(ListingSortField.name),
    ),
    _check(
      controller: controller,
      label: 'Tamaño',
      checked: () => controller.listingField == ListingSortField.size,
      onTap: () => controller.setListingField(ListingSortField.size),
    ),
    _check(
      controller: controller,
      label: 'Fecha de modificación',
      checked: () => controller.listingField == ListingSortField.modified,
      onTap: () => controller.setListingField(ListingSortField.modified),
    ),
    _check(
      controller: controller,
      label: 'Tipo',
      checked: () => controller.listingField == ListingSortField.kind,
      onTap: () => controller.setListingField(ListingSortField.kind),
    ),
    popupGap(),
    popupHeader('DIRECCIÓN'),
    _check(
      controller: controller,
      label: 'Ascendente',
      checked: () => controller.listingDirection == SortDirection.asc,
      onTap: () => controller.setListingDirection(SortDirection.asc),
    ),
    _check(
      controller: controller,
      label: 'Descendente',
      checked: () => controller.listingDirection == SortDirection.desc,
      onTap: () => controller.setListingDirection(SortDirection.desc),
    ),
  ];
}

/// Fila con marca: el contenido se redibuja en vivo al cambiar.
///
/// Como [popupSwitch] pero para opciones excluyentes, donde un interruptor
/// mentiría (los switches son para on/off independientes, no para elegir
/// una de cuatro).
PopupMenuItem<String> _check({
  required FilesController controller,
  required String label,
  required bool Function() checked,
  required VoidCallback onTap,
}) {
  return PopupMenuItem<String>(
    onTap: onTap,
    child: AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final active = checked();
        return Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.check_rounded,
              size: 20,
              color: active
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
            ),
          ],
        );
      },
    ),
  );
}
