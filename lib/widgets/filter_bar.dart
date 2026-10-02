// lib/widgets/filter_bar.dart
//
// Barra de filtros del listado: chips de extensión + dos selectores
// (fecha y tamaño) + limpiar.
//
// # Por qué una tira y no un botón de "filtros"
//
// Un menú con casillas obliga a abrirlo, marcar tres cosas y cerrarlo para
// ver el resultado, y no deja claro qué sigue activo. Los chips son el
// estado: lo encendido se ve, se quita con el mismo gesto que se puso y el
// contador de la lista se actualiza mientras se toca.
//
// # Por qué fecha y tamaño son selectores y no chips
//
// Son criterios con muchas opciones (cuatro fechas, cinco tamaños) que son
// excluyentes entre sí: un chip por opción convertiría la tira en un panel.
// Lo que queda visible es un único chip por criterio, que muestra la
// elección vigente y se abre al tocarlo.
//
// # Qué NO hace
//
// No filtra por carpeta, favorito ni tipo detectado: eso ya son las
// categorías de Explorar, y duplicarlo aquí daría dos caminos para lo
// mismo. Aquí solo lo que no se resuelve yendo a otro sitio.
import 'package:flutter/material.dart';
import 'package:NexoraUi/NexoraUi.dart';

import '../controllers/files_controller.dart';
import '../models/file_filter.dart';

/// Tira de filtros del listado.
class FilterBar extends StatelessWidget {
  final FilesController controller;

  const FilterBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final f = controller.criteria;
        return NChipBar(
          children: [
            for (final ext in kQuickFilterExtensions)
              NChip(
                label: ext,
                selected: f.extensions.contains(ext),
                onTap: () => controller.toggleExtensionFilter(ext),
              ),
            NChip.action(
              label: dateLabel(f.modified),
              icon: Icons.event_outlined,
              onTap: () => _pickDate(context),
            ),
            NChip.action(
              label: f.size == FileSizeBucket.any ? 'Tamaño' : f.size.label,
              icon: Icons.data_usage_outlined,
              onTap: () => _pickSize(context),
            ),
            if (f.isActive)
              NChip.action(
                label: 'Limpiar',
                icon: Icons.close_rounded,
                onTap: controller.clearCriteria,
              ),
          ],
        );
      },
    );
  }

  /// Etiqueta del chip de fecha: el rango en palabras, no en fechas crudas.
  ///
  /// "Hoy" en vez de "12/9 – 12/9": es el caso que se usa a diario y
  /// comprimirlo deja sitio para las dos fechas de un rango personalizado.
  static String dateLabel(DateTimeRange? rango) {
    if (rango == null) return 'Fecha';
    for (final preset in datePresets()) {
      if (_mismoRango(rango, preset.$2)) return preset.$1;
    }
    return '${rango.start.day}/${rango.start.month} – '
        '${rango.end.day}/${rango.end.month}';
  }

  /// Rangos de fecha ofrecidos, con su etiqueta.
  ///
  /// El final es EXCLUSIVO (mañana a las 00:00) para que un archivo
  /// modificado hace un minuto no caiga fuera por un `isBefore` de un
  /// segundo. Por eso los presets se construyen con `add(1 día)` y no con
  /// "hoy".
  static List<(String, DateTimeRange)> datePresets() {
    final hoy = DateTime.now();
    final inicioHoy = DateTime(hoy.year, hoy.month, hoy.day);
    final manana = inicioHoy.add(const Duration(days: 1));
    return [
      ('Hoy', DateTimeRange(start: inicioHoy, end: manana)),
      (
        '7 días',
        DateTimeRange(
          start: inicioHoy.subtract(const Duration(days: 6)),
          end: manana,
        ),
      ),
      (
        '30 días',
        DateTimeRange(
          start: inicioHoy.subtract(const Duration(days: 29)),
          end: manana,
        ),
      ),
      ('Este año', DateTimeRange(start: DateTime(hoy.year), end: manana)),
    ];
  }

  static bool _mismoRango(DateTimeRange a, DateTimeRange b) =>
      a.start.isAtSameMomentAs(b.start) && a.end.isAtSameMomentAs(b.end);

  Future<void> _pickDate(BuildContext context) async {
    final controller = this.controller;
    final actual = controller.criteria.modified;
    // Registro en vez de `DateTimeRange?`: hacen falta TRES resultados
    // (no cambió, se limpió, se eligió otro) y un `null` se come dos de
    // ellos. `DateTimeRange` además no admite extremos nulos, así que
    // "vacío" no se puede fabricar.
    final elegido = await showNModal<({bool clear, DateTimeRange? range})>(
      context,
      builder: (ctx) => _DateRangeSheet(
        current: actual,
        onPick: (r) => Navigator.of(ctx).pop((clear: false, range: r)),
        onClear: () => Navigator.of(ctx).pop((clear: true, range: null)),
      ),
    );
    if (elegido == null) return;
    controller.setCriteria(
      elegido.clear
          ? controller.criteria.copyWith(clearDate: true)
          : controller.criteria.copyWith(modified: elegido.range),
    );
  }

  Future<void> _pickSize(BuildContext context) async {
    final controller = this.controller;
    final elegido = await showNModal<FileSizeBucket>(
      context,
      builder: (ctx) => _SizeSheet(current: controller.criteria.size),
    );
    if (elegido == null) return;
    controller.setCriteria(controller.criteria.copyWith(size: elegido));
  }
}

