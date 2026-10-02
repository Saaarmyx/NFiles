import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:NexoraCore/NexoraCore.dart';
import 'package:NexoraUi/NexoraUi.dart';
import 'package:NFiles/app/nfiles_app.dart';
import 'package:NFiles/controllers/files_controller.dart';
import 'package:NFiles/services/file_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Base de la app con el núcleo inyectado, para tests de integración.
///
/// Tres decisiones que no son arbitrarias y que costaron una hora de tests
/// colgados:
///
/// - Toda E/S real va dentro de [WidgetTester.runAsync]. Un `await` normal
///   de `dart:io` dentro de `testWidgets` NUNCA completa: el cuerpo del test
///   corre bajo reloj falso y el future de disco no se resuelve.
/// - El servicio usa `useIsolate: false`. Con `compute` (isolate real) el
///   barrido no termina dentro de `runAsync`; en línea sí.
/// - `roots` está acotado a un temporal: si la pantalla creara el
///   controlador, escanearía el `$HOME` del proceso y el test no sería
///   determinista.
class NFilesHarness {
  late Directory tmp;
  late FilesController controller;
  late CorePermissions permissions;
  late CoreLocale locale;
  late CorePerformance performance;

  Future<void> setUp() async {
    tmp = await Directory.systemTemp.createTemp('nfiles_app');
    SharedPreferences.setMockInitialValues({});
    final prefs = CorePrefs.inMemory('nfiles_');
    locale = await CoreLocale.open(prefs);
    performance = await CorePerformance.open(prefs);
    permissions = CorePermissions(
      // El host del test es Linux: se declara para no depender de la
      // máquina donde corra.
      hasRuntimePermissions: true,
    );
    controller = FilesController(
      fileService: FileService(roots: [tmp], useIsolate: false),
    );
  }

  Future<void> tearDown() async {
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

  /// Escribe un archivo dentro del temporal (reloj real).
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

  /// Viewport de móvil: sin esto el kit monta la variante de escritorio.
  static void phoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// Toca un destino de la bottom bar por posición.
  ///
  /// No se calcula por coordenadas: la barra no pinta la etiqueta de cada
  /// destino y su geometría depende de un centrado más holgura y padding
  /// que cambian con el número de destinos. Localizar los gestos en orden
  /// es exacto y no se rompe si el kit cambia el espaciado.
  ///
  /// Se filtran los que tienen `onTap` porque la barra también lleva un
  /// `GestureDetector` de arrastre horizontal (para mover la píldora), y
  /// ese no es un destino.
  static Future<void> tapBarItem(WidgetTester tester, int index) async {
    final items = find.descendant(
      of: find.byType(NBottomBarMobile),
      matching: find.byWidgetPredicate(
        (w) => w is GestureDetector && w.onTap != null,
      ),
    );
    final total = items.evaluate().length;
    if (index >= total) {
      throw StateError('La barra tiene $total destinos; se pidió el $index');
    }
    await tester.tap(items.at(index));
    await tester.pumpAndSettle();
  }

  /// Arrastre horizontal con la velocidad de un dedo.
  ///
  /// Mide el `NMobileLayout` y no la pantalla entera para que el gesto
  /// caiga dentro de la zona deslizable y no sobre la topbar.
  static Future<void> swipe(WidgetTester tester, double dx) async {
    final layout = find.byType(NMobileLayout).first;
    final centro = tester.getCenter(layout);
    final inicio = centro.dx - dx / 2;
    final gesto = await tester.startGesture(Offset(inicio, centro.dy));
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 1; i <= 6; i++) {
      await gesto.moveTo(Offset(inicio + dx * i / 6, centro.dy));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesto.up();
    await tester.pumpAndSettle();
  }
}
