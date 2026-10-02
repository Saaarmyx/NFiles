// lib/screens/settings/nfiles_files_settings_content.dart
//
// Los ajustes propios del gestor de archivos, con las piezas estándar
// del kit: [NGroupedCardContainer] por grupo y [NOptionTile] por fila.
//
// Tres sufijos y solo tres, con el significado que tiene en el resto del
// kit (ver `NOptionTile.toggle` y `NCheckmark`):
//
// - Switch plano (`NOptionTile.toggle`) → booleanos on/off.
// - Chevron → la fila abre un selector o navega a otra pantalla.
// - Checkmark (`NCheckmark`) → dentro de un selector, qué opción está
//   activa. El estado lo anuncia la fila, no el check: no se oye dos
//   veces lo mismo.
//
// Cada grupo es una sola idea (cómo se ve, cómo se guarda, qué pasa al
// borrar) y están separados para que un interruptor mal pulsado no quede
// a dos toques de "Vaciar papelera".
//
// Estado y persistencia: la pantalla no guarda nada. Lee del
// [FilesController] y escribe con sus setters; el `attach` de
// `FilesViewPrefs` persiste el bloque entero con debounce. Por eso las
// claves viven en `FilesViewState` y no en un `SharedPreferences` suelto
// dentro del widget.
import 'package:flutter/material.dart';
import 'package:NexoraUi/NexoraUi.dart';

import '../../controllers/files_controller.dart';
import 'nfiles_vault_screen.dart';

/// Contenido de los ajustes de archivos, sin `Scaffold`.
///
/// Devuelve una [Column], no una lista con scroll propio: se monta dentro
/// del `ListView` de [NSettingsContent] (la pantalla de Ajustes), y una
/// lista dentro de otra lista reparte el alto entre las dos y deja la
/// interior sin scroll, con lo que las filas de abajo son inalcanzables.
///
/// Se rebuild sola con [ListenableBuilder] porque quien la mete en Ajustes
/// no la envuelve en nada reactivo.
class NFilesFilesSettingsContent extends StatelessWidget {
  final FilesController controller;

