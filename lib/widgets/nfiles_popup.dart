// lib/widgets/nfiles_popup.dart
//
// Los dos popups ⋮ de la topbar.
//
// Son DOS menús distintos, no uno con secciones variables: Recientes actúa
// sobre la lista de archivos (transferir, espacio, ajustes) y Explorar
// sobre la navegación (cómo se ve y cómo se ordena). Mezclarlos obligaría
// al usuario a leer opciones que no aplican a lo que tiene delante.
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
/// Popup de "Recientes": transferir, espacio, ajustes.
List<PopupMenuEntry<String>> buildRecentPopupItems(
  BuildContext context,
  FilesController controller,
  VoidCallback onOpenSettings,
) {
  return [
    popupHeader('ACCIONES'),
    PopupMenuItem<String>(
      onTap: () {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Transferencias: sin cola activa')),
          );
      },
      child: const _MenuRow(
        icon: Icons.swap_vert_circle_outlined,
        label: 'Transferir archivos',
      ),
    ),
    PopupMenuItem<String>(
      onTap: () {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                'Espacio: ${controller.totalFormattedSize} '
                'en ${controller.visibleFiles.length} archivos',
              ),
            ),
          );
      },
      child: const _MenuRow(
        icon: Icons.storage_outlined,
        label: 'Espacio',
      ),
    ),
    popupGap(),
    PopupMenuItem<String>(
      onTap: onOpenSettings,
      child: const _MenuRow(icon: Icons.settings_outlined, label: 'Ajustes'),
    ),
  ];
}
/// Popup de "Explorar": modo de vista y orden.
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
      isSelected: () => controller.categorySort == CategorySort.az,
      onToggle: () {
        controller.setCategorySort(CategorySort.az);
      },
    ),
    popupSwitch(
      controller: controller,
      label: 'Z → A',
      isSelected: () => controller.categorySort == CategorySort.za,
      onToggle: () {
        controller.setCategorySort(CategorySort.za);
      },
    ),
    popupGap(),
    popupHeader('EXPLORAR'),
    popupSwitch(
      controller: controller,
      label: 'Compacto',
      isSelected: () => controller.exploreViewMode == ExploreViewMode.compact,
      onToggle: () {
        controller.setExploreViewMode(ExploreViewMode.compact);
      },
    ),
    popupSwitch(
      controller: controller,
      label: 'Por grupo',
      isSelected: () => controller.exploreViewMode == ExploreViewMode.grouped,
      onToggle: () {
        controller.setExploreViewMode(ExploreViewMode.grouped);
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
