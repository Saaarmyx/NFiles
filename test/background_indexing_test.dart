// test/background_indexing_test.dart
//
// La indexación no puede atascar el hilo UI: el orden y lo derivable del
// nombre se resuelven dentro del isolate, la lista visible se memoiza y
// cada carga entrega su bloque con una sola notificación.
//
// # Qué protege este archivo
//
// 1. Que `loadFiles` devuelva orden descendente y modelos completos sin
//    trabajo pendiente en el hilo principal.
// 2. Que `visibleFiles` sea estable (misma instancia), inmutable y se
//    invalide al cambiar datos o criterio (no en cada build).
// 3. Que `fetchFiles` pinte una vez por carga: loading + bloque, y una
//    sola en refrescos silenciosos sin cambios.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:NFiles/controllers/files_controller.dart';
import 'package:NFiles/models/file_model.dart';
import 'package:NFiles/services/file_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('nfiles_bg');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<String> put(String name, {int size = 16, DateTime? modified}) async {
    final path = p.join(tmp.path, name);
    await Directory(p.dirname(path)).create(recursive: true);
    await File(path).writeAsBytes(List.filled(size, 1));
    if (modified != null) await File(path).setLastModified(modified);
    return path;
  }

  FilesController controller() {
    final c = FilesController(
      fileService: FileService(roots: [tmp], useIsolate: false),
    );
    addTearDown(c.dispose);
    return c;
  }

  group('el isolate entrega el trabajo hecho', () {
    test('loadFiles ordena descendente por modificación', () async {
      await put('viejo.txt', modified: DateTime(2026, 1, 1));
      await put('nuevo.txt', modified: DateTime(2026, 6, 1));
      await put('medio.txt', modified: DateTime(2026, 3, 1));

      final files = await FileService(
        roots: [tmp],
        useIsolate: false,
      ).loadFiles();

      expect(files.map((f) => f.title).toList(), [
        'nuevo.txt',
        'medio.txt',
        'viejo.txt',
      ]);
    });

    test('título y heurísticas vienen resueltos en el modelo', () async {
      await put('MVIMG_001.jpg');
      await put('selfie_frontal.png');

      final files = await FileService(
        roots: [tmp],
        useIsolate: false,
      ).loadFiles();
      final byTitle = {for (final f in files) f.title: f};

      expect(byTitle['MVIMG_001.jpg']!.isMotionPhoto, isTrue);
      expect(byTitle['selfie_frontal.png']!.isSelfie, isTrue);
    });
  });

  group('visibleFiles memoizada e inmutable', () {
    test('misma instancia entre accesos', () async {
      await put('a.pdf');
      final c = controller();
      await c.fetchFiles();

      expect(identical(c.visibleFiles, c.visibleFiles), isTrue);
    });

    test('no se puede mutar desde fuera', () async {
      await put('a.pdf');
      final c = controller();
      await c.fetchFiles();

      expect(
        () => c.visibleFiles.add(FileModel(
          id: 'x',
          path: 'x',
          title: 'x',
          dateCreated: DateTime(2026),
          dateModified: DateTime(2026),
          sizeInBytes: 1,
        )),
        throwsUnsupportedError,
      );
    });

    test('búsqueda y orden invalidan la caché', () async {
      await put('informe.pdf');
      await put('foto.jpg');
      final c = controller();
      await c.fetchFiles();
      final before = c.visibleFiles;

      c.setSearchQuery('informe');
      expect(identical(c.visibleFiles, before), isFalse);
      expect(c.visibleFiles.map((f) => f.title), ['informe.pdf']);

      c.setSearchQuery('');
      c.setSort(FilesSort.addedDay);
      expect(identical(c.visibleFiles, before), isFalse);
      expect(c.visibleFiles.length, 2);
    });

    test('visibleGroups se memoiza sobre la misma lista', () async {
      await put('a.pdf');
      final c = controller();
      await c.fetchFiles();

      expect(identical(c.visibleGroups, c.visibleGroups), isTrue);
    });
  });

  group('una carga, una entrega', () {
    test('carga fría: loading + bloque, nada más', () async {
      await put('a.pdf');
      final c = controller();
      var avisos = 0;
      c.addListener(() => avisos++);

      await c.fetchFiles();

      expect(c.state, FilesState.loaded);
      expect(avisos, 2);
    });

    test('refresco silencioso sin cambios: un solo aviso', () async {
      await put('a.pdf');
      final c = controller();
      await c.fetchFiles();
      var avisos = 0;
      c.addListener(() => avisos++);

      await c.refreshSilent();

      expect(avisos, 1);
    });
  });
}
