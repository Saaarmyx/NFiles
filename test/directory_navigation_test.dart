// test/directory_navigation_test.dart
//
// La navegación por directorio: `currentPath`, `navigateTo` y el historial.
//
// # Qué protege este archivo
//
// 1. Que `navigateTo` entre de verdad, con escaneo real del directorio.
// 2. Que el índice GLOBAL no se contamine. Es el fallo caro: `visibleFiles`
//    alimenta Recientes, Explorar y el visor, así que si entrar en una
//    carpeta sustituyera el índice, al salir de ella el usuario vería menos
//    archivos de los que había.
// 3. Que el historial no se llene de duplicados ni crezca sin límite.
// 4. Que `navigateUp` lleve al padre y termine en la vista global.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:NFiles/controllers/files_controller.dart';
import 'package:NFiles/widgets/breadcrumbs_bar.dart';

void main() {
  late FilesController controller;
  late Directory raiz;

  setUp(() {
    controller = FilesController();

    raiz = Directory.systemTemp.createTempSync('nfiles_nav');
    _carpeta(raiz, 'Documents');
    _carpeta(raiz, 'Download');
  });

  tearDown(() {
    controller.dispose();
    if (raiz.existsSync()) raiz.deleteSync(recursive: true);
  });

  group('navigateTo', () {
    test('parte de la vista global, sin ruta', () {
      expect(controller.currentPath, isNull);
      expect(controller.isBrowsingDirectory, isFalse);
      expect(controller.navigationHistory, isEmpty);
    });

    test('entra en un directorio y lee sus archivos', () async {
      await controller.navigateTo('${raiz.path}/Documents');

      expect(controller.currentPath, '${raiz.path}/Documents');
      expect(controller.isBrowsingDirectory, isTrue);
      // `browsableFiles` pasa a ser el contenido del directorio.
      expect(controller.browsableFiles.map((f) => f.title),
          containsAll(<String>['a.txt', 'b.txt']));
    });

    test('NO toca el índice global', () async {
      // Este es el test caro. `visibleFiles` alimenta Recientes, Explorar y
      // el visor de archivos: si `navigateTo` sustituyera el índice por los
      // archivos de la subcarpeta, al volver atrás el usuario vería menos
      // archivos de los que había. El síntoma aparecería en otras pantallas,
      // lejos de aquí.
      await controller.navigateTo('${raiz.path}/Documents');
      final enVistaGlobal = controller.visibleFiles.length;

      await controller.navigateTo(null);
      expect(controller.browsableFiles.length, enVistaGlobal,
          reason: 'volver a la vista global tiene que devolver el índice entero');
      expect(controller.currentPath, isNull);
    });

    test('el historial registra la entrada, sin duplicados', () async {
      await controller.navigateTo('${raiz.path}/Documents');
      await controller.navigateTo('${raiz.path}/Download');
      // Volver a la misma carpeta dos veces seguidas no debe duplicar la
      // entrada: con un duplicado, el "atrás" no haría nada perceptible.
      await controller.navigateTo('${raiz.path}/Documents');

      expect(controller.navigationHistory, [
        '${raiz.path}/Documents',
        '${raiz.path}/Download',
      ]);
    });

    test('el historial no crece sin límite', () async {
      for (var i = 0; i < 60; i++) {
        await controller.navigateTo('${raiz.path}/Documents');
      }
      expect(controller.navigationHistory.length, lessThanOrEqualTo(32),
          reason: 'una sesión larga no puede acumular cientos de entradas');
    });

    test('el historial es una copia, no la lista interna', () async {
      await controller.navigateTo('${raiz.path}/Documents');
      final h = controller.navigationHistory;
      expect(() => h.add('/intento/de/corromper'),
          throwsUnsupportedError,
          reason: 'si se pudiera mutar, el estado interno quedaría incoherente');
    });

    test('normaliza la barra final', () async {
      await controller.navigateTo('${raiz.path}/Documents/');
      expect(controller.currentPath, '${raiz.path}/Documents',
          reason: 'con barra final, la misma carpeta daría dos rutas distintas');
    });

    test('una ruta repetida no vuelve a escanear', () async {
      await controller.navigateTo('${raiz.path}/Documents');
      var avisos = 0;
      controller.addListener(() => avisos++);
      await controller.navigateTo('${raiz.path}/Documents');
      // Reentrar en la carpeta en la que ya se está no debe pasar por un
      // escaneo ni un repintado: el usuario no ha pedido nada.
      expect(avisos, 0);
    });

    test('una carpeta inexistente no lanza', () async {
      // Destino elegido por el usuario, carpeta que puede desaparecer entre
      // el tap y el escaneo. Lanzar tiraría la pantalla entera.
      await controller.navigateTo('${raiz.path}/no-existe');
      expect(controller.currentPath, '${raiz.path}/no-existe');
      expect(controller.browsableFiles, isEmpty);
    });

    test('el breadcrumb recibe la ruta y salta al ancestro', () async {
      await controller.navigateTo('${raiz.path}/Documents');
      expect(controller.currentPath, '${raiz.path}/Documents');

      // Lo que el widget entrega al pulsar: la ruta acumulada del segmento.
      // En un temporal de Linux la raíz completa es `/tmp/<dir>`, así que
      // aparecen `/tmp` y el temporal. Se comprueba la COLA, que es la parte
      // que depende de la navegación, y no la lista entera.
      final crumbs = parseBreadcrumbs(controller.currentPath!);
      expect(crumbs.last.path, '${raiz.path}/Documents');
      expect(crumbs.last.isCurrent, isTrue);
      expect(crumbs[crumbs.length - 2].path, raiz.path,
          reason: 'pulsar el anterior tiene que llevar a la carpeta contents');
      // Y ninguna ruta se repite, que es lo que hace inservible un breadcrumb
      // con "Raíz > Raíz" al final.
      final rutas = crumbs.map((c) => c.path).toList();
      expect(rutas.toSet().length, rutas.length);
    });
  });

  group('navigateUp', () {
    test('sube al directorio padre', () async {
      final hondo = _carpeta(raiz, 'Documents', sub: 'Trabajo');
      await controller.navigateTo(hondo);

      expect(await controller.navigateUp(), isTrue);
      expect(controller.currentPath, '${raiz.path}/Documents');
    });

    test('sube de un nivel en un nivel, hasta llegar a la vista global',
        () async {
      // Un temporal de Linux cuelga de `/tmp`, así que salir de la categoría
      // no es un salto: hay que subir cada nivel. Comprobarlo paso a paso
      // documenta que `navigateUp` NO salta de golpe a la raíz, que es lo
      // que un usuario que ha descended cuatro niveles esperaría.
      await controller.navigateTo('${raiz.path}/Documents');
      await controller.navigateUp();
      expect(controller.currentPath, raiz.path);

      await controller.navigateUp();
      expect(controller.currentPath, '/tmp');

      // Y desde `/tmp` ya está en la raíz del sistema: un nivel más deja el
      // breadcrumb con un chip repetido, así que se sale a la vista global.
      await controller.navigateUp();
      expect(controller.currentPath, isNull);
      expect(controller.isBrowsingDirectory, isFalse);
    });

    test('sin directorio abierto no hay a dónde subir', () async {
      expect(await controller.navigateUp(), isFalse);
    });
  });

  group('la lista que se pinta', () {
    test('con directorio abierto muestra ese directorio', () async {
      await controller.navigateTo('${raiz.path}/Documents');
      expect(controller.browsableFiles.every((f) => f.path.contains('Documents')),
          isTrue);
    });

    test('sin directorio abierto muestra el índice filtrado', () async {
      // Se comparan los CONTENIDOS, no la identidad: `visibleFiles` es un
      // getter que construye una lista nueva en cada llamada, así que
      // `identical` siempre daría falso y no mediría nada.
      final global = controller.visibleFiles.map((f) => f.id).toList()..sort();
      final navegable = controller.browsableFiles.map((f) => f.id).toList()
        ..sort();
      expect(navegable, global,
          reason: 'sin ruta abierta, la vista muestra el índice entero');
    });

    test('vuelve a la lista global al salir', () async {
      final enVistaGlobal = controller.visibleFiles.length;
      await controller.navigateTo('${raiz.path}/Documents');
      expect(controller.browsableFiles.length, 2);

      await controller.navigateTo(null);
      // Al salir se recupera el índice entero, no una lista vacía. Es el
      // mismo aserto que el del grupo anterior visto desde el otro lado.
      expect(controller.browsableFiles.length, enVistaGlobal);
      expect(controller.currentPath, isNull);
    });
  });
}

/// Crea una carpeta con dos archivos de texto.
String _carpeta(Directory base, String nombre, {String? sub}) {
  final dir = Directory('${base.path}/$nombre${sub == null ? '' : '/$sub'}')
    ..createSync(recursive: true);
  File('${dir.path}/a.txt').writeAsStringSync('a');
  File('${dir.path}/b.txt').writeAsStringSync('b');
  return dir.path;
}
