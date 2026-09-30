import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:NexoraCore/NexoraCore.dart';
import 'package:NFiles/app/nfiles_app.dart';
import 'package:NFiles/controllers/files_controller.dart';
import 'package:NFiles/models/explore_section.dart';
import 'package:NFiles/services/file_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Base de la app con el núcleo inyectado.
///
/// Dos decisiones que no son arbitrarias y que costaron una hora de tests
/// colgados:
///
/// - Toda E/S real va dentro de [tester.runAsync]. Un `await` normal de
///   `dart:io` dentro de `testWidgets` NUNCA completa: el cuerpo del test
///   corre bajo reloj falso y el future de disco no se resuelve.
/// - El servicio usa `useIsolate: false`. Con `compute` (isolate real) el
///   barrido no termina dentro de `runAsync`; en línea sí.
///
/// Además `roots` está acotado a un temporal: si la pantalla creara el
/// controlador, escanearía el `$HOME` del proceso y el test no sería
/// determinista.
late Directory tmp;
late FilesController controller;
late CorePermissions permissions;
late CoreLocale locale;
late CorePerformance performance;

/// Escribe un archivo dentro del temporal de pruebas (reloj real).
Future<void> put(WidgetTester tester, String name, {int size = 32}) async {
  final file = File('${tmp.path}/$name');
  await tester.runAsync(() async {
    await file.parent.create(recursive: true);
    await file.writeAsBytes(List.filled(size, 1));
  });
}

/// Escanea con reloj real y deja el controlador en `loaded`.
Future<void> precargar(WidgetTester tester) async {
  await tester.runAsync(() => controller.fetchFiles());
}

Future<void> setUpApp() async {
  tmp = await Directory.systemTemp.createTemp('nfiles_app');
  SharedPreferences.setMockInitialValues({});
  final prefs = CorePrefs.inMemory('nfiles_');
  locale = await CoreLocale.open(prefs);
  performance = await CorePerformance.open(prefs);
  permissions = CorePermissions(
    // El host del test es Linux: se declara para no depender de la máquina.
    hasRuntimePermissions: true,
  );
  controller = FilesController(fileService: FileService(roots: [tmp], useIsolate: false));
}

/// Tamaño de móvil: sin esto el kit puede montar la variante de escritorio.
void usePhone() {
  // El tamaño se fija dentro de cada test con `tester.view`.
}

Future<void> tearDownApp() async {
  controller.dispose();
  permissions.dispose();
  locale.dispose();
  performance.dispose();
  if (tmp.existsSync()) tmp.deleteSync(recursive: true);
}

Widget buildApp() => NFilesApp(
  permissions: permissions,
  performance: performance,
  locale: locale,
  controller: controller,
);

