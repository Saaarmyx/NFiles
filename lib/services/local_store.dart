import 'dart:convert';

import 'package:NexoraUi/NexoraUi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../controllers/files_controller.dart';
import 'view_prefs.dart';

/// Persistencia local de NFiles (favoritos y papelera).
///
/// Guarda solo identificadores (rutas) y metadatos: los archivos se
/// redescubren del disco en cada arranque y los registros huérfanos
/// (archivos que ya no existen) se podan al cargar.
class LocalStore {
  static const _favoritesKey = 'nfiles_favorites_v1';
  static const _trashKey = 'nfiles_trash_v1';
  static const _snapshotKey = 'nfiles_snapshot_v1';
  static const _pinsKey = 'nfiles_pins_v1';
  static const _privateOriginsKey = 'nfiles_private_origins_v1';
  static const _albumsKey = 'nfiles_albums_v1';
  static const _onboardingDoneKey = 'nfiles_onboarding_done_v1';

  final SharedPreferences _prefs;

  LocalStore(this._prefs);

  /// El `SharedPreferences` subyacente.
  ///
  /// Lo necesitan las piezas del kit que hablan [NKeyValueStore]
  /// (preferencias de vista, apariencia): constructores distintos con la
  /// misma clave de escritura sobre el mismo almacén. Antes [viewPrefs]
  /// era la única puerta y quien quisiera una segunda instancia tenía que
  /// reconstruirla aquí.
  SharedPreferences get prefs => _prefs;

  static Future<LocalStore> load() async =>
      LocalStore(await SharedPreferences.getInstance());

  /// Ids (rutas) marcados como favoritos.
  Set<String> favoriteIds() =>
      Set.of(_prefs.getStringList(_favoritesKey) ?? const []);

  Future<void> saveFavoriteIds(Set<String> ids) =>
      _prefs.setStringList(_favoritesKey, ids.toList());

