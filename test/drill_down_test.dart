// test/drill_down_test.dart
//
// Entrar en un subdirectorio y ver lo que hay dentro.
//
// # Qué protege este archivo
//
// 1. Que `navigateTo` traiga las SUBCARPETAS, no solo archivos. Es el fallo
//    de fondo: el listado anterior venía de un escaneo en profundidad que
//    solo devolvía archivos, así que no había drill-down posible.
// 2. Que las carpetas queden separadas de los archivos y ordenadas por
//    nombre, antes que ellos.
// 3. Que una carpeta se pinte con el componente del kit y que su toque entre
//    en ella.
// 4. Que una carpeta NO se pueda abrir en el visor, que es el error que
//    aparecería si las carpetas fueran `FileModel`.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:NFiles/controllers/files_controller.dart';
import 'package:NFiles/models/directory_entry.dart';
import 'package:NFiles/models/file_model.dart';
import 'package:NFiles/widgets/file_row.dart';
import 'package:NFiles/screens/listing/file_listing_screen.dart';
import 'package:NexoraCore/NexoraCore.dart';
import 'package:NexoraUi/NexoraUi.dart';

/// Entrada nativa de una carpeta.
FileEntry carpetaNativa(String path) => FileEntry(
      path: path,
      name: path.split('/').last,
      type: EntryType.directory,
      size: 0,
      modified: DateTime(2026, 1, 1),
      created: DateTime(2026, 1, 1),
      kind: null,
      isHidden: false,
    );

/// Entrada nativa de un archivo.
FileEntry archivoNativo(String path) => FileEntry(
      path: path,
      name: path.split('/').last,
      type: EntryType.file,
      size: 10,
      modified: DateTime(2026, 1, 2),
      created: DateTime(2026, 1, 1),
      kind: FileKind.document,
      isHidden: false,
    );

