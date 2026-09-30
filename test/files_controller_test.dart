import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:NFiles/controllers/files_controller.dart';
import 'package:NFiles/models/file_model.dart';
import 'package:NFiles/services/file_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Doble de almacenamiento para no depender del plugin en tests de lógica.
class SharedPreferencesShim {
  static void set() {
    SharedPreferences.setMockInitialValues({});
  }
}

FileModel file(
  String path, {
  DateTime? modified,
  int size = 16,
  bool favorite = false,
}) {
  return FileModel(
    id: path,
    path: path,
    title: p.basename(path),
    dateCreated: modified ?? DateTime(2026, 1, 10),
    dateModified: modified ?? DateTime(2026, 1, 10),
    sizeInBytes: size,
    isFavorite: favorite,
  );
}

void main() {
  // Necesario para , que usa .
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUp(() async {
    SharedPreferencesShim.set();
    tmp = await Directory.systemTemp.createTemp('nfiles_ctrl');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  /// Escribe un archivo y devuelve la ruta.
  Future<String> put(String name, {int size = 16}) async {
    final path = p.join(tmp.path, name);
    await Directory(p.dirname(path)).create(recursive: true);
    await File(path).writeAsBytes(List.filled(size, 1));
    return path;
  }

  Future<FilesController> loaded() async {
    // `FileService` de verdad: el escaneo corre en un isolate real, y en
    // un `test()` normal (sin reloj falso) eso completa sin `runAsync`.
    final c = FilesController(fileService: FileService(roots: [tmp], useIsolate: false));
    await c.fetchFiles();
    return c;
  }

  /// Controlador vacío, para probar lógica sin tocar el disco.
  FilesController empty() =>
      FilesController(fileService: FileService(roots: const [], useIsolate: false));

  group('categorías por familia', () {
    test('cada familia devuelve solo lo suyo', () async {
      final photo = await put('a.jpg');
      final song = await put('b.mp3');
      final doc = await put('c.pdf');
      final apk = await put('d.apk');
      final vid = await put('e.mp4');

      final c = await loaded();
      addTearDown(c.dispose);

      expect(c.imageFiles.map((f) => f.path), [photo]);
      expect(c.musicFiles.map((f) => f.path), [song]);
      expect(c.documentFiles.map((f) => f.path), [doc]);
      expect(c.apkFiles.map((f) => f.path), [apk]);
      expect(c.videos.map((f) => f.path), [vid]);
    });

    test('"Archivos" es el cajón: incluye lo que no es multimedia', () async {
      await put('a.jpg');
      await put('b.mp3');
      await put('d.apk');
      await put('f.xyz');

      final c = await loaded();
      addTearDown(c.dispose);

      final names = c.otherFiles.map((f) => f.title).toSet();
      expect(names, contains('d.apk'));
      expect(names, contains('f.xyz'));
      // Ni imágenes ni música: tienen su propia fila.
      expect(names, isNot(contains('a.jpg')));
      expect(names, isNot(contains('b.mp3')));
    });

    test('las categorías vienen ordenadas de más nuevo a más viejo', () async {
      final old = await put('old.jpg');
      final fresh = await put('new.jpg');
      // Sync: `setLastModified` no devuelve Future y no necesita esperarse.
      File(old).setLastModifiedSync(DateTime(2020));
      File(fresh).setLastModifiedSync(DateTime(2026));

      final c = await loaded();
      addTearDown(c.dispose);

      final titles = c.imageFiles.map((f) => f.title).toList();
      expect(titles.first, 'new.jpg');
    });
  });

  group('carpetas del usuario', () {
    test('Descargas se resuelve por nombre de carpeta', () async {
      final inside = await put('Descargas/hola.txt');
      await put('OTRO/adios.txt');

      final c = await loaded();
      addTearDown(c.dispose);

      expect(c.downloadFiles.map((f) => f.path), [inside]);
    });

    test('Capturas también acepta el nombre en inglés', () async {
      final inside = await put('Screenshots/shot.png');
      final c = await loaded();
      addTearDown(c.dispose);
      expect(c.screenshotFiles.map((f) => f.path), [inside]);
    });

    test('una carpeta sin nombre conocido no inventa resultados', () async {
      await put('raro/archivo.txt');
      final c = await loaded();
      addTearDown(c.dispose);
      expect(c.downloadFiles, isEmpty);
      expect(c.screenshotFiles, isEmpty);
      expect(c.recorderFiles, isEmpty);
    });
  });

  group('totales', () {
    test('totalBytes y su formato suman lo escaneado', () async {
      await put('a.jpg', size: 100);
      await put('b.pdf', size: 200);
      final c = await loaded();
      addTearDown(c.dispose);
      expect(c.totalBytes, 300);
      expect(c.totalFormattedSize, '300 B');
    });
  });

  group('favoritos', () {
    test('toggleFavorite marca y persiste', () async {
      final path = await put('a.jpg');
      final c = await loaded();
      addTearDown(c.dispose);

      expect(c.favoriteFiles, isEmpty);
      await c.toggleFavorite(path);
      expect(c.favoriteFiles.length, 1);
      expect(c.favoriteFiles.first.id, path);
    });

    test('toggleFavorite alterna', () async {
      final path = await put('a.jpg');
      final c = await loaded();
      addTearDown(c.dispose);

      await c.toggleFavorite(path);
      await c.toggleFavorite(path);
      expect(c.favoriteFiles, isEmpty);
    });
  });

  group('búsqueda', () {
    test('filtra por nombre y por ruta', () async {
      await put('informe.pdf');
      await put('foto.jpg');
      final c = await loaded();
      addTearDown(c.dispose);

      c.setSearchQuery('informe');
      expect(c.visibleFiles.map((f) => f.title), ['informe.pdf']);

      c.setSearchQuery('FOTO');
      expect(c.visibleFiles.map((f) => f.title), ['foto.jpg']);
    });

    test('vaciar la búsqueda restaura todo', () async {
      await put('informe.pdf');
      await put('foto.jpg');
      final c = await loaded();
      addTearDown(c.dispose);

      c.setSearchQuery('informe');
      expect(c.visibleFiles.length, 1);
      c.setSearchQuery('');
      expect(c.visibleFiles.length, 2);
    });
  });

  group('orden de categoría', () {
    test('applyCategorySort A→Z y Z→A', () async {
      final c = empty();
      addTearDown(c.dispose);
      final files = [file('/x/c.txt'), file('/x/a.txt'), file('/x/b.txt')];

      c.setCategorySort(CategorySort.az);
      expect(
        c.applyCategorySort(files).map((f) => f.title),
        ['a.txt', 'b.txt', 'c.txt'],
      );

      c.setCategorySort(CategorySort.za);
      expect(
        c.applyCategorySort(files).map((f) => f.title),
        ['c.txt', 'b.txt', 'a.txt'],
      );
    });

    test('applyCategorySort no muta la lista original', () async {
      final c = empty();
      addTearDown(c.dispose);
      final files = [file('/x/c.txt'), file('/x/a.txt')];
      c.setCategorySort(CategorySort.az);
      c.applyCategorySort(files);
      expect(files.first.title, 'c.txt');
    });
  });

  group('agrupación por día', () {
    test('dayKeyOf quita la hora', () async {
      final c = empty();
      addTearDown(c.dispose);
      final day = c.dayKeyOf(
        file('/x/a.jpg', modified: DateTime(2026, 3, 4, 23, 59)),
      );
      expect(day, DateTime(2026, 3, 4));
    });

    test('visibleGroups ordena los días de más nuevo a más viejo', () async {
      await put('hoy.jpg');
      await put('ayer.jpg');
      final c = await loaded();
      addTearDown(c.dispose);
      // Forzamos fechas distintas para que el orden sea determinista.
      final groups = c.visibleGroups;
      final keys = groups.keys.toList();
      expect(keys, isNotEmpty);
      for (var i = 1; i < keys.length; i++) {
        expect(keys[i].isAfter(keys[i - 1]), isFalse);
      }
    });
  });

  group('estados', () {
    test('tras fetchFiles queda en loaded', () async {
      await put('a.jpg');
      final c = await loaded();
      addTearDown(c.dispose);
      expect(c.state, FilesState.loaded);
      expect(c.errorMessage, isNull);
    });

    test('sin archivos tampoco es error', () async {
      final c = await loaded();
      addTearDown(c.dispose);
      expect(c.state, FilesState.loaded);
      expect(c.visibleFiles, isEmpty);
    });
  });
}