/// Fija el viewport a móvil dentro del test.
void phoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUp(setUpApp);
  tearDown(tearDownApp);

  testWidgets('arranca en Recientes con la bottom bar de 2 destinos', (
    tester,
  ) async {
    phoneViewport(tester);
    await precargar(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    // La bottom bar del kit es SOLO iconos: las etiquetas viven en el
    // sidebar de escritorio. Por eso se comprueban los iconos.
    expect(find.byIcon(Icons.history), findsOneWidget);
    expect(find.byIcon(Icons.explore_outlined), findsOneWidget);
    expect(find.text('NFiles'), findsOneWidget);
  });

  testWidgets('Recientes vacío declara el estado, no una pantalla rota', (
    tester,
  ) async {
    phoneViewport(tester);
    await precargar(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('Sin archivos'), findsOneWidget);
  });

  testWidgets('Recientes agrupa por día y nombra el día', (tester) async {
    await put(tester, 'recien.jpg');
    phoneViewport(tester);
    await precargar(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('Hoy'), findsOneWidget);
    expect(find.text('| 1'), findsOneWidget);
    expect(find.text('recien.jpg'), findsOneWidget);
  });

  testWidgets('la fila muestra peso y lugar de guardado', (tester) async {
    await put(tester, 'nota.pdf');
    phoneViewport(tester);
    await precargar(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    // "peso · carpeta" en la misma línea.
    expect(find.textContaining('B · '), findsWidgets);
    expect(find.text('nota.pdf'), findsOneWidget);
  });

  testWidgets('la cabecera se pliega y se despliega', (tester) async {
    await put(tester, 'a.jpg');
    phoneViewport(tester);
    await precargar(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('a.jpg'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();
    expect(find.text('a.jpg'), findsNothing);
    // La cabecera sigue: solo se pliega el contenido.
    expect(find.text('Hoy'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();
    expect(find.text('a.jpg'), findsOneWidget);
  });

  testWidgets('navega a Explorar', (tester) async {
    phoneViewport(tester);
    await precargar(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.explore_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Ubicaciones'), findsOneWidget);
    expect(find.text('NCloud'), findsOneWidget);
    expect(find.text('Este dispositivo'), findsOneWidget);
  });

  testWidgets('Explorar renderiza ubicaciones y las primeras categorías', (
    tester,
  ) async {
    phoneViewport(tester);
    await precargar(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.explore_outlined));
    await tester.pumpAndSettle();

    // Lo que cabe en pantalla: cabecera de ubicaciones y el primer grupo.
    expect(find.text('Ubicaciones'), findsOneWidget);
    expect(find.text('NCloud'), findsOneWidget);
    expect(find.text('Este dispositivo'), findsOneWidget);
    expect(find.text('Documentos'), findsOneWidget);
    expect(find.text('Imágenes'), findsOneWidget);
  });

  testWidgets('el scroll de Explorar alcanza las carpetas y recursos', (
    tester,
  ) async {
    phoneViewport(tester);
    await precargar(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.explore_outlined));
    await tester.pumpAndSettle();

    // La lista es perezosa: para comprobar las filas de abajo hay que
    // bajar de verdad, no solo buscarlas en el árbol.
    for (var i = 0; i < 6 && find.text('Grabaciones').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -220));
      await tester.pumpAndSettle();
    }

    expect(find.text('Carpetas'), findsOneWidget);
    expect(find.text('Descargas'), findsOneWidget);
    expect(find.text('Favoritos'), findsOneWidget);
    expect(find.text('Recursos'), findsOneWidget);
    expect(find.text('Cámara'), findsOneWidget);
    expect(find.text('Capturas'), findsOneWidget);
    expect(find.text('Grabaciones'), findsOneWidget);
  });

  test('el orden de categorías es el pedido, en los datos', () {
    // La lista es navegación, no una coincidencia. Se comprueba sobre
    // `exploreGroups()` y no sobre el árbol de widgets: la `ListView` es
    // perezosa y lo que no está en pantalla no existe como nodo.
    final groups = exploreGroups();

    expect(groups.map((g) => g.title).toList(), [
      null,
      'Carpetas',
      'Recursos',
    ]);
    expect(groups[0].entries.map((e) => e.title).toList(), [
      'Documentos',
      'Imágenes',
      'Vídeos',
      'Música',
      'Archivos',
      'APKs',
    ]);
    expect(groups[1].entries.map((e) => e.title).toList(), [
      'Descargas',
      'Favoritos',
    ]);
    expect(groups[2].entries.map((e) => e.title).toList(), [
      'Cámara',
      'Capturas',
      'Grabaciones',
    ]);
  });

  test('las ubicaciones van antes que las categorías y marcan el remoto', () {
    expect(kStorageLocations.map((l) => l.title).toList(), [
      'NCloud',
      'Este dispositivo',
    ]);
    // NCloud es la única remota: sin backend aún, y se declara.
    expect(kStorageLocations.first.isRemote, isTrue);
    expect(kStorageLocations.last.isRemote, isFalse);
  });

  test('todas las entradas resuelven sus archivos sin fallar', () {
    // Una fila cuya lambda revienta deja la pantalla en error al abrirla.
    final controller = FilesController(
      fileService: FileService(roots: const [], useIsolate: false),
    );
    addTearDown(controller.dispose);
    for (final group in exploreGroups()) {
      for (final entry in group.entries) {
        expect(entry.files(controller), isEmpty, reason: entry.title);
      }
    }
  });

  testWidgets('las categorías vacías lo declaran en el subtítulo', (
    tester,
  ) async {
    phoneViewport(tester);
    await precargar(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.explore_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Vacía'), findsWidgets);
  });

  testWidgets('"Este dispositivo" resume lo escaneado y las categorías lo suyo', (
    tester,
  ) async {
    await put(tester, 'a.jpg');
    await put(tester, 'b.pdf');
    phoneViewport(tester);
    await precargar(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.explore_outlined));
    await tester.pumpAndSettle();

    expect(find.textContaining('64 B en 2 archivos'), findsOneWidget);
    // Imágenes y Documentos tienen 1 cada una.
    expect(find.text('1 elemento'), findsNWidgets(2));
  });
}
