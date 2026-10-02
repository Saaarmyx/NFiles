// lib/screens/settings/nfiles_settings_screen.dart
//
// Ajustes de NFiles: la pantalla que el engranaje del layout abre.
//
// Es UNA sola pantalla, no un menú con un submenú. Encima está la base
// compartida del kit ([NSettingsScreen]: perfil, NCloud, rendimiento,
// personalización, "Sobre") y debajo los tres grupos propios de archivos
// ([NFilesFilesSettingsContent]), inyectados con `extraBlocks`.
//
// Que sean bloques ya construidos y no `NSettingsSection` es a propósito:
// las filas usan [NOptionTile] con switch, chevron y checkmark, los
// mismos que en el resto de la app. Traducirlas al modelo del kit
// obligaría a usar un control distinto en el único sitio donde el
// usuario ajusta el comportamiento del gestor.
//
// La apariencia (idioma, tema, acento, rendimiento) vive en `NexoraCore`
// y en `AppAppearance` del kit; aquí solo se navega a sus pantallas.
//
// Nada se guarda desde aquí: cada fila escribe en el [FilesController], y
// el `attach` de `FilesViewPrefs` persiste el bloque entero con debounce.
// Una fila que no pase por el setter se perdería al reiniciar, así que
// todas las que cambian algo usan el setter del controller.
import 'package:flutter/material.dart';
import 'package:NexoraCore/NexoraCore.dart';
import 'package:NexoraUi/NexoraUi.dart';

import '../../controllers/files_controller.dart';
import 'nfiles_about_screen.dart';
import 'nfiles_files_settings_content.dart';

/// Datos de perfil compartidos (móvil + panel desktop).
const nFilesProfileData = UserProfileData(
  name: 'Nexora Labs',
  email: 'nexora@ncloud.com',
  avatarUrl: '',
  storageUsedGb: 1.2,
  storageTotalGb: 256,
);

/// Info de app compartida (móvil + panel desktop).
///
/// Mantener sincronizada con `version:` de pubspec (esquema Nexora
/// AA.MM.DD-canal: 26.09.28-release | 26.09.28-beta | 26.09.28-debug).
const nFilesAppInfo = NAboutAppInfo(
  appName: 'NFiles',
  version: '26.09.28-release',
  buildNumber: '1',
);

/// Ruta móvil de ajustes.
///
/// [permissions], [locale] y [performance] los inyecta `main()`: son
/// objetos vivos (ChangeNotifier / ValueNotifier) y la pantalla solo los
/// lee y dispara sus cambios, sin recrearlos en cada build. El
/// [controller] es la fuente de los ajustes de archivos, y entra
/// inyectado por la misma razón: el engranaje vive en el layout, que ya
/// lo tiene.
class NFilesSettingsScreen extends StatelessWidget {
  final CorePermissions permissions;
  final CoreLocale locale;
  final CorePerformance performance;
  final FilesController controller;

  const NFilesSettingsScreen({
    super.key,
    required this.permissions,
    required this.locale,
    required this.performance,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return NSettingsScreen(
      profileData: nFilesProfileData,
      appInfo: nFilesAppInfo,
      appName: nFilesAppInfo.appName,
      // Los ajustes de archivos van EN LA MISMA pantalla, no detrás de
      // una fila que empuje a otra pantalla: son ajustes que se cambian
      // de vez en cuando, y esconderlos un nivel por debajo es la forma
      // más rápida de que nunca se cambien.
      extraBlocks: [NFilesFilesSettingsContent(controller: controller)],
      nexoraBaseSection: NSettingsScreen.buildNexoraBaseSection(
        appName: nFilesAppInfo.appName,
        onPerformanceTap: () => pushNPage(
          context,
          NPerformanceContent(
            onPerformanceModeChanged: (mode) =>
                performance.setMode(mode),
          ),
        ),
        onPersonalizationTap: () => pushNPage(
          context,
          const NPersonalizationScreen(experimentalLayout: true),
        ),
        onAboutTap: () => pushNPage(
          context,
          NFilesAboutScreen(permissions: permissions),
        ),
      ),
    );
  }
}
