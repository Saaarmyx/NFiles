// lib/main.dart
//
// Arranque de NFiles.
//
// El orden importa: primero el núcleo (idioma, rendimiento, permisos) y
// después la apariencia, porque el rendimiento decide el acento por defecto
// que se aplica si el usuario no ha hecho la bienvenida.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'package:NexoraCore/NexoraCore.dart';
import 'package:NexoraUi/NexoraUi.dart';

import 'app/nfiles_app.dart';
import 'services/local_store.dart';

/// Namespace de preferencias de NFiles dentro del núcleo compartido.
///
/// Distinto del de NPhotos a propósito: las dos apps pueden convivir
/// instaladas y no deben pisarse las preferencias.
const String kNFilesPrefsNamespace = 'nfiles_';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // ─── Núcleo ───
  final prefs = await CorePrefs.open(kNFilesPrefsNamespace);
  final locale = await CoreLocale.open(prefs);
  final performance = await CorePerformance.open(prefs);
  // Set de gestor de archivos: base + "todos los archivos". Sin el último
  // la pantalla de permisos no lo muestra y el usuario no puede activarlo.
  final permissions = CorePermissions(permissions: filesPermissions());

  // ─── App ───
  final store = await LocalStore.load();
  store.applyAppearance();
  await permissions.refresh();

  runApp(
    CoreAppScope(
      locale: locale,
      child: _Localized(
        locale: locale,
        permissions: permissions,
        performance: performance,
        store: store,
      ),
    ),
  );
}

/// Aplica el idioma al `MaterialApp` y baja la pantalla de permisos.
///
/// Va aparte de [NFilesApp] para que el `MaterialApp` se reconstruya
/// cuando cambia el idioma (el `MaterialApp.locale` no puede cambiar solo
/// desde dentro).
class _Localized extends StatelessWidget {
  final CoreLocale locale;
  final CorePermissions permissions;
  final CorePerformance performance;
  final LocalStore store;

  const _Localized({
    required this.locale,
    required this.permissions,
    required this.performance,
    required this.store,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: locale,
      builder: (context, activeLocale, _) => NAppShell(
        title: 'NFiles',
        locale: activeLocale,
        supportedLocales: [for (final l in kAppLanguages) toFlutterLocale(l)],
        // Los delegados los aporta el núcleo: el kit no depende de
        // `flutter_localizations` a propósito (ver NAppShell).
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: NFilesHome(
          store: store,
          permissions: permissions,
          performance: performance,
          locale: locale,
        ),
      ),
    );
  }
}
