// lib/widgets/nfiles_popup.dart
//
// Los dos popups ⋮ de la topbar.
//
// Son DOS menús distintos, no uno con secciones variables: Recientes actúa
// sobre la lista (modo de vista + ajustes) y Explorar sobre las categorías
// (cómo se ve y cómo se ordena). Mezclarlos obligaría al usuario a leer
// opciones que no aplican a lo que tiene delante.
//
// Las filas multiválor son [icono + label + switch]: el tap en el switch lo
// consume su propio reconocedor y el tap en la fila llega al callback. Si se
// combinaran, los dos se dispararían a la vez.
import 'package:flutter/material.dart';
import '../controllers/files_controller.dart';
/// Separador invisible: solo espacio entre secciones, sin raya.
PopupMenuItem<String> popupGap() =>
    const PopupMenuItem<String>(
      enabled: false,
      height: 10,
      child: SizedBox.shrink(),
    );
/// Encabezado de sección.
PopupMenuItem<String> popupHeader(String text) => PopupMenuItem<String>(
  enabled: false,
  child: Text(
    text,
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
    ),
  ),
);
/// Fila con switch: el contenido se redibuja en vivo al cambiar.
///
/// El switch se pinta escuchando al CONTROLADOR, no a una copia del
/// valor: así el menú no puede mostrar un estado viejo justo después de
/// pulsarlo.
PopupMenuItem<String> popupSwitch({
  required FilesController controller,
  required String label,
  required bool Function() isSelected,
  required VoidCallback onToggle,
}) {
  return PopupMenuItem<String>(
    onTap: onToggle,
    child: AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Row(
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
          Switch.adaptive(
            value: isSelected(),
            onChanged: (_) => onToggle(),
          ),
        ],
      ),
    ),
  );
}
/// Popup de "Recientes": modo de vista (por fecha / compacto) + ajustes
/// (cuenta, configuración).
List<PopupMenuEntry<String>> buildRecentPopupItems(
  FilesController controller,
  VoidCallback onOpenAccount,
  VoidCallback onOpenSettings,
) {
  return [
    popupHeader('MODO DE VISTA'),
    popupSwitch(
      controller: controller,
      label: 'Por fecha',
      isSelected: () => controller.viewMode == FilesViewMode.byDate,
      onToggle: () {
        controller.setViewMode(FilesViewMode.byDate);
      },
    ),
    popupSwitch(
      controller: controller,
      label: 'Compacto',
      isSelected: () => controller.viewMode == FilesViewMode.compact,
      onToggle: () {
        controller.setViewMode(FilesViewMode.compact);
      },
    ),
    popupGap(),
    popupHeader('AJUSTES'),
    PopupMenuItem<String>(
      onTap: onOpenAccount,
      child: const _MenuRow(
        icon: Icons.person_outlined,
        label: 'Cuenta',
      ),
    ),
    PopupMenuItem<String>(
      onTap: onOpenSettings,
      child: const _MenuRow(
        icon: Icons.settings_outlined,
        label: 'Configuración',
      ),
    ),
  ];
}
/// Popup de "Explorar": modo de vista (lista / cuadrícula) + orden (A→Z).
List<PopupMenuEntry<String>> buildExplorePopupItems(
  FilesController controller,
) {
  return [
    popupHeader('MODO DE VISTA'),
    popupSwitch(
      controller: controller,
      label: 'Lista',
      isSelected: () => controller.categoryLayout == CategoryLayout.list,
      onToggle: () {
        controller.setCategoryLayout(CategoryLayout.list);
      },
    ),
    popupSwitch(
      controller: controller,
      label: 'Cuadrícula',
      isSelected: () => controller.categoryLayout == CategoryLayout.grid,
      onToggle: () {
        controller.setCategoryLayout(CategoryLayout.grid);
      },
    ),
    popupGap(),
    popupHeader('ORDEN'),
    popupSwitch(
      controller: controller,
      label: 'A → Z',
      isSelected: () =>
          controller.listingField == ListingSortField.name &&
          controller.listingDirection == SortDirection.asc,
      onToggle: () {
        controller.setListingField(ListingSortField.name);
        controller.setListingDirection(SortDirection.asc);
      },
    ),
    popupSwitch(
      controller: controller,
      label: 'Z → A',
      isSelected: () =>
          controller.listingField == ListingSortField.name &&
          controller.listingDirection == SortDirection.desc,
      onToggle: () {
        controller.setListingField(ListingSortField.name);
        controller.setListingDirection(SortDirection.desc);
      },
    ),
  ];
}
/// Fila simple del menú: icono + etiqueta.
class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MenuRow({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 14)),
        ),
      ],
    );
  }
}