void main() {
  late FilesController controller;
  late Directory raiz;
  final pedidos = <String>[];

  setUp(() {
    controller = FilesController();
    pedidos.clear();
    raiz = Directory.systemTemp.createTempSync('nfiles_drill');
  });

  tearDown(() {
    controller.dispose();
    if (raiz.existsSync()) raiz.deleteSync(recursive: true);
  });

  /// Simula un arbol: `listDirectory` devuelve lo que se le pase.
  void conArbol(Map<String, List<FileEntry>> arbol) {
    controller.debugSetDirectoryLister((path) {
      pedidos.add(path);
      return arbol[path] ?? const [];
    });
  }

  /// Crea en disco un arbol de verdad, para el test de widgets.
  void arbolReal(String dir, List<String> carpetas, List<String> archivos) {
    for (final c in carpetas) {
      Directory('$dir/$c').createSync(recursive: true);
    }
    for (final f in archivos) {
      File('$dir/$f').writeAsStringSync('x');
    }
  }

  group('el listado trae carpetas', () {
    test('navigateTo separa carpetas de archivos', () async {
      final d = raiz.path;
      conArbol({
        d: [
          archivoNativo('$d/a.txt'),
          carpetaNativa('$d/Fotos'),
          carpetaNativa('$d/Documentos'),
        ],
      });

      await controller.navigateTo(d);

      // Las carpetas NO se mezclan con los archivos. Si se mezclaran, una
      // carpeta acabaria en la lista del visor, que no sabe abrirla.
      expect(controller.currentFolders.map((c) => c.name).toList(),
          ['Documentos', 'Fotos']);
      expect(controller.browsableFiles.map((f) => f.title).toList(), ['a.txt']);
    });

    test('las carpetas se ordenan por nombre', () async {
      final d = raiz.path;
      conArbol({
        d: [
          carpetaNativa('$d/zeta'),
          carpetaNativa('$d/Alfa'),
          carpetaNativa('$d/mediana'),
        ],
      });

      await controller.navigateTo(d);
      // Ordenar aquí y no en el motor: `read_dir` devuelve en el orden que
      // el sistema de archivos quiera, que cambia entre dispositivos.
      expect(controller.currentFolders.map((c) => c.name).toList(),
          ['Alfa', 'mediana', 'zeta']);
    });

    test('una carpeta lleva su ruta completa, no solo el nombre', () async {
      final d = raiz.path;
      conArbol({
        d: [carpetaNativa('$d/Fotos/Viaje')],
      });
      await controller.navigateTo(d);

      // Sin la ruta completa no se puede navegar al pulsar: el breadcrumb y
      // `navigateTo` trabajan con rutas, no con nombres.
      expect(controller.currentFolders.single.path, '$d/Fotos/Viaje');
    });

    test('entra en la subcarpeta y ve SU contenido', () async {
      final d = raiz.path;
      conArbol({
        d: [carpetaNativa('$d/Fotos')],
        '$d/Fotos': [
          archivoNativo('$d/Fotos/uno.jpg'),
          carpetaNativa('$d/Fotos/2024'),
        ],
      });

      await controller.navigateTo(d);
      final destino = controller.currentFolders.single.path;
      await controller.navigateTo(destino);

      // Al entrar, la lista es la de la subcarpeta, no la de la anterior.
      expect(controller.currentPath, '$d/Fotos');
      expect(controller.browsableFiles.map((f) => f.title).toList(), ['uno.jpg']);
      expect(controller.currentFolders.map((c) => c.name).toList(), ['2024']);
    });

    test('el breadcrumb crece al entrar', () async {
      final d = raiz.path;
      conArbol({
        d: [carpetaNativa('$d/A')],
        '$d/A': [carpetaNativa('$d/A/B')],
      });

      await controller.navigateTo(d);
      await controller.navigateTo(controller.currentFolders.single.path);
      await controller.navigateTo(controller.currentFolders.single.path);

      expect(controller.currentPath, '$d/A/B');
      expect(controller.navigationHistory, ['$d/A/B', '$d/A', d]);
    });

    test('un directorio vacío no da carpetas ni archivos', () async {
      final d = raiz.path;
      conArbol({d: const []});
      await controller.navigateTo(d);

      expect(controller.currentFolders, isEmpty);
      expect(controller.browsableFiles, isEmpty);
      // Pero la navegación sigue siendo válida: se puede volver con el
      // breadcrumb.
      expect(controller.currentPath, d);
    });

    test('navegar a una carpeta sin permiso no lanza', () async {
      final d = raiz.path;
      controller.debugSetDirectoryLister((_) => throw const FileSystemException('sin permiso'));
      await expectLater(controller.navigateTo(d), completes);
      expect(controller.currentFolders, isEmpty);
    });
  });

  group('DirectoryEntry', () {
    test('se construye desde una entrada nativa', () {
      final e = carpetaNativa('/a/b/Fotos');
      final d = DirectoryEntry.fromNative(e);
      expect(d.path, '/a/b/Fotos');
      expect(d.name, 'Fotos');
      expect(d.hidden, isFalse);
    });

    test('dos entradas de la misma ruta son la misma carpeta', () {
      // Por ruta y no por contenido: al entrar y salir de un directorio, el
      // mtime puede haber cambiado y la carpeta sigue siendo la misma. Con
      // igualdad por contenido, aparecería como una carpeta nueva.
      final a = DirectoryEntry(
          path: '/a', name: 'a', modified: DateTime(2026, 1, 1));
      final b = DirectoryEntry(
          path: '/a', name: 'a', modified: DateTime(2026, 5, 5));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('NO se puede construir un FileModel desde una carpeta', () {
      // El compilador ya lo impide por el tipo: `DirectoryEntry` no es
      // asignable a `FileModel`. Este test documenta el motivo del modelo
      // mas que comprobar una propiedad del lenguaje.
      final d = DirectoryEntry.fromNative(carpetaNativa('/a/Fotos'));
      expect(d, isA<DirectoryEntry>());
      expect(d, isNot(isA<FileModel>()));
    });
  });

  group('la pantalla pinta las carpetas', () {
    testWidgets('la lista muestra las carpetas antes que los archivos',
        (tester) async {
      final d = raiz.path;
      conArbol({
        d: [
          archivoNativo('$d/zebra.txt'),
          carpetaNativa('$d/Fotos'),
        ],
      });
      await controller.navigateTo(d);

      await tester.pumpWidget(MaterialApp(
        home: FileListingScreen(
          controller: controller,
          title: 'Este dispositivo',
          icon: Icons.smartphone_outlined,
          files: const [],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(NFolderTile), findsOneWidget);
      expect(find.text('Fotos'), findsOneWidget);

      // Y la carpeta va ANTES que el archivo. Se comprueba por posición, no
      // por existencia: una lista con la carpeta despues cumpliría las dos
      // comprobaciones de arriba.
      final yCarpeta = tester.getTopLeft(find.text('Fotos')).dy;
      final yArchivo = tester.getTopLeft(find.text('zebra.txt')).dy;
      expect(yCarpeta, lessThan(yArchivo));
    });

    testWidgets('pulsar una carpeta entra en ella', (tester) async {
      final d = raiz.path;
      conArbol({
        d: [carpetaNativa('$d/Fotos')],
        '$d/Fotos': [archivoNativo('$d/Fotos/dentro.jpg')],
      });
      await controller.navigateTo(d);

      await tester.pumpWidget(MaterialApp(
        home: FileListingScreen(
          controller: controller,
          title: 'Este dispositivo',
          icon: Icons.smartphone_outlined,
          files: const [],
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Fotos'));
      await tester.pumpAndSettle();

      expect(controller.currentPath, '$d/Fotos');
      expect(find.text('dentro.jpg'), findsOneWidget);
      // La FILA de la carpeta desapareció de la lista (el breadcrumb la
      // sigue mostrando como ubicación actual, que es lo correcto).
      expect(find.byType(NFolderTile), findsNothing);
    });

    testWidgets('la carpeta se pinta con el componente del kit',
        (tester) async {
      final d = raiz.path;
      conArbol({
        d: [carpetaNativa('$d/Fotos')],
      });
      await controller.navigateTo(d);

      await tester.pumpWidget(MaterialApp(
        home: FileListingScreen(
          controller: controller,
          title: 'Este dispositivo',
          icon: Icons.smartphone_outlined,
          files: const [],
        ),
      ));
      await tester.pumpAndSettle();

      // `FileRow` es lo que pinta un archivo. Si la carpeta saliera como un
      // `FileRow`, el toque abriría el visor con una carpeta dentro.
      expect(find.byType(NFolderTile), findsOneWidget);
      expect(find.byType(FileRow), findsNothing,
          reason: 'una carpeta no puede pintarse como una fila de archivo');
    });

    testWidgets('en cuadrícula usa NFolderGridTile', (tester) async {
      final d = raiz.path;
      conArbol({
        d: [carpetaNativa('$d/Fotos')],
      });
      await controller.navigateTo(d);
      controller.setCategoryLayout(FileViewMode.grid);

      await tester.pumpWidget(MaterialApp(
        home: FileListingScreen(
          controller: controller,
          title: 'Este dispositivo',
          icon: Icons.smartphone_outlined,
          files: const [],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(NFolderGridTile), findsOneWidget);
      expect(find.byType(NFolderTile), findsNothing,
          reason: 'en cuadrícula la fila de lista no se usa');
    });

    testWidgets('una carpeta con subcarpetas no dice "Nada por aquí"',
        (tester) async {
      // El fallo que este test cierra: una carpeta con subcarpetas pero sin
      // archivos NO esta vacia, y con la comprobacion solo de archivos
      // apareceria un "Nada por aqui" encima del arbol de carpetas.
      final d = raiz.path;
      conArbol({
        d: [carpetaNativa('$d/Fotos')],
      });
      await controller.navigateTo(d);

      await tester.pumpWidget(MaterialApp(
        home: FileListingScreen(
          controller: controller,
          title: 'Este dispositivo',
          icon: Icons.smartphone_outlined,
          files: const [],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Nada por aquí'), findsNothing);
      expect(find.text('Fotos'), findsOneWidget);
    });

    testWidgets('el listado real del disco también trae carpetas',
        (tester) async {
      // Sin doble, con el `Directory.list()` de verdad detrás: es la ruta
      // que se usa cuando no hay `.so`.
      final d = '${raiz.path}/real';
      Directory(d).createSync();
      arbolReal(d, ['Fotos', 'Documentos'], ['a.txt']);

      await controller.navigateTo(d);

      expect(controller.currentFolders.map((c) => c.name).toSet(),
          {'Fotos', 'Documentos'});
      expect(controller.browsableFiles.map((f) => f.title).toList(), ['a.txt']);
    });
  });
}