  const NFilesFilesSettingsContent({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _group('Visualización', [
              _viewMode(context),
              _sortField(context),
              _hidden(),
              _extensions(),
            ]),
            _group('Almacenamiento y miniaturas', [
              _wifiOnly(),
              _clearCache(context),
            ]),
            _group('Seguridad y papelera', [
              _confirmDelete(),
              _emptyTrash(context),
              _vault(context),
            ]),
          ],
        );
      },
    );
  }

  /// Grupo con su rótulo y su tarjeta.
  ///
  /// El aire entre grupos lo pone el bloque contenedor de Ajustes; aquí
  /// solo el de abajo del último, para que no pegue con lo que siga.
  Widget _group(String title, List<Widget> rows) {
    return Padding(
      padding: const EdgeInsets.only(bottom: NSpacing.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NSectionLabel(title: title),
          const SizedBox(height: NSpacing.spaceXs),
          NGroupedCardContainer(children: rows),
        ],
      ),
    );
  }

  // ─── Visualización ──────────────────────────────────────────────────

  /// Vista por defecto de un listado: lista o cuadrícula.
  Widget _viewMode(BuildContext context) {
    return _selectorRow(
      icon: Icons.grid_view_rounded,
      title: 'Vista predeterminada',
      subtitle: _viewModeLabel(controller.categoryLayout),
      onTap: () => _pickViewMode(context),
    );
  }

  Future<void> _pickViewMode(BuildContext context) async {
    final chosen = await showNModal<CategoryLayout>(
      context,
      builder: (ctx) => _selectorSheet<CategoryLayout>(
        title: 'Vista predeterminada',
        values: CategoryLayout.values,
        isSelected: (m) => m == controller.categoryLayout,
        iconOf: (m) => m == CategoryLayout.grid
            ? Icons.grid_view_rounded
            : Icons.view_agenda_outlined,
        labelOf: _viewModeLabel,
        onPick: (m) => Navigator.of(ctx).pop(m),
      ),
    );
    if (chosen != null) controller.setCategoryLayout(chosen);
  }

  /// Orden por defecto de un listado. El subtítulo dice qué campo está
  /// activo: es el dato que el usuario quiere ver sin abrir el selector.
  Widget _sortField(BuildContext context) {
    return _selectorRow(
      icon: Icons.swap_vert_rounded,
      title: 'Ordenar por',
      subtitle: _sortFieldLabel(controller.listingField),
      onTap: () => _pickSortField(context),
    );
  }

  Future<void> _pickSortField(BuildContext context) async {
    final chosen = await showNModal<ListingSortField>(
      context,
      builder: (ctx) => _selectorSheet<ListingSortField>(
        title: 'Ordenar por',
        values: ListingSortField.values,
        isSelected: (f) => f == controller.listingField,
        iconOf: _sortFieldIcon,
        labelOf: _sortFieldLabel,
        onPick: (f) => Navigator.of(ctx).pop(f),
      ),
    );
    if (chosen != null) controller.setListingField(chosen);
  }

  /// Archivos y carpetas ocultos.
  ///
  /// El subtítulo avisa de lo que cuesta: con el ajuste activo entran
  /// también las carpetas internas del sistema (`.thumbnails`,
  /// `.trash`), que en Android guardan copias de todo lo multimedia.
  Widget _hidden() {
    return NOptionTile.toggle(
      icon: Icons.visibility_off_outlined,
      title: 'Archivos ocultos',
      subtitle: 'Incluye carpetas del sistema como .thumbnails',
      value: controller.showHiddenFiles,
      onChanged: controller.setShowHiddenFiles,
    );
  }

  /// Mostrar la extensión en los títulos (`informe.pdf` vs `informe`).
  Widget _extensions() {
    return NOptionTile.toggle(
      icon: Icons.description_outlined,
      title: 'Mostrar extensiones',
      subtitle: 'El nombre termina en .pdf, .jpg, .mp3…',
      value: controller.showFileExtensions,
      onChanged: controller.setShowFileExtensions,
    );
  }

  // ─── Almacenamiento y miniaturas ──────────────────────────────────────

  /// Miniaturas solo con Wi-Fi.
  ///
  /// Hoy las miniaturas son locales (motor nativo, sin red), así que no
  /// hay tráfico que ahorrar: lo que el ajuste corta es el prerrellenado
  /// por scroll. Encendido, las fichas usan el icono de familia hasta que
  /// la miniatura esté ya en la caché; el archivo que se abre a propósito
  /// sí genera la suya.
  Widget _wifiOnly() {
    return NOptionTile.toggle(
      icon: Icons.wifi_rounded,
      title: 'Miniaturas solo con Wi-Fi',
      subtitle: 'No se generan por adelantado; las que ya hay se usan',
      value: controller.thumbnailsWifiOnly,
      onChanged: controller.setThumbnailsWifiOnly,
    );
  }

  /// Limpiar la caché de miniaturas.
  ///
  /// Acción directa y no un interruptor: no hay un "estado" de la caché
  /// que conservar, y un switch aquí sugeriría que está activada o no
  /// cuando en realidad hay una cantidad de bytes que además cambia sola
  /// con el uso. Pide confirmación y avisa de lo que borró.
  Widget _clearCache(BuildContext context) {
    return _selectorRow(
      icon: Icons.cleaning_services_outlined,
      title: 'Limpiar caché de miniaturas',
      subtitle: 'Se regeneran la próxima vez que se abra cada archivo',
      onTap: () => _confirmClearCache(context),
    );
  }

  Future<void> _confirmClearCache(BuildContext context) async {
    final confirmed = await showNConfirmDialog(
      context,
      title: '¿Limpiar la caché de miniaturas?',
      message:
          'Se borran las miniaturas guardadas. Los archivos no se tocan y '
          'se regeneran al abrir cada uno.',
      confirmLabel: 'Limpiar',
      isDestructive: false,
      icon: Icons.cleaning_services_outlined,
    );
    if (!confirmed || !context.mounted) return;
    final removed = await controller.clearThumbnailCache();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            removed == 0
                ? 'La caché ya estaba vacía'
                : 'Se borraron $removed miniaturas',
          ),
        ),
      );
  }

  // ─── Seguridad y papelera ────────────────────────────────────────────

  /// Confirmar antes de un borrado definitivo.
  ///
  /// Apagado, el borrado va directo (lo llama `confirmDestructive`, que
  /// pregunta por [FilesController.confirmDelete]).
  Widget _confirmDelete() {
    return NOptionTile.toggle(
      icon: Icons.verified_user_outlined,
      title: 'Confirmar al eliminar',
      subtitle: 'Apagado, el borrado va sin preguntar',
      value: controller.confirmDelete,
      onChanged: controller.setConfirmDelete,
    );
  }

  /// Vaciado automático de la papelera. `0` = nunca.
  Widget _emptyTrash(BuildContext context) {
    final days = controller.autoEmptyTrashDays;
    return _selectorRow(
      icon: Icons.delete_outline_rounded,
      title: 'Vaciar papelera',
      subtitle: days == 0 ? 'Nunca' : 'Cada $days días',
      onTap: () => _pickTrashDays(context),
    );
  }

  Future<void> _pickTrashDays(BuildContext context) async {
    const options = <int>[0, 7, 30, 90];
    final chosen = await showNModal<int>(
      context,
      builder: (ctx) => _selectorSheet<int>(
        title: 'Vaciar papelera',
        values: options,
        isSelected: (d) => d == controller.autoEmptyTrashDays,
        iconOf: (d) => d == 0 ? Icons.all_inclusive_rounded : Icons.schedule,
        labelOf: _trashDaysLabel,
        onPick: (d) => Navigator.of(ctx).pop(d),
      ),
    );
    if (chosen != null) controller.setAutoEmptyTrashDays(chosen);
  }

  /// Carpeta segura: los archivos que salen del explorador.
  ///
  /// Chevron y no nada: es una navegación a otra pantalla, no un ajuste.
  /// El contador va en el subtítulo para no tener que abrirla para saber
  /// si hay algo dentro.
  Widget _vault(BuildContext context) {
    final count = controller.privateFiles.length;
    return _selectorRow(
      icon: Icons.lock_outline_rounded,
      title: 'Carpeta segura',
      subtitle: switch (count) {
        0 => 'Vacía',
        1 => '1 archivo fuera del explorador',
        _ => '$count archivos fuera del explorador',
      },
      onTap: () => pushNPage(
        context,
        NFilesVaultScreen(controller: controller),
      ),
    );
  }

  // ─── Piezas compartidas ──────────────────────────────────────────────

  /// Fila que abre un selector o navega: siempre chevron al final.
  Widget _selectorRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return NOptionTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: const Icon(Icons.chevron_right_rounded, size: 20),
      onTap: onTap,
    );
  }

  /// Hoja de selección única: una fila por valor, con checkmark en la
  /// activa. Cierra con el valor elegido.
  ///
  /// Genérica en el tipo para que vista, orden y papelera compartan una
  /// sola implementación: los tres son "elige un valor de una lista", y
  /// tres copias divergirían en cuanto cambie el sufijo del check.
  Widget _selectorSheet<T>({
    required String title,
    required List<T> values,
    required bool Function(T) isSelected,
    required IconData Function(T) iconOf,
    required String Function(T) labelOf,
    required ValueChanged<T> onPick,
  }) {
    return NModalShell(
      title: title,
      child: NGroupedCardContainer(
        children: [
          for (final value in values)
            NOptionTile(
              icon: iconOf(value),
              title: labelOf(value),
              selected: isSelected(value),
              trailing: NCheckmark(value: isSelected(value)),
              onTap: () => onPick(value),
            ),
        ],
      ),
    );
  }

  static String _viewModeLabel(CategoryLayout mode) => switch (mode) {
        CategoryLayout.list => 'Lista',
        CategoryLayout.grid => 'Cuadrícula',
      };

  static String _sortFieldLabel(ListingSortField field) => switch (field) {
        ListingSortField.name => 'Nombre',
        ListingSortField.size => 'Tamaño',
        ListingSortField.modified => 'Fecha de modificación',
        ListingSortField.kind => 'Tipo',
      };

  static IconData _sortFieldIcon(ListingSortField field) => switch (field) {
        ListingSortField.name => Icons.sort_by_alpha_rounded,
        ListingSortField.size => Icons.storage_rounded,
        ListingSortField.modified => Icons.schedule,
        ListingSortField.kind => Icons.sell_outlined,
      };

  static String _trashDaysLabel(int days) =>
      days == 0 ? 'Nunca' : 'Cada $days días';
}
