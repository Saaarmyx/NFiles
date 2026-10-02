// test/file_listing_screen_test.dart
//
// `FileListingScreen`: topbar con atrás + 2 menús y renderizado
// condicional lista/cuadrícula con el orden del popup.
//
// # Qué protege este archivo
//
// 1. Que la pantalla pinte lista (cards del kit en contenedor) o
//    cuadrícula (celdas agrupadas por carpeta) según el modo.
// 2. Que el popup de vista/orden cambie de verdad el modo y el orden.
// 3. Que el menú general ofrezca actualizar.
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

  tearDown(() async {
    await h.tearDown();
  });

  Future<void> pumpListing(
    WidgetTester tester, {
    required String title,
  }) async {
    NFilesHarness.phoneViewport(tester);
    await h.precargar(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: FileListingScreen(
          controller: h.controller,
          title: title,
          icon: Icons.folder_outlined,
          files: h.controller.visibleFiles,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('topbar con atrás, título y los 2 menús', (tester) async {
    await h.put(tester, 'a.pdf');
    await pumpListing(tester, title: 'Documentos');

    expect(find.text('Documentos'), findsOneWidget);
    expect(find.byTooltip('Volver'), findsOneWidget);
    expect(find.byTooltip('Vista y orden'), findsOneWidget);
    expect(find.byTooltip('Más opciones'), findsOneWidget);
    expect(find.byType(NRecentFileCard), findsOneWidget);
  });

  testWidgets('el popup trae modos, campos y dirección', (tester) async {
    await h.put(tester, 'a.pdf');
    await pumpListing(tester, title: 'Documentos');

    await tester.tap(find.byTooltip('Vista y orden'));
    await tester.pumpAndSettle();

    expect(find.text('MODO'), findsOneWidget);
    expect(find.text('Cuadrícula'), findsOneWidget);
    expect(find.text('Lista'), findsOneWidget);
    expect(find.text('ORDENAR POR'), findsOneWidget);
    expect(find.text('Nombre'), findsOneWidget);
    expect(find.text('Tamaño'), findsOneWidget);
    expect(find.text('Fecha de modificación'), findsOneWidget);
    expect(find.text('Tipo'), findsOneWidget);
    expect(find.text('DIRECCIÓN'), findsOneWidget);
    expect(find.text('Ascendente'), findsOneWidget);
    expect(find.text('Descendente'), findsOneWidget);
  });

  testWidgets('cambiar a cuadrícula pinta celdas agrupadas', (tester) async {
    await h.put(tester, 'a.pdf');
    await pumpListing(tester, title: 'Documentos');

    await tester.tap(find.byTooltip('Vista y orden'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cuadrícula'));
    await tester.pumpAndSettle();

    expect(find.byType(NGridFileCard), findsOneWidget);
    expect(find.byType(NRecentFileCard), findsNothing);
  });

  testWidgets('ordenar por tamaño descendente reordena', (tester) async {
    await h.put(tester, 'a.pdf', size: 10);
    await h.put(tester, 'b.pdf', size: 200);
    await pumpListing(tester, title: 'Documentos');

    // Nombre ascendente por defecto: a.pdf primero.
    var yA = tester.getTopLeft(find.text('a.pdf')).dy;
    var yB = tester.getTopLeft(find.text('b.pdf')).dy;
    expect(yA, lessThan(yB));

    await tester.tap(find.byTooltip('Vista y orden'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tamaño'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Vista y orden'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descendente'));
    await tester.pumpAndSettle();

    yA = tester.getTopLeft(find.text('a.pdf')).dy;
    yB = tester.getTopLeft(find.text('b.pdf')).dy;
    expect(yB, lessThan(yA));
  });

  testWidgets('el menú general ofrece actualizar', (tester) async {
    await h.put(tester, 'a.pdf');
    await pumpListing(tester, title: 'Documentos');

    await tester.tap(find.byTooltip('Más opciones'));
    await tester.pumpAndSettle();

    expect(find.text('Actualizar'), findsOneWidget);
  });

  testWidgets('sin archivos dice dónde está vacía', (tester) async {
    await pumpListing(tester, title: 'Documentos');

    expect(find.text('Nada por aquí'), findsOneWidget);
    expect(find.text('No hay archivos en Documentos.'), findsOneWidget);
  });
}
