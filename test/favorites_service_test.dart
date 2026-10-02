// test/favorites_service_test.dart
//
// `FavoritesService` une favoritos de NFiles y NPhotos: si la unión pierde
// ids o revienta sin la fuente externa, "Favoritos" miente o tumba Explorar.
import 'package:flutter_test/flutter_test.dart';
import 'package:NFiles/models/file_model.dart';
import 'package:NFiles/services/favorites_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

FileModel _file(String path, int modifiedMs) => FileModel(
      id: path,
      path: path,
      title: path.split('/').last,
      dateCreated: DateTime.fromMillisecondsSinceEpoch(modifiedMs),
      dateModified: DateTime.fromMillisecondsSinceEpoch(modifiedMs),
      sizeInBytes: 10,
    );

void main() {
  test('sin clave de NPhotos devuelve vacío, no falla', () async {
    SharedPreferences.setMockInitialValues({});
    final service = FavoritesService();

    expect(await service.nphotosFavorites(), isEmpty);
  });

  test('lee los favoritos de NPhotos cuando la fuente está accesible',
      () async {
    SharedPreferences.setMockInitialValues({
      FavoritesService.nphotosFavoritesKey: ['/dcim/a.jpg', '/dcim/b.jpg'],
    });
    final service = FavoritesService();

    expect(
      await service.nphotosFavorites(),
      {'/dcim/a.jpg', '/dcim/b.jpg'},
    );
  });

  test('la unión junta locales y externos sin duplicados', () async {
    SharedPreferences.setMockInitialValues({
      FavoritesService.nphotosFavoritesKey: ['/dcim/b.jpg', '/dcim/c.jpg'],
    });
    final service = FavoritesService();

    expect(
      await service.unionFavorites({'/dcim/a.jpg', '/dcim/b.jpg'}),
      {'/dcim/a.jpg', '/dcim/b.jpg', '/dcim/c.jpg'},
    );
  });

  test('unionSets es pura y no muta las entradas', () {
    final a = {'/x'};
    final b = {'/y'};
    final union = FavoritesService.unionSets(a, b);

    expect(union, {'/x', '/y'});
    expect(a, {'/x'});
    expect(b, {'/y'});
  });

  test('resolve mapea a modelos, ordena y salta huérfanos', () {
    final service = FavoritesService();
    final all = [
      _file('/a/viejo.jpg', 1000),
      _file('/a/nuevo.jpg', 2000),
    ];

    final resolved = service.resolve(all, {
      '/a/nuevo.jpg',
      '/ya/no/existe.jpg',
      '/a/viejo.jpg',
    });

    // El huérfano fuera, y el más reciente primero.
    expect(resolved.map((f) => f.id).toList(), [
      '/a/nuevo.jpg',
      '/a/viejo.jpg',
    ]);
  });

  test('resolve con unión vacía no devuelve nada', () {
    final service = FavoritesService();

    expect(service.resolve([_file('/a.jpg', 1)], const {}), isEmpty);
  });
}