/// Hoja de fechas: los rangos que se usan de verdad, más el personalizado.
///
/// Los presets van primero porque "hoy" cubre la mayoría de las búsquedas
/// y con un `showDateRangePicker` solo habría que abrir un diálogo y mover
/// dos manecillas.
class _DateRangeSheet extends StatelessWidget {
  final DateTimeRange? current;
  final ValueChanged<DateTimeRange> onPick;
  final VoidCallback onClear;

  const _DateRangeSheet({
    required this.current,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final presets = FilterBar.datePresets();
    final esPreset =
        current != null && presets.any((p) => FilterBar._mismoRango(current!, p.$2));

    return NModalShell(
      title: 'Fecha de modificación',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          NGroupedCardContainer(
            children: [
              for (final (label, rango) in presets)
                _opcion(
                  icon: Icons.event_outlined,
                  label: label,
                  activa: current != null && FilterBar._mismoRango(current!, rango),
                  onTap: () => onPick(rango),
                ),
              _opcion(
                icon: Icons.date_range_outlined,
                label: 'Personalizado',
                activa: current != null && !esPreset,
                onTap: () => _personalizado(context),
              ),
            ],
          ),
          const SizedBox(height: NSpacing.spaceSm),
          NButton(
            label: 'Ninguna',
            variant: NButtonVariant.secondary,
            onPressed: onClear,
          ),
        ],
      ),
    );
  }

  Future<void> _personalizado(BuildContext context) async {
    final hoy = DateTime.now();
    final elegido = await showDateRangePicker(
      context: context,
      firstDate: DateTime(hoy.year - 5),
      // `lastDate` es inclusivo y tiene que admitir hoy entero.
      lastDate: DateTime(hoy.year, hoy.month, hoy.day, 23, 59, 59),
      initialDateRange: current,
    );
    if (elegido != null) onPick(elegido);
  }
}

/// Hoja de tamaño.
class _SizeSheet extends StatelessWidget {
  final FileSizeBucket current;

  const _SizeSheet({required this.current});

  @override
  Widget build(BuildContext context) {
    return NModalShell(
      title: 'Tamaño del archivo',
      child: NGroupedCardContainer(
        children: [
          for (final bucket in FileSizeBucket.values)
            _opcion(
              icon: bucket == FileSizeBucket.any
                  ? Icons.all_inclusive_rounded
                  : Icons.data_usage_outlined,
              label: bucket.label,
              activa: bucket == current,
              onTap: () => Navigator.of(context).pop(bucket),
            ),
        ],
      ),
    );
  }
}

/// Fila de opción con checkmark, no con switch.
///
/// El kit reserva el switch para lo booleano (encendido/apagado) y el
/// checkmark para elegir UNO de varios. Un selector de fecha con cinco
/// switches cinco encendidos a la vez mentiría sobre el estado.
Widget _opcion({
  required IconData icon,
  required String label,
  required bool activa,
  required VoidCallback onTap,
}) {
  return NOptionTile(
    icon: icon,
    title: label,
    selected: activa,
    trailing: NCheckmark(value: activa),
    onTap: onTap,
  );
}
