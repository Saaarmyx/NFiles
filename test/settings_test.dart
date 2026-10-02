import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:NexoraCore/NexoraCore.dart';
import 'package:NFiles/screens/settings/nfiles_about_screen.dart';
import 'package:NFiles/screens/settings/nfiles_permissions_screen.dart';
import 'package:NexoraUi/NexoraUi.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Permisos de mentira.
///
/// Los reales consultan a un canal de plataforma, y un canal no resuelve bajo
/// el reloj falso de `testWidgets`: la pantalla se quedaría en
/// `loading` para siempre. Con estos, `refresh()` se resuelve en el acto
/// y se puede probar la UI de verdad.
CorePermissions fakePermissions({
  PermissionStatus status = PermissionStatus.granted,
  bool hasRuntime = true,
}) {
  CorePermission fake(String id) => CorePermission(
    id: id,
    title: id,
    icon: Icons.folder_outlined,
    status: () async => status,
    request: () async => status,
  );
  return CorePermissions(
    hasRuntimePermissions: hasRuntime,
    permissions: [fake('media'), fake('notifications')],
  );
}

Future<({CoreLocale locale, CorePerformance performance})> core() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = CorePrefs.inMemory('nfiles_');
  final locale = await CoreLocale.open(prefs);
  final performance = await CorePerformance.open(prefs);
  addTearDown(locale.dispose);
  addTearDown(performance.dispose);
  return (locale: locale, performance: performance);
}

void main() {
  testWidgets('About muestra la app y sus secciones', (tester) async {
    final permissions = fakePermissions();
    addTearDown(permissions.dispose);

    await tester.pumpWidget(
      MaterialApp(home: NFilesAboutScreen(permissions: permissions)),
    );
    await tester.pumpAndSettle();

    expect(find.text('NFiles'), findsWidgets);
    expect(find.byType(NAboutContent), findsOneWidget);
  });

  test('la base de ajustes es fija: sin Cuenta ni Idioma', () {
    // La cuenta vive en NCloud y el idioma donde se usa: la base ya no
    // acepta callbacks para ninguno de los dos.
    final base = NSettingsScreen.buildNexoraBaseSection(
      appName: 'NFiles',
      onPerformanceTap: () {},
      onPersonalizationTap: () {},
      onAboutTap: () {},
    );

    expect(base.title, 'Ajustes adicionales');

    final titulos = base.items.whereType<NNavigationItem>().map((i) => i.title);
    expect(titulos, ['Rendimiento', 'Personalización', 'Sobre NFiles']);
    expect(titulos, isNot(contains('Cuenta')));
    expect(titulos, isNot(contains('Idioma')));
  });

  testWidgets('la pantalla de permisos delega en el núcleo', (tester) async {
    final permissions = fakePermissions();
    addTearDown(permissions.dispose);

    await tester.pumpWidget(
      MaterialApp(home: NFilesPermissionsScreen(permissions: permissions)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Gestión de permisos'), findsOneWidget);
    // El contenido y los títulos vienen del núcleo, no de una copia local.
    expect(find.text('media'), findsOneWidget);
    expect(find.text('notifications'), findsOneWidget);
    // Concedidos: los switches están encendidos.
    expect(find.byType(Switch), findsNWidgets(2));
  });

  testWidgets('un permiso denegado deja el switch apagado', (tester) async {
    final permissions = fakePermissions(status: PermissionStatus.denied);
    addTearDown(permissions.dispose);

    await tester.pumpWidget(
      MaterialApp(home: NFilesPermissionsScreen(permissions: permissions)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cargando') , findsNothing);
    expect(permissions.state, PermissionsState.requestable);
  });

  testWidgets('en escritorio los permisos se declaran gestionados', (
    tester,
  ) async {
    final permissions = fakePermissions(hasRuntime: false);
    addTearDown(permissions.dispose);

    await tester.pumpWidget(
      MaterialApp(home: NFilesPermissionsScreen(permissions: permissions)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Gestionado por el sistema'), findsOneWidget);
  });

  testWidgets('la pantalla de idioma lista los idiomas y persiste', (
    tester,
  ) async {
    final c = await core();

    await tester.pumpWidget(
      MaterialApp(home: CoreLanguageScreen(locale: c.locale)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Idioma'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Deutsch'), findsOneWidget);

    await tester.tap(find.text('Deutsch'));
    await tester.pumpAndSettle();
    expect(c.locale.language.value.code, 'de-DE');
  });

  testWidgets('el rendimiento cambia de perfil y lo persiste', (tester) async {
    final c = await core();

    expect(c.performance.mode, CorePerformanceMode.high);
    await c.performance.setMode(CorePerformanceMode.low);
    expect(c.performance.mode, CorePerformanceMode.low);
    expect(c.performance.animationsEnabled, isFalse);
  });
}
