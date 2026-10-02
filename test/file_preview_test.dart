// test/file_preview_test.dart
//
// El enrutado y la pantalla de previsualización.
//
// # Qué protege este archivo
//
// 1. Que el enrutado elija el visor correcto por tipo de archivo.
// 2. Que un archivo de texto se pinte con `NTextViewer` y no con el visor de
//    medios, que lo abriría en un `PageView` sin sentido.
// 3. Que un PDF no se deje en blanco: dice lo que sabe del documento.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:NFiles/controllers/files_controller.dart';
import 'package:NFiles/models/file_model.dart';
import 'package:NFiles/screens/files/file_preview_screen.dart';
import 'package:NexoraUi/NexoraUi.dart';

FileModel archivo(String ruta, {String? titulo}) => FileModel(
      id: ruta,
      path: ruta,
      title: titulo ?? ruta.split('/').last,
      dateCreated: DateTime(2026, 1, 1),
      dateModified: DateTime(2026, 1, 2),
      sizeInBytes: 100,
      isFavorite: false,
      isVideo: false,
    );

void main() {
  late FilesController controller;
  late Directory dir;

  setUp(() {
    controller = FilesController();
    dir = Directory.systemTemp.createTempSync('nfiles_preview');
  });

  tearDown(() {
    controller.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  String en(String nombre) => '${dir.path}/$nombre';

  /// Monta la pantalla y deja que la lectura del disco termine.
  ///
  /// # Por qué `runAsync` ENVUELVE TODO y no solo un `pump` de más
  ///
  /// La pantalla lee el archivo en un `await`, y eso es E/S real. Bajo el
  /// reloj falso de `testWidgets`, `pump()` avanza la animación pero no deja
  /// que la E/S se complete, así que la pantalla se queda con el indicador
  /// de carga para siempre y `find.byType(NTextViewer)` no encuentra nada.
  ///
  /// Hacer un `await tester.runAsync(() => delay(...))` suelta NO sirve: el
  /// hueco del reloj real cae FUERA del tramo que el widget considera su
  /// zona, y la continuación del `await` se programa en la zona equivocada.
  /// Hay que meter el `pumpWidget` y el `pump` final DENTRO del `runAsync`.
  Future<void> montar(
    WidgetTester tester,
    FileModel file,
  ) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: FilePreviewScreen(file: file, controller: controller),
      ));
      // Margen para la lectura. Va holgado a propósito: en una máquina
      // cargada el `File.length()` puede tardar, y un margen corto produce
      // un test que pasa en local y falla en CI.
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await tester.pump();
    });
  }

  group('decideViewerFor', () {
    test('el código va al visor de texto', () {
      for (final p in ['a.dart', 'b.rs', 'c.py', 'd.json', 'e.yaml', 'f.sh']) {
        expect(decideViewerFor(p), PreviewKind.text, reason: p);
      }
    });

    test('un PDF va al visor de PDF, no al de texto', () {
      // `.pdf` cae en `document`, igual que un `.docx` o un `.txt`. Si no se
      // separara por extensión, un PDF de 300 páginas se abriría como un
      // archivo de texto con un guion binario dentro.
      expect(decideViewerFor('a.pdf'), PreviewKind.pdf);
      expect(decideViewerFor('a.PDF'), PreviewKind.pdf,
          reason: 'la extensión va en mayúsculas a menudo');
    });

    test('el texto plano va al visor de texto', () {
      for (final p in ['a.txt', 'b.md', 'c.log', 'd.ini', 'e.conf']) {
        expect(decideViewerFor(p), PreviewKind.text, reason: p);
      }
    });

    test('los medios van al visor de medios', () {
      expect(decideViewerFor('a.jpg'), PreviewKind.media);
      expect(decideViewerFor('a.mp4'), PreviewKind.media);
      expect(decideViewerFor('a.mp3'), PreviewKind.media);
    });

    test('un APK va al inspector, no a "sin vista previa"', () {
      // Antes caía en `unsupported` con el resto. Si vuelve a caer ahí, el
      // inspector existe pero nadie lo abre.
      expect(decideViewerFor('a.apk'), PreviewKind.apk);
      expect(decideViewerFor('a.APK'), PreviewKind.apk,
          reason: 'la extensión va en mayúsculas a menudo');
    });

    test('lo que no se puede mostrar cae en "sin vista previa"', () {
      for (final p in ['a.zip', 'c.xlsx', 'd.pptx', 'e.iso']) {
        expect(decideViewerFor(p), PreviewKind.unsupported, reason: p);
      }
    });

    test('un nombre sin extensión no rompe', () {
      expect(decideViewerFor('sin-extension'), PreviewKind.unsupported);
    });

    test('un punto final no rompe', () {
      // Un archivo que se llama solo "algo." es legal en algunos sistemas.
      expect(() => decideViewerFor('algo.'), returnsNormally);
    });

    test('una ruta vacía no rompe', () {
      expect(() => decideViewerFor(''), returnsNormally);
    });
  });

  group('la pantalla de texto', () {
    testWidgets('pinta el contenido con NTextViewer', (tester) async {
      File(en('a.txt')).writeAsStringSync('primera linea\nsegunda linea');
      final file = archivo(en('a.txt'));

      await montar(tester, file,);

      expect(find.byType(NTextViewer), findsOneWidget);
      expect(find.textContaining('primera linea'), findsOneWidget);
    });

    testWidgets('un archivo de código lleva números de línea',
        (tester) async {
      File(en('a.dart')).writeAsStringSync('void main() {}');
      final file = archivo(en('a.dart'));

      await montar(tester, file,);

      // El código se numera; un `.txt` proselto no, porque un número cada
      // cuatro palabras es ruido.
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('un .txt NO lleva números de línea', (tester) async {
      File(en('a.txt')).writeAsStringSync('un parrafo largo de texto');
      final file = archivo(en('a.txt'));

      await montar(tester, file,);

      expect(find.text('1'), findsNothing);
    });

    testWidgets('un binario renombrado a .txt se declara, no se pinta',
        (tester) async {
      // Un ZIP con nombre de texto: si se intentara pintar, saldrían
      // 200.000 caracteres de control y el usuario no podría hacer nada.
      final bytes = List<int>.filled(20000, 0x41);
      for (var i = 0; i < 200; i++) {
        bytes[i * 100] = 0x00;
      }
      File(en('falso.txt')).writeAsBytesSync(bytes);

      await montar(tester, archivo(en('falso.txt')));

      expect(find.text('Este archivo no es texto'), findsOneWidget);
      expect(find.byType(NTextViewer), findsNothing);
    });

    testWidgets('un archivo vacío lo dice', (tester) async {
      File(en('cero.txt')).writeAsBytesSync(const <int>[]);
      await montar(tester, archivo(en('cero.txt')));

      expect(find.text('Archivo vacío'), findsOneWidget);
    });

    testWidgets('una ruta que no existe no rompe la pantalla',
        (tester) async {
      // El archivo se borró entre la lista y el toque. La pantalla tiene que
      // pintar algo, no tirar.
      await montar(tester, archivo(en('fantasma.txt')));

      expect(tester.takeException(), isNull);
      expect(find.byType(NTextViewer), findsNothing);
    });

    testWidgets('un archivo por encima del tope se declara truncado',
        (tester) async {
      // El tope por defecto son 8 MiB, así que 9 ya lo pasa. Un solo
      // montaje a propósito: volver a montar reutiliza el mismo `State` y
      // `initState` no vuelve a correr, así que la pantalla seguiría
      // mostrando el archivo anterior.
      final enorme = 'a' * (9 * 1024 * 1024);
      File(en('enorme.txt')).writeAsStringSync(enorme);

      await montar(tester, archivo(en('enorme.txt')));

      // Lo que se declara NO es "se ha leído todo": el usuario tiene que
      // saber que le falta contenido, o creerá que el archivo acaba ahí.
      expect(find.textContaining('Mostrando los primeros'), findsOneWidget);
    });
  });

  group('la pantalla de PDF', () {
    testWidgets('un PDF válido dice cuántas páginas tiene', (tester) async {
      final buf = StringBuffer();
      buf.write('%PDF-1.7\n');
      buf.write('/Type /Pages /Kids [3 0 R] /Count   12\n');
      buf.write('%%EOF');
      File(en('a.pdf')).writeAsStringSync(buf.toString());

      await montar(tester, archivo(en('a.pdf')),);

      expect(find.text('12 páginas'), findsOneWidget);
    });

    testWidgets('un PDF cifrado lo declara', (tester) async {
      File(en('c.pdf')).writeAsStringSync(
        '%PDF-1.7\n/Encrypt 9 0 R\n/Type /Pages /Count 3\n%%EOF',
      );
      await montar(tester, archivo(en('c.pdf')),);

      expect(find.text('PDF cifrado'), findsOneWidget);
    });

    testWidgets('un archivo que no es PDF lo declara', (tester) async {
      File(en('falso.pdf')).writeAsStringSync('esto no es un pdf');
      await montar(tester, archivo(en('falso.pdf')));

      expect(find.text('No es un PDF válido'), findsOneWidget);
    });

    testWidgets('no se queda en blanco', (tester) async {
      // El fallo que este test cierra: sin motor de PDF, la versión previa
      // abría una pantalla negra sin texto. El usuario no puede distinguir
      // "no puedo mostrarlo" de "la app se ha roto".
      File(en('a.pdf')).writeAsStringSync('%PDF-1.7\n/Count 5\n%%EOF');
      await montar(tester, archivo(en('a.pdf')),);

      expect(find.byType(Text), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('tipos sin visor', () {
    testWidgets('un ZIP lo declara', (tester) async {
      File(en('a.zip')).writeAsBytesSync(const [0x50, 0x4B, 0x03, 0x04]);
      await montar(tester, archivo(en('a.zip')),);

      expect(find.text('Sin vista previa'), findsOneWidget);
    });

    test('la decisión se toma antes de construir la pantalla', () {
      // No hace falta montar nada para saber que un ZIP no tiene vista
      // previa: el enrutado es una función pura, y por eso se puede probar
      // sin widget.
      expect(decideViewerFor('a.zip'), PreviewKind.unsupported);
    });
  });
}
