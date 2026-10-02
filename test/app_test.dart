import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:NexoraCore/NexoraCore.dart';
import 'package:NexoraUi/NexoraUi.dart';
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
    // La topbar muestra el nombre del destino activo.
    expect(find.text('Recientes'), findsOneWidget);
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

    expect(find.text('Hoy • 1 elemento'), findsOneWidget);
    expect(find.text('recien.jpg'), findsOneWidget);
  });

  testWidgets('la fila muestra peso y lugar de guardado', (tester) async {
    await put(tester, 'nota.pdf');
    phoneViewport(tester);
    await precargar(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    // "peso • carpeta" en la misma línea (formato de NRecentFileCard).
    expect(find.textContaining('B • '), findsWidgets);
    expect(find.text('nota.pdf'), findsOneWidget);
  });

  testWidgets('la cabecera se pliega y se despliega', (tester) async {
    await put(tester, 'a.jpg');
    phoneViewport(tester);
    await precargar(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('a.jpg'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
    await tester.pumpAndSettle();
    expect(find.text('a.jpg'), findsNothing);
    // La cabecera sigue: solo se pliega el contenido.
    expect(find.text('Hoy • 1 elemento'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
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

    expect(find.text('Almacenamiento'), findsOneWidget);
    expect(find.text('NCloud'), findsOneWidget);
    expect(find.text('Mi Teléfono'), findsOneWidget);
  });

  testWidgets('Explorar renderiza almacenamiento y las primeras categorías', (
    tester,
  ) async {
    // Con archivos: las categorías vacías no se pintan (ver "lo vacío se
    // esconde"), así que para ver "Documentos" tiene que haber un pdf.
    await put(tester, 'nota.pdf');
    await put(tester, 'foto.jpg');
    phoneViewport(tester);
    await precargar(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.explore_outlined));
    await tester.pumpAndSettle();

    // Lo que cabe en pantalla: almacenamiento y el primer grupo.
    expect(find.text('Almacenamiento'), findsOneWidget);
    expect(find.text('NCloud'), findsOneWidget);
    expect(find.text('Mi Teléfono'), findsOneWidget);
    expect(find.text('Documentos'), findsOneWidget);
    expect(find.text('Imágenes'), findsOneWidget);
  });

  testWidgets('el scroll de Explorar alcanza las carpetas y recursos', (
    tester,
  ) async {
    await put(tester, 'Downloads/descarga.pdf');
    await put(tester, 'DCIM/foto.jpg');
    await put(tester, 'Screenshots/captura.png');
    await put(tester, 'Instagram/foto.jpg');
    await put(tester, 'WhatsApp Images/img.jpg');
    phoneViewport(tester);
    await precargar(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.explore_outlined));
    await tester.pumpAndSettle();

    // La lista es perezosa: para comprobar las filas de abajo hay que
    // bajar de verdad, no solo buscarlas en el árbol. Y lo de arriba se
    // comprueba antes de bajar, porque el scroll lo saca del árbol.
    expect(find.text('Acceso Rápido'), findsOneWidget);
    expect(find.text('Descargas'), findsOneWidget);
    expect(find.text('Categorías'), findsOneWidget);
    for (var i = 0; i < 8 && find.text('WhatsApp').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -220));
      await tester.pumpAndSettle();
    }

    expect(find.text('Recursos'), findsOneWidget);
    expect(find.text('Cámara'), findsOneWidget);
    expect(find.text('Capturas'), findsOneWidget);
    expect(find.text('NRecorder'), findsOneWidget);
    expect(find.text('Instagram'), findsOneWidget);
    expect(find.text('WhatsApp'), findsOneWidget);
  });

  test('el orden de categorías es el pedido, en los datos', () {
    // La lista es navegación, no una coincidencia. Se comprueba sobre las
    // listas de entradas y no sobre el árbol de widgets: la `ListView` es
    // perezosa y lo que no está en pantalla no existe como nodo.
    expect(
      kQuickEntries().map((e) => e.title).toList(),
      ['Descargas', 'Favoritos'],
    );
    // Hojas, presentaciones y comprimidos tienen entrada propia desde que
    // el sniffer los distingue por contenido. El orden es navegación, no
    // coincidencia: multimedia primero, luego documentos, y el cajón de
    // "Archivos" cerrando la lista.
    expect(kTypeEntries().map((e) => e.title).toList(), [
      'Documentos',
      'Hojas de cálculo',
      'Presentaciones',
      'Comprimidos',
      'Imágenes',
      'Vídeos',
      'Música',
      'Archivos',
      'APKs',
    ]);
    // NRecorder es un marcador deshabilitado, no una carpeta.
    expect(kResourceEntries().map((e) => e.title).toList(), [
      'Cámara',
      'Capturas',
      'NRecorder',
      'Instagram',
      'WhatsApp',
    ]);
    expect(
      kResourceEntries().firstWhere((e) => e.id == 'nrecorder').enabled,
      isFalse,
    );
  });

  test('las ubicaciones van antes que las categorías y marcan el remoto', () {
    expect(kStorageLocations.map((l) => l.title).toList(), [
      'NCloud',
      'Mi Teléfono',
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
    for (final entry in [
      ...kQuickEntries(),
      ...kTypeEntries(),
      ...kResourceEntries(),
    ]) {
      expect(entry.files(controller), isEmpty, reason: entry.title);
    }
  });

  testWidgets('las categorías vacías no se pintan', (tester) async {
    // Solo hay un pdf suelto: media docena de categorías se queda vacía y
    // sus filas desaparecen en vez de llevar a "Nada por aquí".
    await put(tester, 'nota.pdf');
    phoneViewport(tester);
    await precargar(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.explore_outlined));
    await tester.pumpAndSettle();

    // La que tiene contenido sí sale, con su conteo y sin "Vacía".
    expect(find.text('Documentos'), findsOneWidget);
    expect(find.text('1 elemento'), findsOneWidget);
    // Las que no, no: ni fila ni subtítulo de vacío.
    expect(find.text('Imágenes'), findsNothing);
    expect(find.text('Música'), findsNothing);
    expect(find.text('APKs'), findsNothing);
    expect(find.text('Vacía'), findsNothing);
    // Y un grupo sin filas no deja el título colgando.
    expect(find.text('Acceso Rápido'), findsNothing);
  });

  testWidgets('sin nada que enseñar se dice, no se deja en blanco', (
    tester,
  ) async {
    phoneViewport(tester);
    await precargar(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.explore_outlined));
    await tester.pumpAndSettle();

    // El almacenamiento siempre está (hay algo que medir); el resto no.
    expect(find.text('Mi Teléfono'), findsOneWidget);
    expect(find.text('No hay archivos en el almacenamiento'), findsOneWidget);
    expect(find.text('Categorías'), findsNothing);
    // "Recursos" sí sigue, pero solo con el marcador de NRecorder: un
    // marcador deshabilitado no es una categoría vacía.
    expect(find.text('Recursos'), findsOneWidget);
    expect(find.text('Cámara'), findsNothing);
    expect(find.text('Instagram'), findsNothing);
  });

  testWidgets('"Mi Teléfono" mide el almacenamiento y las categorías lo suyo', (
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

    // El bloque de almacenamiento mide con medidor por fila.
    expect(find.byType(NStorageSpecTile), findsNWidgets(2));
    expect(find.text('Mi Teléfono'), findsOneWidget);
    // Imágenes y Documentos tienen 1 cada una.
    expect(find.text('1 elemento'), findsNWidgets(2));
  });
}
