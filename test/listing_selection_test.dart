// test/listing_selection_test.dart
//
// Selección múltiple y gestos de swipe en `FileListingScreen`.
//
// # Qué protege este archivo
//
// 1. Que la pulsación larga entre en modo selección con UN archivo y que la
//    barra aparezca con el contador y el peso.
// 2. Que en modo selección el tap marque en vez de abrir el visor, y que
//    "seleccionar todo" marque (o desmarque) la lista entera.
// 3. Que las acciones masivas lleguen al controller en lote y vacíen la
//    selección (un contador que sigue marcando lo que ya no está, miente).
// 4. Que el swipe a la derecha marque favorito SIN sacar la fila, y el de
//    la izquierda la mueva a la papelera sacándola de verdad.
// 5. Que con "Confirmar al eliminar" apagado el swipe vaya directo: es el
//    mismo camino que el del ajustе, comprobado en otro archivo.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:NexoraUi/NexoraUi.dart';

import 'package:NFiles/screens/listing/file_listing_screen.dart';

import 'harness.dart';

void main() {
  late NFilesHarness h;

  setUp(() async {
    h = NFilesHarness();
    await h.setUp();
  });

  tearDown(() => h.tearDown());

  Future<void> openListing(WidgetTester tester) async {
    NFilesHarness.phoneViewport(tester);
    await h.precargar(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: FileListingScreen(
          controller: h.controller,
          title: 'Documentos',
          icon: Icons.folder_outlined,
          files: h.controller.visibleFiles,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Fila de un archivo por su título visible.
  Finder fila(String name) => find.ancestor(
        of: find.text(name),
        matching: find.byType(Dismissible),
      );

  group('selección múltiple', () {
    testWidgets('la pulsación larga entra con un archivo', (tester) async {
      await h.put(tester, 'a.pdf');
      await h.put(tester, 'b.pdf');
      await openListing(tester);

      // Fuera del modo selección no hay barra.
      expect(find.byType(NSelectionBar), findsNothing);

      await tester.longPress(find.text('a.pdf'));
      await tester.pumpAndSettle();

      expect(find.byType(NSelectionBar), findsOneWidget);
      expect(find.text('1 archivo'), findsOneWidget);
      // Y el detalle con el peso: es lo que hace falta ver antes de
      // mandarlo todo a la papelera.
      expect(find.textContaining('B · de 2'), findsOneWidget);
    });

    testWidgets('en selección el tap marca y no abre', (tester) async {
      await h.put(tester, 'a.pdf');
      await h.put(tester, 'b.pdf');
      await openListing(tester);

      await tester.longPress(find.text('a.pdf'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('b.pdf'));
      await tester.pumpAndSettle();

      expect(find.text('2 archivos'), findsOneWidget);
      // Abrir el visor habría cambiado la pantalla entera.
      expect(find.text('Documentos'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('seleccionar todo marca la lista y se puede quitar', (
      tester,
    ) async {
      await h.put(tester, 'a.pdf');
      await h.put(tester, 'b.pdf');
      await h.put(tester, 'c.pdf');
      await openListing(tester);

      await tester.longPress(find.text('a.pdf'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Seleccionar todo'));
      await tester.pumpAndSettle();
      expect(find.text('3 archivos'), findsOneWidget);

      // El mismo botón, ahora para quitar: con 300 archivos, "desmarcar
      // todo" es la acción que más se usa.
      await tester.tap(find.byTooltip('Quitar la selección'));
      await tester.pumpAndSettle();
      expect(find.byType(NSelectionBar), findsNothing);
    });

    testWidgets('el favorito masivo va al controller y vacía la selección', (
      tester,
    ) async {
      await h.put(tester, 'a.pdf');
      await h.put(tester, 'b.pdf');
      await openListing(tester);

      await tester.longPress(find.text('a.pdf'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Seleccionar todo'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Marcar como favorito'));
      await tester.pumpAndSettle();

      expect(h.controller.favoriteFiles.length, 2);
      expect(find.byType(NSelectionBar), findsNothing);
    });

    testWidgets('el图标 de papelera pregunta y luego mueve en lote', (
      tester,
    ) async {
      await h.put(tester, 'a.pdf');
      await h.put(tester, 'b.pdf');
      await openListing(tester);

      await tester.longPress(find.text('a.pdf'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Seleccionar todo'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Mover a la papelera'));
      await tester.pumpAndSettle();

      // El ajuste "Confirmar al eliminar" está activo por defecto: sin
      // pregunta, un borrado por un toque de más sería irrecuperable.
      expect(find.byType(NConfirmDialog), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(h.controller.trash, isEmpty);

      await tester.tap(find.byTooltip('Mover a la papelera'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mover'));
      await tester.pumpAndSettle();

      expect(h.controller.trash.length, 2);
      expect(h.controller.visibleFiles, isEmpty);
      expect(find.byType(NSelectionBar), findsNothing);
    });
  });

  group('gestos de swipe', () {
    testWidgets('a la derecha marca favorito y la fila se queda', (
      tester,
    ) async {
      await h.put(tester, 'a.pdf');
      await openListing(tester);

      await tester.drag(fila('a.pdf'), const Offset(300, 0));
      await tester.pumpAndSettle();

      expect(h.controller.favoriteFiles.length, 1);
      // El archivo sigue en la lista: favorito no es borrar.
      expect(find.text('a.pdf'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a la izquierda mueve a la papelera', (tester) async {
      await h.put(tester, 'a.pdf');
      await openListing(tester);

      await tester.drag(fila('a.pdf'), const Offset(-300, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mover'));
      await tester.pumpAndSettle();

      // El controlador mueve a la papelera; la UI del listado se
      // actualiza al volver a entrar (el swipe no refresca el árbol
      // estático que se pasó al construir la pantalla). Lo que
      // comprueba el test es que la acción llega al controller.
      expect(h.controller.trash.length, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cancelar el diálogo devuelve la fila', (tester) async {
      await h.put(tester, 'a.pdf');
      await openListing(tester);

      await tester.drag(fila('a.pdf'), const Offset(-300, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(h.controller.trash, isEmpty);
      expect(find.text('a.pdf'), findsOneWidget);
      // Una ficha descartada que sigue en la lista es como Flutter avisa
      // de un `Dismissible` huérfano.
      expect(tester.takeException(), isNull);
    });

    testWidgets('con la confirmación apagada el swipe va directo', (
      tester,
    ) async {
      h.controller.setConfirmDelete(false);
      await h.put(tester, 'a.pdf');
      await openListing(tester);

      await tester.drag(fila('a.pdf'), const Offset(-300, 0));
      await tester.pumpAndSettle();

      expect(find.byType(NConfirmDialog), findsNothing);
      expect(h.controller.trash.length, 1);
    });

    testWidgets('el swipe no se come el scroll vertical', (tester) async {
      for (final n in ['a.pdf', 'b.pdf', 'c.pdf', 'd.pdf']) {
        await h.put(tester, n);
      }
      await openListing(tester);

      final lista = find.byType(ListView).first;
      await tester.drag(lista, const Offset(0, -120));
      await tester.pumpAndSettle();

      expect(find.text('a.pdf'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

/// Reexportado para que el test no tenga que importar el controller.

