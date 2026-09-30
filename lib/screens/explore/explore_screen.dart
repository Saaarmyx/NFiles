// lib/screens/explore/explore_screen.dart
//
// Pantalla "Explorar": dónde está cada cosa.
//
// Estructura, de arriba abajo:
//   Ubicaciones      → NCloud + este dispositivo
//   (sin título)     → documentos, imágenes, vídeos, música, archivos, apks
//   Carpetas         → descargas, favoritos
//   Recursos         → cámara, capturas, grabaciones
//
// La estética es la de las tarjetas del kit (icono en cuadro tintado +
// título + subtítulo + chevron) para que la lista se lea de un vistazo sin
// abrir nada.
import 'package:flutter/material.dart';
import 'package:NexoraUi/NexoraUi.dart';

import '../../controllers/files_controller.dart';
import '../../models/explore_section.dart';
import '../category/category_screen.dart';

class ExploreScreen extends StatelessWidget {
  final FilesController controller;

  const ExploreScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (controller.state == FilesState.loading ||
            controller.state == FilesState.initial) {
          return const Center(child: NLoader(size: 44));
        }
        return ListView(
          padding: const EdgeInsets.only(bottom: NSpacing.spaceXl),
          children: [
            _LocationsCard(controller: controller),
            for (final group in exploreGroups()) ...[
              if (group.title != null)
                _GroupTitle(group.title!)
              else
                const SizedBox(height: NSpacing.spaceMd),
              _GroupCard(
                entries: group.entries,
                controller: controller,
              ),
              const SizedBox(height: NSpacing.spaceSm),
            ],
          ],
        );
      },
    );
  }
}

/// Tarjeta "Ubicaciones".
class _LocationsCard extends StatelessWidget {
  final FilesController controller;

  const _LocationsCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    return NSettingsSectionCard(
      section: NSettingsSection(
        title: 'Ubicaciones',
        items: [
          for (final location in kStorageLocations)
            NNavigationItem.standard(
              icon: location.icon,
              title: location.title,
              subtitle: location.isRemote
                  ? location.subtitle
                  : '${controller.totalFormattedSize} en '
                        '${controller.visibleFiles.length} archivos',
              onTap: () => _onLocationTap(context, location),
            ),
        ],
      ),
    );
  }

  void _onLocationTap(BuildContext context, StorageLocation location) {
    // NCloud todavía no tiene backend. Se declara en vez de abrir una
    // pantalla vacía: prometer algo que no existe es peor que decir que
    // falta.
    if (location.isRemote) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('NCloud: todavía no disponible')),
        );
      return;
    }
    pushNPage(
      context,
      CategoryScreen(
        controller: controller,
        title: 'Este dispositivo',
        icon: location.icon,
        files: controller.visibleFiles,
      ),
    );
  }
}

/// Título de grupo ("Carpetas", "Recursos").
class _GroupTitle extends StatelessWidget {
  final String title;

  const _GroupTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NSpacing.spaceMd,
        NSpacing.spaceSm,
        NSpacing.spaceMd,
        NSpacing.space2xs,
      ),
      child: NSectionLabel(
        title: title,
        color: context.nMutedTextColor,
      ),
    );
  }
}

/// Tarjeta de un grupo de entradas.
class _GroupCard extends StatelessWidget {
  final List<ExploreEntry> entries;
  final FilesController controller;

  const _GroupCard({required this.entries, required this.controller});

  @override
  Widget build(BuildContext context) {
    return NCard(
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(24),
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++)
            _EntryTile(
              entry: entries[i],
              controller: controller,
              isLast: i == entries.length - 1,
            ),
        ],
      ),
    );
  }
}

/// Fila: icono tintado + título + subtítulo + chevron.
class _EntryTile extends StatelessWidget {
  final ExploreEntry entry;
  final FilesController controller;
  final bool isLast;

  const _EntryTile({
    required this.entry,
    required this.controller,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final files = entry.files(controller);
    final count = files.length;
    final subtitle = entry.subtitle?.call(controller) ??
        (count == 0 ? 'Vacía' : '$count ${count == 1 ? 'elemento' : 'elementos'}');
    final muted = context.nMutedTextColor;

    return Column(
      children: [
        InkWell(
          onTap: () => pushNPage(
            context,
            CategoryScreen(
              controller: controller,
              title: entry.title,
              icon: entry.icon,
              files: files,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: NSpacing.spaceMd,
              vertical: NSpacing.spaceSm,
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: entry.tint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(entry.icon, color: Colors.white, size: 20),
                ),
                const SizedBox(width: NSpacing.spaceSm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: NTypography.fontFamilyBase,
                          fontWeight: NTypography.weightSemibold,
                          fontSize: NTypography.sizeMd,
                          color: context.nPrimaryTextColor,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
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
                Icon(Icons.chevron_right, size: 20, color: muted),
              ],
            ),
          ),
        ),
        if (!isLast)
          Divider(
            height: 1,
            indent: 60,
            endIndent: NSpacing.spaceMd,
            color: muted.withValues(alpha: 0.15),
          ),
      ],
    );
  }
}
