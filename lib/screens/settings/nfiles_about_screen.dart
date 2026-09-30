// lib/screens/settings/nfiles_about_screen.dart
//
// "Sobre la app" de NFiles.
//
// Reutiliza el contenido del kit y le encaja la gestión de permisos del
// núcleo. La copia local de esa pantalla (heredada de NPhotos) ya no
// existe: `NexoraCore` la sirve para las dos apps.
import 'package:flutter/material.dart';
import 'package:NexoraCore/NexoraCore.dart';
import 'package:NexoraUi/NexoraUi.dart';

import 'nfiles_permissions_screen.dart';
import 'nfiles_settings_screen.dart';

class NFilesAboutScreen extends StatelessWidget {
  final CorePermissions permissions;

  const NFilesAboutScreen({super.key, required this.permissions});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const NSecondaryTopBar(title: 'Sobre la app'),
      body: NAboutContent(
        appInfo: nFilesAppInfo,
        onPermissionsTap: () => pushNPage(
          context,
          NFilesPermissionsScreen(permissions: permissions),
        ),
        onRevokePermissionsTap: () => confirmRevokeAllPermissions(context),
      ),
    );
  }
}