  /// Ruta → fecha en que se movió a la papelera.
  Map<String, DateTime> trashedAt() {
    final raw = _prefs.getString(_trashKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final entry in decoded.entries)
          entry.key: DateTime.fromMillisecondsSinceEpoch(entry.value as int),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> saveTrashed(Map<String, DateTime> trashed) =>
      _prefs.setString(_trashKey, jsonEncode({
        for (final entry in trashed.entries)
          entry.key: entry.value.millisecondsSinceEpoch,
      }));

  /// Snapshot ligero para arranque instantáneo (0ms percibidos).
  ///
  /// Solo guarda primitivos (ruta + mtime) para hidratar la grilla desde
  /// caché antes del escaneo real. Los metadatos ricos se resuelven después.
  List<Map<String, Object>> loadSnapshot() {
    final raw = _prefs.getString(_snapshotKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return [
        for (final e in decoded)
          if (e is Map<String, dynamic> &&
              e['path'] is String &&
              e['modified'] is int)
            {'path': e['path'] as String, 'modified': e['modified'] as int},
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveSnapshot(List<Map<String, Object>> rows) =>
      _prefs.setString(_snapshotKey, jsonEncode(rows));

  /// Pines de Álbumes en orden (máx 4). Ids: `album:<dirPath>` para
  /// carpetas y `__videos__` / `__trash__` / `__favorites__` para listas
  /// sintéticas. Sin clave = primera vez (la app siembra los defaults).
  bool hasPins() => _prefs.containsKey(_pinsKey);

  List<String> pinnedIds() =>
      List.of(_prefs.getStringList(_pinsKey) ?? const []);

  Future<void> savePinnedIds(List<String> ids) =>
      _prefs.setStringList(_pinsKey, ids);

  /// Orígenes de la carpeta privada: ruta actual en bóveda → carpeta
  /// original, para restaurar cada archivo a su sitio.
  Map<String, String> privateOrigins() {
    final raw = _prefs.getString(_privateOriginsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final entry in decoded.entries)
          if (entry.value is String) entry.key: entry.value as String,
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> savePrivateOrigins(Map<String, String> origins) =>
      _prefs.setString(_privateOriginsKey, jsonEncode(origins));

  // ─── Personalización de álbumes ───

  /// Previsualización por ruta: {ruta: AlbumPrefs}.
  /// Se serializa como lista para no duplicar claves en JSON.
  Map<String, AlbumPrefs> albumPrefs() {
    final raw = _prefs.getString(_albumsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return {
        for (final e in decoded)
          if (e is Map<String, dynamic> && e['path'] is String)
            e['path'] as String: AlbumPrefs(
              name: e['name'] as String?,
              cover: e['cover'] as String?,
              hidden: e['hidden'] as bool? ?? false,
            ),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> saveAlbumPrefs(Map<String, AlbumPrefs> prefs) =>
      _prefs.setString(
        _albumsKey,
        jsonEncode([
          for (final entry in prefs.entries)
            if (entry.value.isCustom)
              {
                'path': entry.key,
                if (entry.value.name != null) 'name': entry.value.name,
                if (entry.value.cover != null) 'cover': entry.value.cover,
                if (entry.value.hidden) 'hidden': true,
              },
        ]),
      );

  // ─── Bienvenida / apariencia ───

  /// Si ya se completó la bienvenida inicial.
  bool onboardingDone() => _prefs.getBool(_onboardingDoneKey) ?? false;

  /// Preferencias del popup de la topbar (orden, vista, filtro, y las
  /// de Explorar y Categorías). Mismo almacén, otro prefijo.
  late final FilesViewPrefs viewPrefs =
      FilesViewPrefs(PrefsKeyValueStore(_prefs));

  /// Aplica lo guardado al controller y se queda escuchando.
  void applyViewPreferences(FilesController controller) {
    viewPrefs.applyTo(controller, viewPrefs.load());
    viewPrefs.attach(controller);
  }

  /// Persistencia de la apariencia, delegada en el kit.
  ///
  /// La lista de ajustes (acento, tema, estilo, intensidad, modo, usuario
  /// y foto) la define [NAppearanceStore] para que las dos apps no puedan
  /// desincronizarse. Aqui solo se le da nombre y prefijo.
  late final NAppearanceStore appearance =
      NAppearanceStore(PrefsKeyValueStore(_prefs), prefix: 'nfiles_appearance_');

  /// Persiste la bienvenida y marca el fin.
  Future<void> saveOnboarding() async {
    await appearance.save();
    await _prefs.setBool(_onboardingDoneKey, true);
  }

  /// Aplica la apariencia guardada y se queda escuchando para que
  /// cualquier cambio posterior se guarde solo.
  ///
  /// Antes solo se guardaba al terminar la bienvenida, asi que cambiar el
  /// acento o el estilo despues se perdia al reiniciar.
  void applyAppearance() {
    appearance.load(defaultAccent: NAccentColors.files);
    appearance.attach();
  }
}

/// Adaptador de [NKeyValueStore] sobre `SharedPreferences`.
///
/// El kit define la persistencia de la apariencia pero no depende de
/// `shared_preferences`, para no arrastrar el plugin a quien solo quiera
/// un componente. Esta clase es todo el pegamento que hace falta.
class PrefsKeyValueStore implements NKeyValueStore {
  final SharedPreferences prefs;

  const PrefsKeyValueStore(this.prefs);

  @override
  String? getString(String key) => prefs.getString(key);

  @override
  double? getDouble(String key) => prefs.getDouble(key);

  @override
  int? getInt(String key) => prefs.getInt(key);

  @override
  bool? getBool(String key) => prefs.getBool(key);

  @override
  Future<void> setString(String key, String? value) async {
    if (value == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
  }

  @override
  Future<void> setDouble(String key, double value) =>
      prefs.setDouble(key, value);

  @override
  Future<void> setInt(String key, int value) => prefs.setInt(key, value);

  @override
  Future<void> setBool(String key, bool value) => prefs.setBool(key, value);
}

/// Previsualización de un álbum: nombre, carátula y visibilidad.
///
/// Todo opcional: null = se usa el valor real del disco.
class AlbumPrefs {
  final String? name;
  final String? cover;
  final bool hidden;

  const AlbumPrefs({this.name, this.cover, this.hidden = false});

  /// False si no aporta nada: entonces no se persiste.
  bool get isCustom => name != null || cover != null || hidden;

  AlbumPrefs copyWith({
    String? name,
    String? cover,
    bool? hidden,
    bool clearName = false,
    bool clearCover = false,
  }) => AlbumPrefs(
    name: clearName ? null : (name ?? this.name),
    cover: clearCover ? null : (cover ?? this.cover),
    hidden: hidden ?? this.hidden,
  );
}
