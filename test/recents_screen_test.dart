// test/recents_screen_test.dart
//
// Pantalla "Recientes": top bar propia, popup por secciones y cards del kit.
//
// # Qué protege este archivo
//
// 1. Que el listado pinte [NRecentFileCard] con `"{Peso} • {Origen}"` y no
//    otra fila: es el contrato visual de la pantalla.
// 2. Que el popup ⋮ de Recientes traiga exactamente las dos secciones
//    acordadas (modo de vista + ajustes con Cuenta y Configuración).
import 'dart:io';
import 'dart:typed_data';

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

  testWidgets('renderiza cada archivo como NRecentFileCard con peso y origen',
      (tester) async {
    await h.put(tester, 'informe.pdf');
    NFilesHarness.phoneViewport(tester);
    await h.precargar(tester);
    await tester.pumpWidget(h.buildApp());
    await tester.pumpAndSettle();

    // Una card por archivo, con el subtítulo "{Peso} • {Origen}".
    expect(find.byType(NRecentFileCard), findsOneWidget);
    expect(find.text('informe.pdf'), findsOneWidget);
    expect(find.textContaining('32 B • '), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsWidgets);
  });

  testWidgets('los archivos de hace más de 7 días quedan fuera', (
    tester,
  ) async {
    await h.put(tester, 'nuevo.pdf');
    await h.put(tester, 'viejo.pdf');
    // Envejece solo el mtime: el filtro de Recientes mira la modificación.
    final old = File('${h.tmp.path}/viejo.pdf');
    await tester.runAsync(() async {
      old.setLastModifiedSync(
        DateTime.now().subtract(const Duration(days: 10)),
      );
    });
    NFilesHarness.phoneViewport(tester);
    await h.precargar(tester);
    await tester.pumpWidget(h.buildApp());
    await tester.pumpAndSettle();

    expect(find.text('nuevo.pdf'), findsOneWidget);
    expect(find.text('viejo.pdf'), findsNothing);
    // Solo el reciente pide card (y miniatura).
    expect(find.byType(NRecentFileCard), findsOneWidget);
  });

  testWidgets('el popup trae modo de vista y ajustes con Cuenta', (
    tester,
  ) async {
    NFilesHarness.phoneViewport(tester);
    await h.precargar(tester);
    await tester.pumpWidget(h.buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Más opciones'));
    await tester.pumpAndSettle();

    expect(find.text('MODO DE VISTA'), findsOneWidget);
    expect(find.text('Por fecha'), findsOneWidget);
    expect(find.text('Compacto'), findsOneWidget);
    expect(find.text('AJUSTES'), findsOneWidget);
    expect(find.text('Cuenta'), findsOneWidget);
    expect(find.text('Configuración'), findsOneWidget);
  });

  testWidgets('Cuenta abre la pantalla de cuenta', (tester) async {
    NFilesHarness.phoneViewport(tester);
    await h.precargar(tester);
    await tester.pumpWidget(h.buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Más opciones'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cuenta'));
    await tester.pumpAndSettle();

    // La cuenta de NFiles vive en la pantalla de nube del kit.
    expect(find.byType(NCloudScreen), findsOneWidget);
  });

  testWidgets('una imagen muestra su miniatura, no el icono azul', (
    tester,
  ) async {
    final file = File('${h.tmp.path}/foto.png');
    await tester.runAsync(() => file.writeAsBytes(_png1x1));
    NFilesHarness.phoneViewport(tester);
    await h.precargar(tester);
    await tester.pumpWidget(h.buildApp());
    await tester.pumpAndSettle();

    expect(find.text('foto.png'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(NIconTile), findsNothing);
  });

  testWidgets('compacto agrupa por día sin cabeceras de texto', (
    tester,
  ) async {
    await h.put(tester, 'a.jpg');
    NFilesHarness.phoneViewport(tester);
    await h.precargar(tester);
    await tester.pumpWidget(h.buildApp());
    await tester.pumpAndSettle();

    // Por fecha: cabecera estilizada + tarjeta de grupo.
    expect(find.text('Hoy • 1 elemento'), findsOneWidget);
    expect(find.byType(NGroupedCardContainer), findsOneWidget);

    await tester.tap(find.byTooltip('Más opciones'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compacto'));
    await tester.pumpAndSettle();

    // Compacto: la card y su tarjeta de grupo siguen, la cabecera no.
    expect(find.byType(NRecentFileCard), findsOneWidget);
    expect(find.byType(NGroupedCardContainer), findsOneWidget);
    expect(find.text('Hoy • 1 elemento'), findsNothing);
  });
}

/// PNG de 1x1 para probar miniaturas reales sin assets.
final _png1x1 = Uint8List.fromList(const [
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82,
  0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137,
  0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 96, 24, 5, 163, 96,
  20, 140, 2, 0, 3, 152, 0, 143, 47, 158, 234, 102, 0, 0, 0, 0,
  73, 69, 78, 68, 174, 66, 96, 130,
]);
