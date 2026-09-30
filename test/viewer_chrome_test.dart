import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:NexoraUi/NexoraUi.dart';
import 'package:NFiles/controllers/files_controller.dart';
import 'package:NFiles/models/file_model.dart';
import 'package:NFiles/screens/files/file_viewer_screen.dart';
import 'package:NFiles/services/file_service.dart';

/// El chrome del visor se monta y se ve al abrir; a los 5 s se oculta
/// solo y un toque en el archivo lo devuelve.
void main() {
  late Directory tmp;
  late FileModel file;

  setUp(() async {
    SharedPreferencesShim.set();
    tmp = await Directory.systemTemp.createTemp('nfiles_chrome');
    final diskFile = File('${tmp.path}/a.jpg');
    await diskFile.writeAsBytes(List.filled(16, 1));
    file = FileModel(
      id: diskFile.path,
      path: diskFile.path,
      title: 'a.jpg',
      dateCreated: DateTime(2026, 1, 10),
      dateModified: DateTime(2026, 1, 10),
      sizeInBytes: 16,
    );
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<void> pumpViewer(WidgetTester tester, {Brightness brightness = Brightness.dark}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.dark
            ? AppTheme.darkTheme
            : AppTheme.lightTheme,
        home: FileViewerScreen(
          controller: FilesController(fileService: FileService(roots: [tmp])),
          initialIndex: 0,
          filesOverride: [file],
        ),
      ),
    );
    await tester.pump();
  }

  for (final brightness in [Brightness.dark, Brightness.light]) {
    testWidgets('las barras del visor se montan visibles en $brightness', (
      tester,
    ) async {
      await pumpViewer(tester, brightness: brightness);

      expect(find.byType(NViewerTopBar), findsOneWidget);
      expect(find.byType(NViewerBottomBar), findsOneWidget);

      final top = tester.getSize(find.byType(NViewerTopBar));
      final bottom = tester.getSize(find.byType(NViewerBottomBar));
      expect(top.height, 64, reason: 'la topbar debe medir 64 como la global');
      expect(bottom.height, greaterThan(0), reason: 'la bottombar debe medir');

      // Chrome opaco al abrir: se ve sobre el archivo.
      final opacities = tester
          .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
          .map((w) => w.opacity)
          .toList();
      expect(opacities, everyElement(1.0));
    });
  }

  testWidgets('se oculta a los 5 s y un toque la devuelve', (tester) async {
    await pumpViewer(tester);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(
      tester.widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity)).map((w) => w.opacity),
      everyElement(0.0),
    );

    await tester.tap(find.byType(InteractiveViewer));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester.widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity)).map((w) => w.opacity),
      everyElement(1.0),
    );
  });
}

/// Evita el arranque real de SharedPreferences en tests.
class SharedPreferencesShim {
  static void set() {}
}
