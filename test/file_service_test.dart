// test/file_service_test.dart
//
// El barrido con raíces solapadas no duplica: la base cubre a las
// subcarpetas a propósito (por si la base no es legible), así que un
// archivo sale en cada raíz que lo contenga si nadie lo filtra.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:NFiles/services/file_service.dart';

void main() {
  test('raíces solapadas devuelven cada archivo una sola vez', () async {
    final tmp = await Directory.systemTemp.createTemp('nfiles_dedup');
    try {
      final sub = Directory('${tmp.path}/Download');
      await sub.create(recursive: true);
      await File('${tmp.path}/a.pdf').writeAsBytes(List.filled(16, 1));
      await File('${sub.path}/b.pdf').writeAsBytes(List.filled(16, 2));

      final service = FileService(
        roots: [tmp, sub],
        useIsolate: false,
      );
      final files = await service.loadFiles();
      final ids = files.map((f) => f.id).toList();

      expect(ids.toSet().length, ids.length,
          reason: 'la base y Download se solapan: b.pdf saldría dos veces');
      expect(ids.length, 2);
    } finally {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    }
  });

  group('archivos ocultos', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('nfiles_hidden');
      // Dos formas de ocultarse: el propio nombre y la carpeta que lo
      // contiene. El ajuste tiene que encender las dos o el contador de
      // cada categoría sigue mintiendo.
      await File('${tmp.path}/visible.pdf').writeAsBytes(List.filled(8, 1));
      await File('${tmp.path}/.oculto.pdf').writeAsBytes(List.filled(8, 1));
      final thumb = Directory('${tmp.path}/.thumbnails');
      await thumb.create();
      await File('${thumb.path}/copia.png')
          .writeAsBytes(List.filled(8, 1));
    });

    tearDown(() async {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('por defecto quedan fuera los ocultos', () async {
      final files = await FileService(
        roots: [tmp],
        useIsolate: false,
      ).loadFiles();

      expect(files.map((f) => f.title), ['visible.pdf']);
    });

    test('con showHidden entran también', () async {
      final files = await FileService(
        roots: [tmp],
        useIsolate: false,
        showHidden: true,
      ).loadFiles();

      expect(files.map((f) => f.title).toSet(), {
        'visible.pdf',
        '.oculto.pdf',
        'copia.png',
      });
    });

    test('withHidden copia el resto de configuración', () async {
      final base = FileService(roots: [tmp], useIsolate: false);
      final copia = base.withHidden(true);

      expect(copia.roots, base.roots);
      expect(copia.useIsolate, base.useIsolate);
      expect(copia.showHidden, isTrue);
      expect(base.showHidden, isFalse,
          reason: 'la original no se muta: es la que usa el resto del app');
    });
  });
}
