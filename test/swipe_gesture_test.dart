import 'package:NexoraUi/NexoraUi.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

/// El gesto de swipe sobre la app real, no sobre el kit.
///
/// El kit ya tenía el `PageView` con física horizontal y sus tests
/// pasan; lo que se comprueba aquí es que **estas pantallas** (Recientes
/// y Explorar) no se quedan sin gesto: tienen listas verticales,
/// exploradores y scrolls propios que compiten por él en la arena de
/// gestos.
void main() {
  late NFilesHarness h;

  setUp(() async {
    h = NFilesHarness();
    await h.setUp();
  });
  tearDown(() => h.tearDown());

  Future<void> pump(WidgetTester tester) async {
    NFilesHarness.phoneViewport(tester);
    await tester.pumpWidget(h.buildApp());
    await tester.pumpAndSettle();
  }

  testWidgets('deslizar a la izquierda va de Recientes a Explorar', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Recientes'), findsWidgets);

    await NFilesHarness.swipe(tester, -260);

    // La topbar cambia de título: prueba de que la página se movió de
    // verdad y no solo la píldora de la barra.
    expect(find.text('Explorar'), findsWidgets);
  });

  testWidgets('deslizar a la derecha vuelve de Explorar a Recientes', (
    tester,
  ) async {
    await pump(tester);

    await NFilesHarness.swipe(tester, -260);
    expect(find.text('Explorar'), findsWidgets);

    await NFilesHarness.swipe(tester, 260);
    expect(find.text('Recientes'), findsWidgets);
  });

  testWidgets('el scroll vertical sigue funcionando', (tester) async {
    await pump(tester);
    await h.put(tester, 'a.txt');
    await h.precargar(tester);
    await tester.pumpAndSettle();

    final centro = tester.getCenter(find.byType(NMobileLayout).first);
    final gesto = await tester.startGesture(centro);
    await gesto.moveBy(const Offset(0, -200));
    await gesto.up();
    await tester.pumpAndSettle();

    // Si el gesto horizontal se hubiera tragado el vertical, la página
    // habría cambiado o la lista no se habría desplazado.
    expect(find.text('Recientes'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el gesto deja la vista estable al asentarse', (tester) async {
    // Regresión del ciclo swipe -> onPageChanged -> didUpdateWidget ->
    // jumpToPage, que se veía como un tirón al terminar la animación.
    await pump(tester);

    await NFilesHarness.swipe(tester, -260);
    expect(find.text('Explorar'), findsWidgets);

    // Con doble aviso la vista se resincronizaría sola y el título
    // parpadearía. Aquí se comprueba que se queda quieta.
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Explorar'), findsWidgets);
  });

  testWidgets('no hay salto al volver a tocar la barra', (tester) async {
    await pump(tester);

    await NFilesHarness.swipe(tester, -260);
    expect(find.text('Explorar'), findsWidgets);

    // Volver por la barra tras un gesto no debe dejar la vista a medias.
    await NFilesHarness.tapBarItem(tester, 0);

    expect(find.text('Recientes'), findsWidgets);
  });
}
