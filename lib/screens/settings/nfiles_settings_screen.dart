// lib/screens/settings/nfiles_settings_screen.dart
//
// Fuente única de datos de configuración de NFiles.
//
// - [nFilesAppInfo] y [nFilesProfileData]: compartidos por la ruta móvil y
//   el panel lateral de escritorio.
// - [NFilesSettingsScreen]: ruta móvil a pantalla completa. Delega en
//   [NSettingsScreen] para que cualquier cambio en NexoraUi se propague sin
//   duplicar layout.
//
// La apariencia (idioma, tema, acento, rendimiento) vive en `NexoraCore`
// y en `AppAppearance` del kit; aquí solo se navega a sus pantallas.
import 'package:flutter/material.dart';
import 'package:NexoraCore/NexoraCore.dart';
import 'package:NexoraUi/NexoraUi.dart';

import 'nfiles_about_screen.dart';

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
/// [permissions] y [locale] los inyecta `main()`: son objetos vivos
/// (ChangeNotifier / ValueNotifier) y la pantalla solo los lee y dispara
/// sus cambios, sin recrearlos en cada build.
class NFilesSettingsScreen extends StatelessWidget {
  final CorePermissions permissions;
  final CoreLocale locale;
  final CorePerformance performance;

  const NFilesSettingsScreen({
    super.key,
    required this.permissions,
    required this.locale,
    required this.performance,
  });

  @override
  Widget build(BuildContext context) {
    return NSettingsScreen(
      profileData: nFilesProfileData,
      appInfo: nFilesAppInfo,
      appName: nFilesAppInfo.appName,
      nexoraBaseSection: NSettingsScreen.buildNexoraBaseSection(
        onAccountTap: () => pushNPage(
          context,
          NAccountScreen(profileData: nFilesProfileData),
        ),
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
        onLanguageTap: () => pushNPage(
          context,
          CoreLanguageScreen(locale: locale),
        ),
        onAboutTap: () => pushNPage(
          context,
          NFilesAboutScreen(permissions: permissions),
        ),
      ),
    );
  }
}
