// lib/screens/recent/recent_screen.dart
//
// Pantalla inicial: archivos recientes, del más nuevo al más viejo.
//
// Un solo `CustomScrollView` con una cabecera por día (Hoy, Ayer, Hace 2
// días, fecha). El colapso de cada día vive en el State, no en el
// controlador: es estado efímero de la vista, y al recargar no debe
// perderlo ni reiniciarlo.
import 'package:flutter/material.dart';
import 'package:NexoraUi/NexoraUi.dart';

import '../../controllers/files_controller.dart';
import '../../models/file_model.dart';
import '../../utils/file_viewer.dart';
import '../../widgets/day_header.dart';
import '../../widgets/file_row.dart';

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

class RecentScreen extends StatefulWidget {
  final FilesController controller;

  const RecentScreen({super.key, required this.controller});

  @override
  State<RecentScreen> createState() => _RecentScreenState();
}

class _RecentScreenState extends State<RecentScreen> {
  /// Días plegados por el usuario. Clave: `yyyy-mm-dd`.
  final Set<String> _collapsed = {};

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
            onAction: controller.fetchFiles,
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
  List<_DayGroup> _groupsOf(FilesController controller) {
    final byDay = <DateTime, List<FileModel>>{};
    for (final file in controller.visibleFiles) {
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
    final total = groups.fold<int>(0, (sum, g) => sum + g.files.length);

    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: NSpacing.spaceXs)),
        for (final group in groups) ...[
          SliverToBoxAdapter(
            child: DayHeader(
              label: group.label,
              count: group.files.length,
              total: total,
              collapsed: _collapsed.contains(_keyOf(group.day)),
              onToggleCollapsed: () => setState(() {
                final key = _keyOf(group.day);
                if (!_collapsed.remove(key)) _collapsed.add(key);
              }),
            ),
          ),
          if (!_collapsed.contains(_keyOf(group.day)))
            SliverList.builder(
              itemCount: group.files.length,
              itemBuilder: (context, index) {
                final file = group.files[index];
                return FileRow(
                  file: file,
                  onTap: () => openFileViewer(
                    context,
                    controller: widget.controller,
                    files: group.files,
                    initialId: file.id,
                  ),
                );
              },
            ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: NSpacing.spaceXl)),
      ],
    );
  }
}
