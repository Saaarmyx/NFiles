// test/view_mode_toggle_test.dart
//
// El botón que alterna lista y cuadrícula.
//
// # Qué protege este archivo
//
// 1. Que el icono muestre el MODO AL QUE SE VA, no el actual. Es contraintuitivo
//    y por eso lleva un test propio.
// 2. Que el estado cambie de verdad en el controller y llegue a persistir.
// 3. Que reconstruir no reescriba la preferencia.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:NFiles/controllers/files_controller.dart';
import 'package:NFiles/widgets/view_mode_toggle.dart';

void main() {
  late FilesController controller;

  setUp(() {
    controller = FilesController();
  });

  tearDown(() {
    controller.dispose();
  });

  Widget wrap() => MaterialApp(
        home: Scaffold(
          body: Center(child: ViewModeToggle(controller: controller)),
        ),
      );

  testWidgets('arranca en lista y muestra el icono de cuadrícula',
      (tester) async {
    expect(controller.categoryLayout, FileViewMode.list);
    await tester.pumpWidget(wrap());

    // El icono es el del modo AL QUE SE VA. Con una lista activa, el botón
    // ofrece pasar a cuadrícula. Mostrar `view_list` junto a una lista
    // parecería "estoy en lista", que es la lectura invertida.
    expect(find.byIcon(Icons.grid_view), findsOneWidget);
    expect(find.byIcon(Icons.view_list), findsNothing);
  });

  testWidgets('pulsar cambia a cuadrícula y el icono se invierte',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.tap(find.byIcon(Icons.grid_view));
    await tester.pump();

    expect(controller.categoryLayout, FileViewMode.grid);
    expect(find.byIcon(Icons.view_list), findsOneWidget);
    expect(find.byIcon(Icons.grid_view), findsNothing);
  });

  testWidgets('pulsar dos veces vuelve al punto de partida', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.tap(find.byIcon(Icons.grid_view));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.view_list));
    await tester.pump();

    expect(controller.categoryLayout, FileViewMode.list);
  });

  testWidgets('el estado sobrevive a reconstruir el widget', (tester) async {
    // El widget no guarda el modo: lo lee del controller. Si lo guardara en
    // su propio `State`, al rotar la pantalla volvería al valor inicial y
    // desincronizándose de lo que hay en el almacenamiento.
    await tester.pumpWidget(wrap());
    await tester.tap(find.byIcon(Icons.grid_view));
    await tester.pump();

    await tester.pumpWidget(wrap());
    await tester.pump();

    expect(controller.categoryLayout, FileViewMode.grid);
    expect(find.byIcon(Icons.view_list), findsOneWidget);
  });

  testWidgets('expone la acción, no el estado, al lector de pantalla',
      (tester) async {
    // Con una lista activa, lo que hace el botón es cambiar A cuadrícula.
    // Anunciar el estado haría que un lector de pantalla dijera "lista" justo
    // antes de que el usuario cambie a cuadrícula.
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(wrap());

    expect(
      find.bySemanticsLabel('Cambiar a cuadrícula'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Cambiar a lista'),
      findsNothing,
    );

    await tester.tap(find.byIcon(Icons.grid_view));
    await tester.pump();
    expect(find.bySemanticsLabel('Cambiar a lista'), findsOneWidget);

    handle.dispose();
  });

  testWidgets('avisa a quien escucha, para que la vista cambie',
      (tester) async {
    var avisos = 0;
    controller.addListener(() => avisos++);
    await tester.pumpWidget(wrap());

    await tester.tap(find.byIcon(Icons.grid_view));
    await tester.pump();
    expect(avisos, greaterThan(0),
        reason: 'sin notificar, la lista no se reconstruye al cambiar de modo');
  });
}
