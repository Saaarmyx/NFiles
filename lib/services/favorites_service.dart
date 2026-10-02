// lib/services/favorites_service.dart
//
// Unión de favoritos locales y de NPhotos.
//
// NFiles guarda sus favoritos en `nfiles_favorites_v1` y NPhotos en
// `nphotos_favorites_v1`, ambos como listas de rutas. Cada app lee su
// propio `SharedPreferences` (en Android están aislados por paquete), así
// que la fuente de NPhotos solo está accesible en entornos donde ambos
// prefieren el mismo almacén: se intenta con mejor esfuerzo y se degrada
// a los locales sin fallar nunca.
import 'package:shared_preferences/shared_preferences.dart';

import '../models/file_model.dart';

class FavoritesService {
  /// Clave de favoritos de NPhotos. Vive aquí y no en NFiles porque la
  /// fuente es de la otra app: si NPhotos la versiona, se cambia en un
  /// solo sitio.
  static const nphotosFavoritesKey = 'nphotos_favorites_v1';

  final Future<SharedPreferences> Function() _prefsLoader;

  FavoritesService({Future<SharedPreferences> Function()? prefsLoader})
      : _prefsLoader = prefsLoader ?? SharedPreferences.getInstance;

  /// Favoritos marcados en NPhotos, o vacío si la fuente no está accesible.
  ///
  /// Nunca lanza: una fuente ausente o ilegible es un conjunto vacío, no
  /// un error. Así "Favoritos" simplemente no muestra lo de NPhotos.
  Future<Set<String>> nphotosFavorites() async {
    try {
      final prefs = await _prefsLoader();
      final list = prefs.getStringList(nphotosFavoritesKey);
      if (list == null) return const {};
      return Set.of(list.where((p) => p.isNotEmpty));
    } catch (_) {
      return const {};
    }
  }

  /// Unión de locales + NPhotos, sin duplicados.
  Future<Set<String>> unionFavorites(Set<String> local) async {
    return unionSets(local, await nphotosFavorites());
  }

  /// Unión pura, para componer sin E/S.
  static Set<String> unionSets(Set<String> a, Set<String> b) => {...a, ...b};

  /// Resuelve ids a modelos conocidos, en orden estable. Los ids sin
  /// archivo en disco se saltan: un favorito huérfano no pinta fila.
  List<FileModel> resolve(List<FileModel> all, Set<String> ids) {
    if (ids.isEmpty) return const [];
    final byId = {for (final f in all) f.id: f};
    final out = <FileModel>[];
    for (final id in ids) {
      final file = byId[id];
      if (file != null) out.add(file);
    }
    out.sort((a, b) => b.dateModified.compareTo(a.dateModified));
    return out;
  }
}
