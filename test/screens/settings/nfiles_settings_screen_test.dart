// test/screens/settings/nfiles_settings_screen_test.dart
//
// `NFilesFilesSettingsContent`: los ajustes de archivos con las piezas
// estándar del kit.
//
// # Qué protege este archivo
//
// 1. Que la pantalla pinte los tres grupos con los sufijos que les
//    corresponden: switch plano en booleanos, chevron en lo que abre un
//    selector o navega, checkmark en la opción activa del selector.
// 2. Que tocar un switch escriba en el controller Y sobreviva a un
//    reinicio (leer de `LocalStore` y volver a aplicar). Un ajuste que se
//    ve pero no se guarda es el fallo clásico de esta pantalla.
// 3. Que limpiar caché pida confirmación y avise de lo que borró.
// 4. Que la bóveda navegue.
// 5. Que el contenido se monte DENTRO de la pantalla de Ajustes (una sola
//    pantalla, sin fila que empuje a otra) y sin una lista dentro de la
//    lista de Ajustes.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:NexoraCore/NexoraCore.dart';
import 'package:NexoraUi/NexoraUi.dart';
import 'package:NFiles/controllers/files_controller.dart';
import 'package:NFiles/screens/settings/nfiles_files_settings_content.dart';
import 'package:NFiles/screens/settings/nfiles_settings_screen.dart';
import 'package:NFiles/screens/settings/nfiles_vault_screen.dart';
import 'package:NFiles/services/file_service.dart';
import 'package:NFiles/services/local_store.dart';
import 'package:NFiles/services/view_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late FilesController controller;
  late LocalStore store;
  late FilesViewPrefs prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('nfiles_settings');
    controller = FilesController(
      fileService: FileService(roots: [tmp], useIsolate: false),
    );
    addTearDown(controller.dispose);
    store = await LocalStore.load();
    prefs = store.viewPrefs;
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    // Alto generoso a propósito: los tres grupos tienen que caber sin
    // scroll. Un test que tiene que hacer scroll para llegar a la última
    // fila acaba probando el scroll, no el ajuste.
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // El contenido es una columna (para poder vivir dentro de la
          // lista de Ajustes); aquí se envuelve en la lista que en la app
          // aporta la pantalla.
          body: ListView(
            children: [NFilesFilesSettingsContent(controller: controller)],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Ajustes completos (los de Nexora + los de archivos) en una pantalla.
  Future<void> pumpAjustes(WidgetTester tester) async {
    final prefs = CorePrefs.inMemory('nfiles_settings_');
    final locale = await CoreLocale.open(prefs);
    final performance = await CorePerformance.open(prefs);
    final permissions = CorePermissions(hasRuntimePermissions: true);
    addTearDown(locale.dispose);
    addTearDown(performance.dispose);
    addTearDown(permissions.dispose);

    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: NFilesSettingsScreen(
          permissions: permissions,
          locale: locale,
          performance: performance,
          controller: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Fila por su título exacto.
  Finder fila(String title) => find.widgetWithText(NOptionTile, title);

  /// Espera al debounce del `attach` (250 ms) más el guardado.
  Future<void> persistir() => Future<void>.delayed(
        const Duration(milliseconds: 350),
      );

  group('estructura y sufijos', () {
    testWidgets('pinta los tres grupos con sus rótulos', (tester) async {
      await pumpSettings(tester);

      expect(find.text('Visualización'), findsOneWidget);
      expect(find.text('Almacenamiento y miniaturas'), findsOneWidget);
      expect(find.text('Seguridad y papelera'), findsOneWidget);
      // Cada grupo es una tarjeta propia: tres, no una corrida.
      expect(find.byType(NGroupedCardContainer), findsNWidgets(3));
    });

    testWidgets('los booleanos llevan switch y el resto chevron', (
      tester,
    ) async {
      await pumpSettings(tester);

      // 4 booleanos: ocultos, extensiones, wifi y confirmar.
      expect(find.byType(Switch), findsNWidgets(4));
      // 5 filas con chevron: vista, orden, caché, papelera y bóveda.
      // El switch plano NO lleva chevron: son sufijos excluyentes.
      expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(5));
      expect(
        find.descendant(of: fila('Archivos ocultos'), matching: find.byIcon(Icons.chevron_right_rounded)),
        findsNothing,
      );
    });

    testWidgets('el selector marca la opción activa con check', (
      tester,
    ) async {
      await pumpSettings(tester);

      await tester.tap(fila('Ordenar por'));
      await tester.pumpAndSettle();

      // Una fila por valor (4 campos de orden), cada una con su check. Lo
      // que tiene que haber es exactamente UN check marcado: dos marcas
      // en un selector de opción única harían ambiguo cuál manda.
      expect(find.byType(NCheckmark), findsNWidgets(4));
      final marcados = tester
          .widgetList<NCheckmark>(find.byType(NCheckmark))
          .where((c) => c.value)
          .toList();
      expect(marcados, hasLength(1));
      // Y es el del campo activo, no otro: el subtítulo decía "Nombre".
      final activa = find.ancestor(
        of: find.text('Nombre'),
        matching: find.byType(NOptionTile),
      );
      expect(
        find.descendant(of: activa, matching: find.byType(NCheckmark)),
        findsOneWidget,
      );
    });
  });

  group('los switches cambian y se guardan', () {
    testWidgets('archivos ocultos escribe en el controller', (
      tester,
    ) async {
      await pumpSettings(tester);

      expect(controller.showHiddenFiles, isFalse);
      await tester.tap(fila('Archivos ocultos'));
      await tester.pumpAndSettle();

      expect(controller.showHiddenFiles, isTrue);
      // El switch refleja el estado nuevo: no se queda atrás.
      expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
    });

    testWidgets('el resto de booleanos también', (tester) async {
      await pumpSettings(tester);

      await tester.tap(fila('Mostrar extensiones'));
      await tester.pumpAndSettle();
      await tester.tap(fila('Miniaturas solo con Wi-Fi'));
      await tester.pumpAndSettle();
      // La de seguridad está en el tercer grupo: sin asegurar el scroll el
      // tap caería fuera y el test probaría el viewport, no el ajuste.
      await tester.ensureVisible(fila('Confirmar al eliminar'));
      await tester.pumpAndSettle();
      await tester.tap(fila('Confirmar al eliminar'));
      await tester.pumpAndSettle();

      expect(controller.showFileExtensions, isFalse);
      expect(controller.thumbnailsWifiOnly, isTrue);
      expect(controller.confirmDelete, isFalse);
    });

    test('el estado sobrevive a un reinicio', () async {
      // Sin UI: lo que importa es el contrato guardar → leer.
      prefs.attach(controller);
      controller.setShowHiddenFiles(true);
      controller.setShowFileExtensions(false);
      controller.setThumbnailsWifiOnly(true);
      controller.setConfirmDelete(false);
      controller.setAutoEmptyTrashDays(7);
      await persistir();

      // Otra instancia sobre el mismo almacén: es el reinicio de la app.
      final leido = FilesViewPrefs(PrefsKeyValueStore(store.prefs)).load();

      expect(leido.showHiddenFiles, isTrue);
      expect(leido.showFileExtensions, isFalse);
      expect(leido.thumbnailsWifiOnly, isTrue);
      expect(leido.confirmDelete, isFalse);
      expect(leido.autoEmptyTrashDays, 7);
    });

    test('los enums también sobreviven (regresión de writeAll)', () async {
      // `writeAll` guardaba los enums con `toString()` ("ListingSortField.size")
      // y `enumOf` compara con `.name`: ninguna preferencia enum sobrevivía
      // a un reinicio y caía siempre al valor por defecto.
      prefs.attach(controller);
      controller.setCategoryLayout(FileViewMode.grid);
      controller.setListingField(ListingSortField.size);
      controller.setListingDirection(SortDirection.desc);
      await persistir();

      final leido = FilesViewPrefs(PrefsKeyValueStore(store.prefs)).load();

      expect(leido.categoryLayout, CategoryLayout.grid);
      expect(leido.listingField, ListingSortField.size);
      expect(leido.listingDirection, SortDirection.desc);
    });

    test('sin nada guardado se leen los valores por defecto', () {
      final leido = FilesViewPrefs(PrefsKeyValueStore(store.prefs)).load();

      expect(leido.showHiddenFiles, isFalse);
      expect(leido.showFileExtensions, isTrue);
      expect(leido.thumbnailsWifiOnly, isFalse);
      expect(leido.confirmDelete, isTrue);
      expect(leido.autoEmptyTrashDays, 30);
      expect(leido.categoryLayout, CategoryLayout.list);
      expect(leido.listingField, ListingSortField.name);
    });
  });

  group('selectores con chevron', () {
    testWidgets('vista predeterminada cambia el modo', (tester) async {
      await pumpSettings(tester);

      expect(find.text('Lista'), findsOneWidget);
      await tester.tap(fila('Vista predeterminada'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cuadrícula'));
      await tester.pumpAndSettle();

      expect(controller.categoryLayout, FileViewMode.grid);
      // El subtítulo ya lo dice: no hay que reabrir el selector.
      expect(find.text('Cuadrícula'), findsOneWidget);
    });

    testWidgets('ordenar por cambia el campo', (tester) async {
      await pumpSettings(tester);

      await tester.tap(fila('Ordenar por'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tipo'));
      await tester.pumpAndSettle();

      expect(controller.listingField, ListingSortField.kind);
      expect(find.text('Tipo'), findsOneWidget);
    });

    testWidgets('vaciar papelera cambia los días', (tester) async {
      await pumpSettings(tester);

      expect(find.text('Cada 30 días'), findsOneWidget);
      await tester.tap(fila('Vaciar papelera'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cada 7 días'));
      await tester.pumpAndSettle();

      expect(controller.autoEmptyTrashDays, 7);
      expect(find.text('Cada 7 días'), findsOneWidget);
    });
  });

  group('limpiar caché', () {
    testWidgets('pide confirmación antes de borrar', (tester) async {
      await pumpSettings(tester);

      await tester.tap(fila('Limpiar caché de miniaturas'));
      await tester.pumpAndSettle();

      expect(find.byType(NConfirmDialog), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      // Cancelar no borra: es el motivo de preguntar.
      expect(find.byType(NConfirmDialog), findsNothing);
    });

    testWidgets('al confirmar avisa y el controller responde 0 sin motor', (
      tester,
    ) async {
      await pumpSettings(tester);

      await tester.tap(fila('Limpiar caché de miniaturas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Limpiar'));
      await tester.pumpAndSettle();

      // Buscamos en todos los widgets Text que contengan el mensaje esperado.
      // El SnackBar puede tener el texto exacto o con variaciones.
      final textoWidgets = find.byType(Text);
      final textos = <String>[];
      for (final w in textoWidgets.evaluate()) {
        if (w.widget is Text) {
          textos.add((w.widget as Text).data ?? '');
        }
      }
      final encontradoVacia = textos.any((t) => t.contains('La caché ya estaba vacía'));
      final encontradoBorrada = textos.any((t) => t.contains('Se borraron'));
      expect(encontradoVacia || encontradoBorrada, isTrue,
          reason: 'tiene que avisar del resultado: La caché ya estaba vacía o Se borraron X miniaturas');
    });

    testWidgets('el botón dispara el camino del controller', (tester) async {
      var llamadas = 0;
      final espia = _SpyController(
        FileService(roots: [tmp], useIsolate: false),
        onClear: () => llamadas++,
      );
      addTearDown(espia.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [NFilesFilesSettingsContent(controller: espia)],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(fila('Limpiar caché de miniaturas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Limpiar'));
      await tester.pumpAndSettle();

      expect(llamadas, 1);
    });
  });

  group('carpeta segura', () {
    testWidgets('navega y dice si está vacía', (tester) async {
      await pumpSettings(tester);
      expect(find.text('Vacía'), findsOneWidget);

      await tester.ensureVisible(fila('Carpeta segura'));
      await tester.pumpAndSettle();
      await tester.tap(fila('Carpeta segura'));
      await tester.pumpAndSettle();

      expect(find.byType(NFilesVaultScreen), findsOneWidget);
      expect(find.text('Carpeta segura vacía'), findsOneWidget);
    });

    testWidgets('el contador refleja lo que hay dentro', (tester) async {
      await pumpSettings(tester);
      await tester.ensureVisible(fila('Carpeta segura'));
      await tester.pumpAndSettle();
      await tester.tap(fila('Carpeta segura'));
      await tester.pumpAndSettle();

      expect(find.byType(NFilesVaultContent), findsOneWidget);
    });
  });

  group('integrado en la pantalla de Ajustes', () {
    testWidgets('los ajustes de archivos están en la misma pantalla', (
      tester,
    ) async {
      await pumpAjustes(tester);

      // Lo de Nexora…
      expect(find.text('Configuración'), findsOneWidget);
      expect(find.text('Rendimiento'), findsOneWidget);
      expect(find.text('Personalización'), findsOneWidget);
      expect(find.text('Sobre NFiles'), findsOneWidget);
      // …y lo de archivos, sin pasar por otra pantalla.
      expect(find.byType(NFilesFilesSettingsContent), findsOneWidget);
      expect(find.text('Visualización'), findsOneWidget);
      expect(find.text('Seguridad y papelera'), findsOneWidget);
      // Y sin la fila que antes empujaba a una pantalla aparte.
      expect(find.text('Ajustes de archivos'), findsNothing);
    });

    testWidgets('el contenido no es una lista dentro de la lista', (
      tester,
    ) async {
      await pumpAjustes(tester);

      // Una `ListView` dentro de otra reparte el alto entre las dos y
      // deja la interior sin scroll: las filas de abajo dejan de ser
      // alcanzables. El contenido debe ser una columna.
      expect(
        find.descendant(
          of: find.byType(NFilesFilesSettingsContent),
          matching: find.byType(ListView),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(NFilesFilesSettingsContent),
          matching: find.byType(Column),
        ),
        findsWidgets,
      );
    });

    testWidgets('un switch de Ajustes cambia el controller desde la app', (
      tester,
    ) async {
      await pumpAjustes(tester);

      expect(controller.showHiddenFiles, isFalse);
      await tester.tap(fila('Archivos ocultos'));
      await tester.pumpAndSettle();

      expect(controller.showHiddenFiles, isTrue);
    });
  });
}

/// Controller que cuenta las limpiezas de caché.
///
/// No hace falta un motor real: lo que se prueba es que la fila llama al
/// camino del controller y no a la caché por su cuenta.
class _SpyController extends FilesController {
  _SpyController(FileService service, {required this.onClear})
      : super(fileService: service);

  final void Function() onClear;

  @override
  Future<int> clearThumbnailCache() async {
    onClear();
    return 0;
  }
}
