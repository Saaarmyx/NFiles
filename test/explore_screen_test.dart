// test/explore_screen_test.dart
//
// Pantalla "Explorar": cuatro bloques, la regla de lo vacío y Favoritos
// condicional.
//
// # Qué protege este archivo
//
// 1. Que un grupo con 0 filas no se pinte (ni su título): nueve tarjetas
//    que llevan a "Nada por aquí" son peor que ninguna.
// 2. Que NRecorder se pinte siempre: es un marcador deshabilitado, no una
//    categoría vacía, y su subtítulo ya dice "Próximamente".
// 3. Que "Favoritos" solo salga en Acceso Rápido cuando hay favoritos
//    (locales o de NPhotos).
// 4. Que Instagram y WhatsApp resuelvan sus carpetas sin fallar.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:NexoraUi/NexoraUi.dart';

import 'harness.dart';

void main() {
  late NFilesHarness h;

  setUp(() async {
    h = NFilesHarness();
    await h.setUp();
  });

  tearDown(() async {
    await h.tearDown();
  });

  Future<void> openExplore(WidgetTester tester) async {
    NFilesHarness.phoneViewport(tester);
    await h.precargar(tester);
    await tester.pumpWidget(h.buildApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.explore_outlined));
    await tester.pumpAndSettle();
  }

  /// Baja hasta que aparezca [texto] (o se agote el scroll).
  Future<void> scrollTo(WidgetTester tester, String texto) async {
    for (var i = 0; i < 8 && find.text(texto).evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -220));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('los cuatro bloques con almacenamiento medido', (tester) async {
    // Un archivo por grupo para que los tres tengan filas: con la regla de
    // lo vacío, un grupo sin contenido ni siquiera pone su título.
    await h.put(tester, 'Downloads/descarga.pdf');
    await h.put(tester, 'nota.pdf');
    await h.put(tester, 'DCIM/foto.jpg');
    await openExplore(tester);

    // Arriba: almacenamiento medido por fila.
    expect(find.text('Almacenamiento'), findsOneWidget);
    expect(find.byType(NStorageSpecTile), findsNWidgets(2));
    expect(find.text('NCloud'), findsOneWidget);
    expect(find.text('Mi Teléfono'), findsOneWidget);
    expect(find.text('Acceso Rápido'), findsOneWidget);

    await scrollTo(tester, 'WhatsApp');

    // Abajo: recursos (lo intermedio se comprueba en app_test, porque el
    // scroll saca del árbol lo que queda lejos).
    expect(find.text('Recursos'), findsOneWidget);
  });

  testWidgets('un grupo sin contenido no pone ni filas ni título', (
    tester,
  ) async {
    // Solo un pdf: Descargas, Favoritos, Imágenes, Música… se quedan vacíos.
    await h.put(tester, 'nota.pdf');
    await openExplore(tester);

    expect(find.text('Documentos'), findsOneWidget);
    expect(find.text('Acceso Rápido'), findsNothing);
    expect(find.text('Descargas'), findsNothing);
    expect(find.text('Imágenes'), findsNothing);
  });

  testWidgets('sin favoritos no hay fila de Favoritos', (tester) async {
    await h.put(tester, 'Downloads/descarga.pdf');
    await openExplore(tester);

    expect(find.text('Descargas'), findsOneWidget);
    expect(find.text('Favoritos'), findsNothing);
  });

  testWidgets('con favoritos aparece en Acceso Rápido', (tester) async {
    await h.put(tester, 'nota.pdf');
    NFilesHarness.phoneViewport(tester);
    await h.precargar(tester);
    await tester.runAsync(() => h.controller.toggleFavorite(
          '${h.tmp.path}/nota.pdf',
        ));
    await tester.pumpWidget(h.buildApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.explore_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Favoritos'), findsOneWidget);
  });

  testWidgets('NRecorder no navega a ninguna parte', (tester) async {
    await openExplore(tester);

    await scrollTo(tester, 'NRecorder');
    expect(find.text('NRecorder'), findsOneWidget);
    expect(find.text('Próximamente'), findsOneWidget);

    await tester.tap(find.text('NRecorder'));
    await tester.pumpAndSettle();

    // Sin navegación: no hay categoría vacía ni pantalla nueva.
    expect(find.text('Nada por aquí'), findsNothing);
  });

  testWidgets('las tarjetas respiran: no van pegadas a los bordes', (
    tester,
  ) async {
    await openExplore(tester);

    final rect = tester.getRect(find.byType(NGroupedCardContainer).first);
    expect(rect.left, NSpacing.spaceMd);
    expect(rect.right, 360 - NSpacing.spaceMd);
  });

  testWidgets('los grupos no llevan rayas divisorias', (tester) async {
    await openExplore(tester);

    for (final c in find.byType(NGroupedCardContainer).evaluate()) {
      expect(
        find.descendant(
          of: find.byWidget(c.widget),
          matching: find.byType(Divider),
        ),
        findsNothing,
      );
    }
  });

  testWidgets('todos los iconos comparten el acento de la app', (
    tester,
  ) async {
    await openExplore(tester);

    // Marcos de 40x40 con radio 12: los de las filas y los de NIconTile.
    // (`Container` guarda el tamaño en `constraints`, no en props.)
    bool isFrame(Widget w) {
      if (w is! Container) return false;
      final constraints = w.constraints;
      if (constraints?.maxWidth != 40 || constraints?.maxHeight != 40) {
        return false;
      }
      final decoration = w.decoration;
      return decoration is BoxDecoration &&
          decoration.borderRadius == BorderRadius.circular(12);
    }

    final frames = find.byWidgetPredicate(isFrame);
    expect(frames, findsWidgets);
    final colors = {
      for (final c in tester.widgetList<Container>(frames))
        (c.decoration as BoxDecoration).color,
    };
    expect(colors.length, 1, reason: 'un solo color de icono en Explorar');
    final primary =
        Theme.of(tester.element(find.text('Mi Teléfono'))).colorScheme.primary;
    expect(colors.single, primary);
  });

  testWidgets('Instagram y WhatsApp resuelven sus carpetas', (tester) async {
    await h.put(tester, 'Instagram/foto.jpg');
    await h.put(tester, 'WhatsApp Images/img.jpg');
    await openExplore(tester);

    for (var i = 0; i < 8 && find.text('WhatsApp').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -220));
      await tester.pumpAndSettle();
    }

    expect(find.text('Instagram'), findsOneWidget);
    expect(find.text('WhatsApp'), findsOneWidget);
    expect(find.text('1 elemento'), findsNWidgets(2));
  });
}
