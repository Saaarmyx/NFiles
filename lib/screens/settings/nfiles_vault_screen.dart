// lib/screens/settings/nfiles_vault_screen.dart
//
// Carpeta segura: los archivos que el usuario saca del explorador.
//
// Es una pantalla de solo lectura con una acción por fila (restaurar).
// No lleva su propia lista de "borrar": vaciar la bóveda es lo mismo que
// borrar cada archivo, y ese diálogo ya lo pone quien lo borra. Añadirlo
// aquí duplicaría la confirmación en dos sitios que pueden desincronizarse.
//
// Se llega desde Ajustes > Seguridad y papelera > Carpeta segura.
import 'package:flutter/material.dart';
import 'package:NexoraUi/NexoraUi.dart';

import '../../controllers/files_controller.dart';

/// Contenido de la carpeta segura (reutilizable en el panel desktop).
class NFilesVaultContent extends StatelessWidget {
  final FilesController controller;

  const NFilesVaultContent({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final files = controller.privateFiles;
        if (files.isEmpty) return const _VaultEmpty();
        return ListView.separated(
          padding: const EdgeInsets.all(NSpacing.spaceMd),
          itemCount: files.length,
          separatorBuilder: (_, _) => const SizedBox(height: NSpacing.spaceXs),
          itemBuilder: (context, i) {
            final file = files[i];
            return NOptionTile(
              icon: Icons.lock_outline_rounded,
              title: file.displayName,
              subtitle: file.folderName,
              // Icono de restaurar, no un chevron: la fila no navega, la
              // acción está en la propia fila.
              trailing: Icon(
                Icons.restore_rounded,
                size: 20,
                color: NOptionTileColors.accentOf(context),
              ),
              onTap: () => controller.restoreFromPrivate(file.id),
            );
          },
        );
      },
    );
  }
}

class _VaultEmpty extends StatelessWidget {
  const _VaultEmpty();

  @override
  Widget build(BuildContext context) {
    return const NEmptyState(
      icon: Icons.lock_outline_rounded,
      title: 'Carpeta segura vacía',
      subtitle:
          'Los archivos que muevas aquí dejan de verse en el explorador, '
          'en tus álbumes y en Recientes.',
    );
  }
}

/// Ruta móvil de la carpeta segura.
class NFilesVaultScreen extends StatelessWidget {
  final FilesController controller;

  const NFilesVaultScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const NSecondaryTopBar(title: 'Carpeta segura'),
      body: NFilesVaultContent(controller: controller),
    );
  }
}
