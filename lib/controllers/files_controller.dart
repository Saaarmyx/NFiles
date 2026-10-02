// lib/controllers/files_controller.dart
import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

// El dominio de archivos (FileKind, FsScannerRegistry, kindForPath…) y el
// perfil de rendimiento (CorePerformance) viven en el MISMO paquete: el motor
// nativo en Rust pasó de NexoraFs a NexoraCore, así que basta un import.
import 'package:NexoraCore/NexoraCore.dart';
import '../models/directory_entry.dart';
import '../models/file_filter.dart';
import '../models/file_model.dart';
import '../services/local_store.dart';
import '../services/file_service.dart';
import '../services/favorites_service.dart';
import '../services/native_index.dart';
import '../services/private_vault.dart';

enum FilesState { initial, permissionDenied, loading, loaded, error }

/// Orden del explorador desde el popup de la topbar.
enum FilesSort { captureDay, addedDay }

/// Modo de vista desde el popup de la topbar.
enum FilesViewMode { byDate, compact }

/// Filtro del explorador desde el popup de la topbar.
enum FilesFilter { all, camera }

/// Cómo se ve la lista de "Explorar": plana o por grupos.
enum ExploreViewMode { compact, grouped }

/// Cómo se ve una lista de archivos: en lista o en cuadrícula.
///
/// Este enum sustituye a [CategoryLayout], que significaba exactamente lo
/// mismo con otro nombre. La migración es transparente en el disco porque la
/// persistencia guarda el `name` del valor —`list` o `grid`— y esos nombres
/// no cambian: un usuario que tenía `grid` guardado sigue teniendo `grid`.
enum FileViewMode { list, grid }

/// Nombre anterior de [FileViewMode].
///
/// Se conserva como alias para no romper a quien aún lo escriba. Es un
/// *alias de tipo*, no un enum aparte: `CategoryLayout.list` y
/// `FileViewMode.list` son el MISMO valor, así que no puede aparecer el error
/// de comparar dos enums distintos que nunca son iguales, que es lo que
/// habría pasado de haber creado un enum nuevo sin más.
typedef CategoryLayout = FileViewMode;

/// Campo por el que se ordena un listado de archivos.
enum ListingSortField { name, size, modified, kind }

/// Dirección de la ordenación.
enum SortDirection { asc, desc }

class TrashedFile {
  final FileModel file;
  final DateTime trashedAt;

  const TrashedFile({required this.file, required this.trashedAt});
}

/// Pin de la pantalla Álbumes (máx 4).
///
/// [id] es `album:<dirPath>` para carpetas reales o `__videos__`,
/// `__trash__`, `__favorites__` para listas sintéticas.
/// Estado completo del popup de la topbar (⋮), en una sola pieza.
///
/// Vive aquí y no en el servicio de persistencia para evitar un ciclo:
/// el servicio necesita los enums del controller, así que si el estado
/// viviera allí el controller no podría importarlo.
@immutable
class FilesViewState {
  final FilesSort sort;
  final FilesViewMode viewMode;
  final FilesFilter filter;
  final ExploreViewMode exploreViewMode;
  final CategoryLayout categoryLayout;
  final ListingSortField listingField;
  final SortDirection listingDirection;
  final bool showHiddenFiles;
  final bool showFileExtensions;
  final bool thumbnailsWifiOnly;
  final bool confirmDelete;
  final int autoEmptyTrashDays;

  const FilesViewState({
    required this.sort,
    required this.viewMode,
    required this.filter,
    required this.exploreViewMode,
    required this.categoryLayout,
    required this.listingField,
    required this.listingDirection,
    required this.showHiddenFiles,
    required this.showFileExtensions,
    required this.thumbnailsWifiOnly,
    required this.confirmDelete,
    required this.autoEmptyTrashDays,
  });

  /// Defaults de fábrica: lo que ve alguien que abre la app por primera.
  /// Nombre ascendente, como el antiguo A→Z: cambiar de modelo no reordena
  /// lo que el usuario ya tenía.
  const FilesViewState.fresh()
      : sort = FilesSort.captureDay,
        viewMode = FilesViewMode.byDate,
        filter = FilesFilter.all,
        exploreViewMode = ExploreViewMode.compact,
        categoryLayout = CategoryLayout.list,
        listingField = ListingSortField.name,
        listingDirection = SortDirection.asc,
        showHiddenFiles = false,
        showFileExtensions = true,
        thumbnailsWifiOnly = false,
        confirmDelete = true,
        autoEmptyTrashDays = 30;

  /// Lo que hay ahora mismo en el controller.
  factory FilesViewState.of(FilesController c) => FilesViewState(
        sort: c.sort,
        viewMode: c.viewMode,
        filter: c.filter,
        exploreViewMode: c.exploreViewMode,
        categoryLayout: c.categoryLayout,
        listingField: c.listingField,
        listingDirection: c.listingDirection,
        showHiddenFiles: c.showHiddenFiles,
        showFileExtensions: c.showFileExtensions,
        thumbnailsWifiOnly: c.thumbnailsWifiOnly,
        confirmDelete: c.confirmDelete,
        autoEmptyTrashDays: c.autoEmptyTrashDays,
      );

  /// Claves de almacenamiento. Se guardan enums por su `.name`.
  Map<String, Object?> toMap() => {
        'sort': sort,
        'view_mode': viewMode,
        'filter': filter,
        'explore_view_mode': exploreViewMode,
        'default_view_mode': categoryLayout,
        'default_sort_field': listingField,
        'sort_direction': listingDirection,
        'show_hidden_files': showHiddenFiles,
        'show_file_extensions': showFileExtensions,
        'thumbnails_wifi_only': thumbnailsWifiOnly,
        'confirm_delete': confirmDelete,
        'auto_empty_trash_days': autoEmptyTrashDays,
      };
}

class FilesController extends ChangeNotifier {
  final FileService _fileService;
  LocalStore? _store;

  /// Unión de favoritos (locales + NPhotos) de la última carga.
  ///
  /// La resuelve [FavoritesService]: lo de NPhotos entra con mejor esfuerzo
  /// y lo local siempre. Expuesta para que Explorar decida si "Favoritos"
  /// merece fila en Acceso Rápido.
  Set<String> _favoriteUnion = const {};
  Set<String> get favoriteUnion => _favoriteUnion;

  final FavoritesService _favorites;

  /// Índice nativo persistente (redb). Inyectable para tests.
  final NativeFileIndex _nativeIndex;

  /// Espacio del punto de montaje (vía `statvfs`, microsegundos).
  ///
  /// `null` sin motor o si el FS no responde: la UI muestra entonces la
  /// suma del escaneo como respaldo.
  StorageInfo? _storage;
  StorageInfo? get storage => _storage;

  /// Directorio de la carpeta privada. Solo para tests; en producción
  /// se resuelve vía `path_provider` (soporte de la app).
  final Directory? privateDirOverride;

  FilesState _state = FilesState.initial;
  FilesState get state => _state;

  List<FileModel> _files = [];
  List<FileModel> get files => _files;

  List<TrashedFile> _trash = [];
  List<TrashedFile> get trash => List.unmodifiable(_trash);

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // Preferencias de la topbar (popup ⋮): orden, vista y filtro + búsqueda.
  FilesSort _sort = FilesSort.captureDay;
  FilesSort get sort => _sort;

  FilesViewMode _viewMode = FilesViewMode.byDate;
  FilesViewMode get viewMode => _viewMode;

  FilesFilter _filter = FilesFilter.all;
  FilesFilter get filter => _filter;

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  void setSort(FilesSort value) {
    if (_sort == value) return;
    _sort = value;
    _invalidateVisible();
    notifyListeners();
  }

  void setViewMode(FilesViewMode value) {
    if (_viewMode == value) return;
    _viewMode = value;
    notifyListeners();
  }

  void setFilter(FilesFilter value) {
    if (_filter == value) return;
    _filter = value;
    _invalidateCaches();
    notifyListeners();
  }

  // Preferencias de "Explorar" y de categoría (popup ⋮ de cada pantalla).

  ExploreViewMode _exploreViewMode = ExploreViewMode.compact;
  ExploreViewMode get exploreViewMode => _exploreViewMode;

  FileViewMode _layout = FileViewMode.list;
  FileViewMode get categoryLayout => _layout;

  ListingSortField _listingField = ListingSortField.name;
  ListingSortField get listingField => _listingField;

  SortDirection _listingDirection = SortDirection.asc;
  SortDirection get listingDirection => _listingDirection;

  void setExploreViewMode(ExploreViewMode value) {
    if (_exploreViewMode == value) return;
    _exploreViewMode = value;
    notifyListeners();
  }

  void setCategoryLayout(FileViewMode value) {
    if (_layout == value) return;
    _layout = value;
    notifyListeners();
  }

  // ─── Ajustes de NFiles (pantalla de ajustes) ──────────────────────────
  //
  // Se persisten con las claves `default_view_mode`, `show_hidden_files`,
  // etc. (ver `FilesViewPrefs`). Todos los setters notifican, así que el
  // guardado con debounce del `attach` no puede perderse ninguno.

  /// Mostrar archivos y carpetas ocultos (los que empiezan por `.`).
  ///
  /// Al cambiar se reescanea: el índice actual se construyó sin ellos y
  /// filtrarlos en memoria sería mentir sobre lo que hay en disco.
  bool _showHiddenFiles = false;
  bool get showHiddenFiles => _showHiddenFiles;

  void setShowHiddenFiles(bool value) {
    if (_showHiddenFiles == value) return;
    _showHiddenFiles = value;
    notifyListeners();
    unawaited(fetchFiles());
  }

  /// Mostrar la extensión en los títulos (`informe.pdf` vs `informe`).
  bool _showFileExtensions = true;
  bool get showFileExtensions => _showFileExtensions;

  void setShowFileExtensions(bool value) {
    if (_showFileExtensions == value) return;
    _showFileExtensions = value;
    notifyListeners();
  }

  /// Generar miniaturas solo con Wi-Fi.
  ///
  /// Hoy el motor de miniaturas es local (Rust, sin red), así que no hay
  /// tráfico que ahorrar: lo que el ajuste controla es el **trabajo en
  /// segundo plano**. Con el ajuste encendido se deja de pedir el
  /// prerrellenado por scroll ([ensureThumbnails]): las fichas se pintan
  /// con el icono de familia y la miniatura solo aparece si ya estaba en
  /// la caché de disco, que es el trabajo que se puede pausar sin romper
  /// nada.
  ///
  /// Es el punto donde entrará la comprobación de red real cuando las
  /// miniaturas seResolution desde NCloud; el consumidor (el servicio)
  /// no cambia cuando llegue.
  bool _thumbnailsWifiOnly = false;
  bool get thumbnailsWifiOnly => _thumbnailsWifiOnly;

  void setThumbnailsWifiOnly(bool value) {
    if (_thumbnailsWifiOnly == value) return;
    _thumbnailsWifiOnly = value;
    // El mapa en memoria es la caché de esta sesión: si se apaga el
    // ajuste, las miniaturas ya generadas se siguen usando. Al activarlo
    // no se borra nada, solo deja de pedir más.
    notifyListeners();
  }

  /// Pedir confirmación antes de un borrado definitivo.
  ///
  /// La UI de borrado aún no tiene diálogos de confirmación, así que el
  /// flag se persiste y se expone para cuando los haya. El valor por
  /// defecto (`true`) es el comportamiento que se espera entonces.
  bool _confirmDelete = true;
  bool get confirmDelete => _confirmDelete;

  void setConfirmDelete(bool value) {
    if (_confirmDelete == value) return;
    _confirmDelete = value;
    notifyListeners();
  }

  /// Vaciar la papelera automáticamente a los N días. `0` = nunca.
  int _autoEmptyTrashDays = 30;
  int get autoEmptyTrashDays => _autoEmptyTrashDays;

  void setAutoEmptyTrashDays(int value) {
    if (_autoEmptyTrashDays == value) return;
    _autoEmptyTrashDays = value;
    notifyListeners();
  }

  // -- Navegacion por directorio -----------------------------------------
  //
  // El indice global (`_files`) y el directorio actual son DOS cosas, y no
  // se mezclan a proposito: `visibleFiles` alimenta Recientes, Explorar y el
  // visor de archivos, asi que si `navigateTo` sustituyera `_files` por los
  // archivos de un subdirectorio, al entrar en una carpeta dejarian de verse
  // los demas archivos de todo el almacenamiento. Ese fallo no aparece en los
  // tests de navegacion, que mirarian solo lo recien escaneado.

  /// Archivos del directorio actual. Vacio mientras no se ha entrado en uno.
  List<FileModel> _currentDirFiles = const [];

  /// Carpetas del directorio actual.
  ///
  /// Van en una lista aparte y no mezcladas con los archivos porque se
  /// comportan distinto: no se abren en el visor, no se comparten, no tienen
  /// tamano, y en la rejilla se pintan con un componente que no es el de una
  /// imagen. Metidas en `_currentDirFiles` acabarian triesndo a abrirse.
  List<DirectoryEntry> _currentDirFolders = const [];

  /// Ruta del directorio en el que se esta. `null` = vista global.
  String? _currentPath;

  /// Pila de directorios visitados, del mas reciente al mas antiguo.
  final List<String> _history = [];

  /// Ruta del directorio actual, o `null` si se esta en la vista global.
  String? get currentPath => _currentPath;

  /// Historial de navegacion, del mas reciente al mas antiguo.
  ///
  /// Copia defensiva: si quien lo lee lo mutara, el estado interno se
  /// corromperia sin que ninguna asercion lo detectara.
  List<String> get navigationHistory => List.unmodifiable(_history);

  /// `true` si se ha entrado en algun directorio.
  bool get isBrowsingDirectory => _currentPath != null;

  /// Carpetas del directorio actual, ordenadas por nombre.
  ///
  /// El orden lo pone aqui y no el motor: `read_dir` devuelve en el orden que
  /// el sistema de archivos quiera, que cambia entre dispositivos y entre
  /// ejecuciones. Una lista de carpetas que se reordena sola al abrirla es
  /// desconcertante.
  List<DirectoryEntry> get currentFolders {
    final lista = [..._currentDirFolders];
    lista.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return lista;
  }

  /// Archivos de la vista de navegacion.
  ///
  /// Con un directorio abierto, los de ese directorio; sin el, el indice
  /// global ya filtrado. Nunca los dos mezclados: una categoria abierta
  /// dentro de una carpeta no puede mostrar los archivos de las demas.
  List<FileModel> get browsableFiles =>
      _currentPath == null ? visibleFiles : _currentDirFiles;

  /// Entra en [path], escaneandolo si hace falta.
  ///
  /// [path] vacio o `null` vuelve a la vista global, que es lo que hace el
  /// primer chip del breadcrumb cuando el mapa de raices no lo cubre.
  ///
  /// No lanza si la carpeta no existe o no se puede leer: deja la lista vacia
  /// y el breadcrumb apuntando donde se le pidio, que es el mismo resultado
  /// visual que una carpeta vacia. Lanzar desde aqui tiraria la pantalla
  /// entera por un `ENOENT`, y en un explorador el destino lo elige el
  /// usuario pero la carpeta puede desaparecer entre el tap y el escaneo.
  Future<void> navigateTo(String? path) async {
    // Ruta vacia = volver a la vista global. Se distingue de "carpeta que no
    // existe" justamente para que el breadcrumb pueda ofrecer esa opcion.
    if (path == null || path.trim().isEmpty) {
      _currentPath = null;
      _currentDirFiles = const [];
      _currentDirFolders = const [];
      notifyListeners();
      return;
    }

    final destino = _normalize(path);
    if (destino == _currentPath) return;

    _currentPath = destino;
    _currentDirFiles = const [];
    _currentDirFolders = const [];
    _recordHistory(destino);
    notifyListeners();

    try {
      // `StorageService.listDirectory` y no `FileService`: el primero lista
      // las entradas INMEDIATAS y devuelve tambien las carpetas, mientras que
      // el segundo recorre en profundidad y solo devuelve archivos. Con el
      // segundo no habia forma de drill-down, porque las carpetas no
      // aparecian nunca en la lista.
      final entries = _directoryLister(destino);
      // La navegacion pudo cambiar mientras listaba: si el usuario salto a
      // otro sitio con el breadcrumb, un resultado viejo no debe pisar la
      // vista nueva.
      if (_currentPath != destino) return;
      _currentDirFolders = [
        for (final e in entries)
          if (e.type == EntryType.directory) _aCarpeta(e),
      ];
      _currentDirFiles = [
        for (final e in entries)
          if (e.type != EntryType.directory) _aModelo(e),
      ];
    } catch (e) {
      debugPrint('No se pudo entrar en $destino: $e');
      if (_currentPath == destino) {
        _currentDirFiles = const [];
        _currentDirFolders = const [];
      }
    }
    if (_currentPath == destino) notifyListeners();
  }

  /// Convierte una entrada nativa en carpeta.
  DirectoryEntry _aCarpeta(FileEntry e) => DirectoryEntry.fromNative(e);

  /// Convierte una entrada nativa en [FileModel].
  FileModel _aModelo(FileEntry e) => FileModel(
        id: e.path,
        path: e.path,
        title: e.name,
        dateCreated: e.created ?? e.modified,
        dateModified: e.modified,
        sizeInBytes: e.size,
        isFavorite: false,
        isVideo: e.kind == FileKind.video,
      );

  /// Sube un nivel. `false` si ya estaba en la raiz y no hay adonde ir.
  Future<bool> navigateUp() async {
    if (_currentPath == null) return false;
    // Volver a la vista global en vez de quedarse en un `..` sin resolver:
    // `navigateTo` trata la ruta vacia como la raiz, que es lo que el
    // breadcrumb entiende.
    await navigateTo(_parentOf(_currentPath!));
    return true;
  }

  /// Quita la barra final, que haria que la misma carpeta se alcanzara por
  /// dos rutas distintas y por tanto con dos entradas de historial.
  static String _normalize(String path) =>
      path.endsWith('/') && path.length > 1
          ? path.substring(0, path.length - 1)
          : path;

  /// Ancestro de [path], o `null` si ya esta en la raiz.
  ///
  /// Devolver `null` en vez de `/` es lo que hace que `navigateUp` termine en
  /// la vista global: una barra de breadcrumbs con la raiz repetida dos
  /// veces ("Raiz > Raiz") es ruido.
  static String? _parentOf(String path) {
    final corte = _normalize(path).lastIndexOf('/');
    if (corte <= 0) return null;
    return _normalize(path).substring(0, corte);
  }

  /// Apunta el historial sin duplicar la entrada repetida.
  void _recordHistory(String path) {
    _history.remove(path);
    _history.insert(0, path);
    // El historial no crece sin limite: una sesion larga explorando puede
    // llegar a cientos de entradas y ninguna se consulta a mas de unas pocas.
    if (_history.length > _maxHistory) {
      _history.removeRange(_maxHistory, _history.length);
    }
  }

  /// Cuantas entradas de navegacion se recuerdan.
  static const int _maxHistory = 32;

  /// Listado de un directorio, sustituible en tests.
  ///
  /// Existia antes un `debugSetUseIsolateForScans` que apagaba el isolate del
  /// escaneo porque `compute` no completa bajo el reloj falso de
  /// `testWidgets`. Ya no hace falta: `listDirectory` es sincrono y no usa
  /// isolate, y eso es justo lo que lo hace utilizable desde un test de
  /// widget sin trucos.
  static List<FileEntry> _defaultLister(String path) =>
      StorageService.listDirectory(path);

  List<FileEntry> Function(String) _directoryLister = _defaultLister;

  /// Fija el listado de directorios. Pensado para tests.
  void debugSetDirectoryLister(List<FileEntry> Function(String) lister) {
    _directoryLister = lister;
  }


  /// Restaura de golpe todo el estado del popup **sin** notificar.
  ///
  /// Se llama al arrancar, antes de que la UI se suscriba: notificar
  /// ahí solo provocaría un repintado de una pantalla que aún no existe.
  void restoreViewState(FilesViewState state) {
    _sort = state.sort;
    _viewMode = state.viewMode;
    _filter = state.filter;
    _exploreViewMode = state.exploreViewMode;
    _layout = state.categoryLayout;
    _listingField = state.listingField;
    _listingDirection = state.listingDirection;
    _showHiddenFiles = state.showHiddenFiles;
    _showFileExtensions = state.showFileExtensions;
    _thumbnailsWifiOnly = state.thumbnailsWifiOnly;
    _confirmDelete = state.confirmDelete;
    _autoEmptyTrashDays = state.autoEmptyTrashDays;
    // Los ajustes de pantalla affects lo derivado (ocultos cambia el
    // escaneo, el resto no), pero la lista puede venir cacheada de antes
    // de la restauración.
    _invalidateVisible();
  }

  void setListingField(ListingSortField value) {
    if (_listingField == value) return;
    _listingField = value;
    _invalidateCaches();
    notifyListeners();
  }

  void setListingDirection(SortDirection value) {
    if (_listingDirection == value) return;
    _listingDirection = value;
    _invalidateCaches();
    notifyListeners();
  }

  /// Ordena según [listingField] y [listingDirection].
  ///
  /// Sobre una copia: la lista original va por fecha y la usan otras
  /// pantallas. El desempate es por nombre para que el orden sea total y
  /// no dependa del orden de llegada del escaneo.
  List<FileModel> sortListing(List<FileModel> files) {
    final list = List<FileModel>.of(files);
    int byField(FileModel a, FileModel b) {
      final cmp = switch (_listingField) {
        ListingSortField.name =>
          a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        ListingSortField.size => a.sizeInBytes.compareTo(b.sizeInBytes),
        ListingSortField.modified =>
          a.dateModified.compareTo(b.dateModified),
        ListingSortField.kind =>
          kindForPath(a.path).index.compareTo(kindForPath(b.path).index),
      };
      if (cmp != 0) return cmp;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    }

    list.sort((a, b) => _listingDirection == SortDirection.asc
        ? byField(a, b)
        : byField(b, a));
    return list;
  }

  void setSearchQuery(String value) {
    final q = value.trim().toLowerCase();
    if (_searchQuery == q) return;
    _searchQuery = q;
    _invalidateVisible();
    notifyListeners();
  }

  DateTime _sortKey(FileModel p) =>
      _sort == FilesSort.captureDay ? p.dateCreated : p.dateModified;

  /// Clave de día (año/mes/día) sobre la fecha de orden activa.
  DateTime dayKeyOf(FileModel p) {
    final d = _sortKey(p);
    return DateTime(d.year, d.month, d.day);
  }

  /// Archivos visibles agrupadas por día (orden desc). Para modo "Por fecha".
  ///
  /// Memoizado sobre la instancia vigente de [visibleFiles]: reagrupar en
  /// cada build es un paseo O(N) con un DateTime por archivo que no aporta
  /// nada si los datos no cambiaron.
  Map<DateTime, List<FileModel>> get visibleGroups {
    final source = visibleFiles;
    if (!identical(source, _groupsSource) || _cachedGroups == null) {
      final groups = <DateTime, List<FileModel>>{};
      for (final p in source) {
        groups.putIfAbsent(dayKeyOf(p), () => []).add(p);
      }
      final keys = groups.keys.toList()..sort((a, b) => b.compareTo(a));
      _cachedGroups = {for (final k in keys) k: groups[k]!};
      _groupsSource = source;
    }
    return _cachedGroups!;
  }

  List<FileModel>? _groupsSource;
  Map<DateTime, List<FileModel>>? _cachedGroups;

  // -- Criterios de la barra de filtros -----------------------------------
  //
  // Extensión, fecha y tamaño. NO se persisten a propósito: son de "lo que
  // estoy mirando ahora", no una preferencia. Si volvieran al reinicio, un
  // filtro de "PDF de hoy" ocultaría el almacenamiento entero al día
  // siguiente sin que nadie lo hubiera pedido.

  FileFilter _criteria = FileFilter.none;
  FileFilter get criteria => _criteria;

  void setCriteria(FileFilter value) {
    if (identical(_criteria, value)) return;
    _criteria = value;
    _invalidateVisible();
    notifyListeners();
  }

  void toggleExtensionFilter(String ext) =>
      setCriteria(_criteria.toggleExtension(ext));

  void clearCriteria() => setCriteria(FileFilter.none);

  /// Archivos tras aplicar filtro (todos / cámara), búsqueda y orden.
  /// Es lo que pinta la grilla principal.
  ///
  /// Memoizado e inmutable: el orden O(N log N) se paga una vez por cambio
  /// de datos o de criterio, no una vez por build. Como las pantallas
  /// reconstruyen en cada notificación (p. ej. al llegar miniaturas),
  /// recalcular aquí la ordenación era un tirón por frame con bibliotecas
  /// grandes. Se devuelve vista no modificable: quien necesite otro orden
  /// usa [sortListing], que copia.
  List<FileModel> get visibleFiles {
    var cached = _cachedVisible;
    if (cached == null) {
      Iterable<FileModel> list = _files;
      if (_filter == FilesFilter.camera) {
        // Filtro por CARPETA, no por el viejo álbum de cámara (eliminado
        // con la pantalla de Álbumes). Mismo criterio que Expl › Cámara.
        list = list.where(
          (f) => cameraFolderNames.contains(f.folderName.toLowerCase()),
        );
      }
      if (_searchQuery.isNotEmpty) {
        list = list.where(
          (p) =>
              p.title.toLowerCase().contains(_searchQuery) ||
              p.path.toLowerCase().contains(_searchQuery),
        );
      }
      // Los chips de la barra de filtros van aquí y no en la pantalla: es el
      // mismo `where` sobre `_files` que el resto de criterios, y meterlo
      // en el `itemBuilder` pagaría el paseo completo por cada ficha que
      // se pintara.
      final criterios = _criteria;
      if (!criterios.isEmpty) {
        list = list.where(criterios.matches);
      }
      final sorted = list.toList()
        ..sort((a, b) => _sortKey(b).compareTo(_sortKey(a)));
      cached = _cachedVisible = UnmodifiableListView(sorted);
    }
    return cached;
  }

  UnmodifiableListView<FileModel>? _cachedVisible;

  /// Invalida lo derivado de [_files], criterio de orden y búsqueda.
  void _invalidateVisible() {
    _cachedVisible = null;
    _groupsSource = null;
    _cachedGroups = null;
  }

  // Recarga dinámica: observación del disco + anti-solape de escaneos.
  final List<StreamSubscription<FileSystemEvent>> _watchers = [];
  Timer? _watchDebounce;
  Duration _watchDebounceDuration = const Duration(seconds: 2);
  bool _watching = false;
  bool _fetching = false;
  bool _disposed = false;

  // Derivados cacheados: se recalculan solo cuando cambian los datos.
  List<FileModel>? _cachedFavorites;
  List<FileModel>? _cachedVideos;
  List<FileModel>? _cachedRecentWeek;

  void _invalidateCaches() {
    _invalidateKindCaches();
    _cachedFavorites = null;
    _cachedVideos = null;
    _cachedRecentWeek = null;
    _invalidateVisible();
  }

  /// Retorna los archivos marcadas como favoritas
  List<FileModel> get favoriteFiles =>
      _cachedFavorites ??= _files.where((p) => p.isFavorite).toList();

  /// Solo vídeos (por extensión). Vive pineado en Álbumes.
  List<FileModel> get videos =>
      _cachedVideos ??= _files.where((p) => p.isVideo).toList();

  // ─── Categorías del explorador ────────────────────────────────────
  //
  // Sustituyen a las "colecciones" de la versión galería. Se cachean como
  // el resto de derivados porque Explor las repinta en cada scroll.

  final Map<FileKind, List<FileModel>> _cachedByKind = {};

  /// Vacía las cachés por familia al invalidar.
  void _invalidateKindCaches() => _cachedByKind.clear();

  /// Archivos de una familia, del más reciente al más viejo.
  ///
  /// La familia se decide por extensión ([kindForPath]), no por carpeta:
  /// en un gestor de archivos "¿dónde está?" no es lo mismo que
  /// "¿qué es?".
  List<FileModel> filesOfKind(FileKind kind) => _cachedByKind[kind] ??= _files
      .where((f) => kindForPath(f.path) == kind)
      .toList()
    ..sort((a, b) => b.dateModified.compareTo(a.dateModified));

  /// Imágenes.
  List<FileModel> get imageFiles => filesOfKind(FileKind.image);

  /// Documentos (PDF, Word, texto plano).
  ///
  /// Ya NO incluye hojas de cálculo ni presentaciones: tienen familia
  /// propia ([spreadsheetFiles], [presentationFiles]) y categoría propia en
  /// Explorar. Antes un `.xlsx` caía aquí y no se podía filtrar.
  List<FileModel> get documentFiles => filesOfKind(FileKind.document);

  /// Hojas de cálculo: `.xlsx`, `.xls`, `.ods`.
  List<FileModel> get spreadsheetFiles => filesOfKind(FileKind.spreadsheet);

  /// Presentaciones: `.pptx`, `.ppt`, `.odp`.
  List<FileModel> get presentationFiles => filesOfKind(FileKind.presentation);

  /// Toda la ofimática junta: documento, hoja y presentación.
  ///
  /// Es lo que usan las búsquedas y el "abrir con", donde al usuario le
  /// importa "documentos" y no si es un Excel o un PowerPoint. La
  /// diferenciación fina es para las categorías, que sí las separa.
  List<FileModel> get officeFiles => _files
      .where((f) => kindForPath(f.path).isOffice)
      .toList()
    ..sort((a, b) => b.dateModified.compareTo(a.dateModified));

  /// Música.
  List<FileModel> get musicFiles => filesOfKind(FileKind.audio);

  /// APKs instalables.
  List<FileModel> get apkFiles => filesOfKind(FileKind.apk);

  /// Comprimidos.
  List<FileModel> get archiveFiles => filesOfKind(FileKind.archive);

  /// "Archivos": todo lo que no es multimedia, documento ni paquete.
  ///
  /// Es el cajón de sastre que cierra la pantalla de categorías: el
  /// usuario tiene que poder llegar a lo que no encaja en ningún grupo.
  ///
  /// Se mantiene `kindForPath` y no el `kind` del `FileEntry` a propósito:
  /// el entry lo rellena el motor nativo cuando está disponible, y esta
  /// lista es el respaldo que tiene que funcionar igual sin él.
  List<FileModel> get otherFiles => _files
      .where((f) => const {
        FileKind.other,
        FileKind.code,
        FileKind.archive,
        FileKind.apk,
        FileKind.spreadsheet,
        FileKind.presentation,
      }.contains(kindForPath(f.path)))
      .toList()
    ..sort((a, b) => b.dateModified.compareTo(a.dateModified));

  /// Nombres de carpeta que resuelven la ubicación "Descargas".
  static const downloadFolderNames = {
    'downloads',
    'download',
    'descargas',
    'descarga',
  };

  /// Archivos guardados en la carpeta de descargas.
  List<FileModel> get downloadFiles => _files.where((f) {
    return downloadFolderNames.contains(f.folderName.toLowerCase());
  }).toList()
    ..sort((a, b) => b.dateModified.compareTo(a.dateModified));

  /// Nombres de carpeta que resuelven "Cámara".
  static const cameraFolderNames = {'camera', 'cámara', 'camara', 'dcim'};

  /// Nombres de carpeta que resuelven "Capturas".
  static const screenshotFolderNames = {
    'screenshots',
    'screenshot',
    'capturas',
    'captura',
    'captures',
    'screen shots',
  };

  /// Nombres de carpeta que resuelven "Grabaciones" (vídeos de cámara).
  static const recorderFolderNames = {
    'recordings',
    'recording',
    'grabaciones',
    'grabacion',
    'camera',
    'cámara',
    'camara',
  };

  /// Nombres de carpeta que resuelven "Instagram".
  static const instagramFolderNames = {'instagram'};

  /// Nombres de carpeta que resuelven "WhatsApp" (imágenes, vídeo,
  /// audio y documentos de la app).
  static const whatsappFolderNames = {
    'whatsapp',
    'whatsapp images',
    'whatsapp video',
    'whatsapp audio',
    'whatsapp documents',
  };

  /// Archivos de una carpeta concreta, resuelta por nombre.
  List<FileModel> filesInFolderNamed(Set<String> names) => _files.where((f) {
    return names.contains(f.folderName.toLowerCase());
  }).toList()
    ..sort((a, b) => b.dateModified.compareTo(a.dateModified));

  /// Cámara: fotos y vídeos de la carpeta de cámara.
  List<FileModel> get cameraFiles => filesInFolderNamed(cameraFolderNames);

  /// Capturas de pantalla.
  List<FileModel> get screenshotFiles =>
      filesInFolderNamed(screenshotFolderNames);

  /// Grabaciones de voz/vídeo.
  List<FileModel> get recorderFiles => filesInFolderNamed(recorderFolderNames);

  /// Lo guardado por Instagram.
  List<FileModel> get instagramFiles =>
      filesInFolderNamed(instagramFolderNames);

  /// Lo guardado por WhatsApp.
  List<FileModel> get whatsappFiles =>
      filesInFolderNamed(whatsappFolderNames);

  /// Volumen total en bytes de los archivos escaneados.
  int get totalBytes =>
      _files.fold(0, (sum, f) => sum + f.sizeInBytes);

  /// Volumen formateado ('1,4 GB') para la fila de espacio.
  String get totalFormattedSize => FileModel.formatBytes(totalBytes);

  /// Recientes: [visibleFiles] recortados a los últimos 7 días.
  ///
  /// Lo que pinta `RecentsScreen`: si la modificación es anterior a la
  /// ventana, el archivo se descarta aquí, antes de agrupar por día y de
  /// pedir miniaturas. Hereda filtros (cámara, búsqueda) y orden
  /// descendente de [visibleFiles]: los más recientes primero.
  List<FileModel> get recentFiles {
    final cutoff = DateTime.now().subtract(recentWindow);
    return [
      for (final f in visibleFiles)
        if (!f.dateModified.isBefore(cutoff)) f,
    ];
  }

  static const recentWindow = Duration(days: 7);

  List<FileModel> get recentWeek {
    if (_cachedRecentWeek != null) return _cachedRecentWeek!;
    final cutoff = DateTime.now().subtract(recentWindow);
    final list = _files.where((p) => !p.dateCreated.isBefore(cutoff)).toList()
      ..sort((a, b) => b.dateCreated.compareTo(a.dateCreated));
    return _cachedRecentWeek = list;
  }

  // ---- Carpeta privada ----

  List<FileModel> _private = [];
  List<FileModel> get privateFiles => List.unmodifiable(_private);

  Future<Directory> _vaultDir() async {
    if (privateDirOverride != null) return privateDirOverride!;
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'private'));
  }

  /// Carga la bóveda (archivos movidos fuera de las raíces escaneadas).
  Future<void> loadPrivate() async {
    try {
      final vault = PrivateVault(await _vaultDir());
      final files = await vault.files();
      final service = FileService(
        roots: [vault.dir],
        // La bóveda no se observa: es pequeña y se recarga tras cada
        // movimiento.
      );
      final scanned = await service.loadFiles();
      final byPath = {for (final s in scanned) s.path: s};
      _private = [
        for (final file in files)
          byPath[file.path] ??
              FileModel(
                id: file.path,
                path: file.path,
                title: p.basename(file.path),
                dateCreated: DateTime.now(),
                dateModified: DateTime.now(),
                sizeInBytes: 0,
              ),
      ]..sort((a, b) => b.dateModified.compareTo(a.dateModified));
    } catch (e) {
      debugPrint('No se pudo cargar la carpeta privada: $e');
      _private = [];
    }
  }

  /// Mueve un archivo del explorador a la carpeta privada (desaparece de
  /// explorador, álbumes y colecciones). Conserva el favorito.
  Future<void> moveToPrivate(String fileId) async {
    final index = _files.indexWhere((p) => p.id == fileId);
    if (index == -1) return;
    final file = _files[index];
    try {
      final vault = PrivateVault(await _vaultDir());
      final destPath = await vault.moveIn(File(file.path));
      _files.removeAt(index);
      final moved = file.copyWith(id: destPath, path: destPath);
      _private = [..._private, moved]
        ..sort((a, b) => b.dateModified.compareTo(a.dateModified));
      final store = _store;
      if (store != null) {
        final origins = store.privateOrigins();
        origins[destPath] = p.dirname(file.path);
        await store.savePrivateOrigins(origins);
        if (file.isFavorite) {
          final favs = store.favoriteIds()..remove(file.id);
          favs.add(destPath);
          await store.saveFavoriteIds(favs);
        }
      }
      _invalidateCaches();
      notifyListeners();
    } catch (e) {
      debugPrint('No se pudo mover a privada ${file.path}: $e');
    }
  }

  /// Devuelve un archivo privada a su carpeta original.
  Future<void> restoreFromPrivate(String fileId) async {
    final index = _private.indexWhere((p) => p.id == fileId);
    if (index == -1) return;
    final file = _private[index];
    try {
      final vault = PrivateVault(await _vaultDir());
      final origins = _store?.privateOrigins() ?? {};
      final originDir = origins[file.path];
      final Directory targetDir;
      if (originDir != null) {
        targetDir = Directory(originDir);
      } else {
        final roots = await _fileService.existingRoots();
        if (roots.isEmpty) return;
        targetDir = roots.first;
      }
      final restoredPath = await vault.moveOut(file.path, targetDir);
      _private = _private.where((p) => p.id != fileId).toList();
      final restored = file.copyWith(id: restoredPath, path: restoredPath);
      _files = [..._files, restored]
        ..sort((a, b) => b.dateModified.compareTo(a.dateModified));
      if (_store != null) {
        final next = _store!.privateOrigins()..remove(file.path);
        await _store!.savePrivateOrigins(next);
      }
      _invalidateCaches();
      notifyListeners();
    } catch (e) {
      debugPrint('No se pudo restaurar ${file.path}: $e');
    }
  }

  /// Archivos recién insertadas por la última actualización incremental.
  /// La UI lo usa para animar solo esas celdas (sin parpadeo global).
  Set<String> _lastInsertedIds = {};
  Set<String> get lastInsertedIds => _lastInsertedIds;

  /// Favoritos locales unidos con los de NPhotos (mejor esfuerzo).
  ///
  /// Guarda la unión en [_favoriteUnion] para que la UI la consulte sin
  /// E/S. Nunca lanza: sin fuente externa, son los locales.
  Future<Set<String>> _unionFavorites() async {
    final union =
        await _favorites.unionFavorites(_store?.favoriteIds() ?? const {});
    _favoriteUnion = union;
    return union;
  }

  /// Hidrata la grilla desde el snapshot local para apertura en ~0ms.
  /// No toca el estado de carga: si hay caché, pasa directo a loaded.
  Future<void> hydrateFromCache() async {
    // Vía rápida: índice nativo (<50ms, con tamaños y fechas reales).
    if (await hydrateFromNativeIndex()) return;
    if (_files.isNotEmpty || _state == FilesState.loaded) return;
    try {
      _store ??= await LocalStore.load();
    } catch (_) {
      return;
    }
    final snapshot = _store!.loadSnapshot();
    if (snapshot.isEmpty) return;
    final favoriteIds = await _unionFavorites();
    final trashedAt = _store!.trashedAt();
    final cached = <FileModel>[];
    for (final row in snapshot) {
      final path = row['path'] as String;
      if (trashedAt.containsKey(path)) continue;
      cached.add(
        FileModel(
          id: path,
          path: path,
          title: path.split(Platform.pathSeparator).last,
          dateCreated: DateTime.fromMillisecondsSinceEpoch(
            row['modified'] as int,
          ),
          dateModified: DateTime.fromMillisecondsSinceEpoch(
            row['modified'] as int,
          ),
          sizeInBytes: 0,
          isFavorite: favoriteIds.contains(path),
          isVideo: FileService.videoExtensions.any(
            (ext) => path.toLowerCase().endsWith(ext),
          ),
        ),
      );
    }
    if (cached.isEmpty) return;
    cached.sort((a, b) => b.dateModified.compareTo(a.dateModified));
    _files = cached;
    _invalidateCaches();
    _state = FilesState.loaded;
    notifyListeners();
  }

  /// Hidrata DIRECTAMENTE desde la BD local (redb en Rust, <50ms).
  ///
  /// Abre el `.redb`, hace `memcpy` de las filas y pinta sin tocar el disco.
  /// Devuelve `true` si hidrató (aunque sea con 0 filas pero con índice
  /// válido y estado `loaded`); `false` si no hay motor/BD y hay que caer
  /// al snapshot de `SharedPreferences`.
  Future<bool> hydrateFromNativeIndex() async {
    if (_files.isNotEmpty || _state == FilesState.loaded) return true;
    try {
      final opened = await _nativeIndex.open();
      // Espacio al instante, en paralelo a la hidratación (µs, sin escaneo).
      loadStorage();
      if (!opened) return false;
      try {
        _store ??= await LocalStore.load();
      } catch (_) {
        _store = null;
      }
      final favs = await _unionFavorites();
      final trashedAt = _store?.trashedAt() ?? const {};
      final hydrated = _nativeIndex.hydrate(favoriteIds: favs);
      if (hydrated.isEmpty) return false;
      final visible = [
        for (final f in hydrated)
          if (!trashedAt.containsKey(f.path)) f,
      ];
      if (visible.isEmpty) return false;
      _files = visible;
      _invalidateCaches();
      _state = FilesState.loaded;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('hidratación nativa falló, cae a snapshot: $e');
      return false;
    }
  }

  /// Lee `statvfs` y lo publica para la hoja de Espacio (instantáneo).
  ///
  /// Con [silent], no notifica: quien llama entrega su propio bloque
  /// después y un aviso intermedio sería un rebuild de más.
  void loadStorage({bool silent = false}) {
    try {
      final info = StorageService.quick(StorageService.defaultMount());
      if (info != null) {
        _storage = info;
        // No se notifica a propósito en caliente: la hoja lo lee al abrir.
        // Si ya hay oyentes de espacio, este sí avisa.
        if (!silent) notifyListeners();
      }
    } catch (e) {
      debugPrint('statvfs no disponible: $e');
    }
  }

  /// Sincronización incremental en segundo plano (sin `loading`).
  ///
  /// Compara el `mtime` de cada raíz con lo persistido y re-escanea SOLO las
  /// que cambiaron. Las intactas se saltan: sin volver a escanear todo el
  /// disco desde cero. Pensado para correr tras `hydrateFromNativeIndex`
  /// sin bloquear la UI (el llamante lo lanza sin `await` o en isolate).
  ///
  /// El re-escaneo hereda el modo del servicio principal: en producción va
  /// en isolate y en tests corre en línea (bajo reloj falso `compute`
  /// nunca completa).
  Future<void> syncIncrementalBackground() async {
    if (_fetching || _disposed) return;
    // Sin índice no hay diff posible: escaneo completo como antes.
    if (!_nativeIndex.isAvailable) {
      await fetchFiles(silent: _files.isNotEmpty);
      return;
    }
    try {
      final existing = await _fileService.existingRoots();
      if (existing.isEmpty || _disposed) return;
      final changedPaths =
          _nativeIndex.changedRoots(existing).toSet();
      if (changedPaths.isEmpty) {
        // Nada cambió en disco: solo refresca espacio y sale.
        loadStorage();
        return;
      }
      final changed =
          existing.where((d) => changedPaths.contains(d.path)).toList();
      final service = FileService(
        roots: changed,
        useIsolate: _fileService.useIsolate,
        showHidden: _showHiddenFiles,
      );
      final fresh = await service.loadFiles();
      if (_disposed) return;
      if (fresh.isEmpty) {
        _nativeIndex.persist(_files, existing);
        return;
      }
      // Fusión: quita lo viejo de esas raíces y mete lo fresco.
      final keep = _files
          .where((f) => !changedPaths.contains(p.dirname(f.path)))
          .toList();
      // Respeta papelera/favoritos persistidos (unidos con NPhotos).
      try {
        _store ??= await LocalStore.load();
      } catch (_) {}
      final favs = await _unionFavorites();
      final trashedAt = _store?.trashedAt() ?? {};
      final next = <FileModel>[];
      final nextTrash = List<TrashedFile>.of(_trash);
      for (final f in [...keep, ...fresh]) {
        final withFav =
            favs.contains(f.id) ? f.copyWith(isFavorite: true) : f;
        if (trashedAt.containsKey(withFav.id)) {
          if (!nextTrash.any((t) => t.file.id == withFav.id)) {
            nextTrash.add(
              TrashedFile(file: withFav, trashedAt: trashedAt[withFav.id]!),
            );
          }
        } else {
          next.add(withFav);
        }
      }
      next.sort((a, b) => b.dateModified.compareTo(a.dateModified));
      _lastInsertedIds = _applyIncrementalUpdate(next, nextTrash);
      await _saveSnapshot(next);
      loadStorage(silent: true);
      _state = FilesState.loaded;
      notifyListeners();
      // Índice nativo DESPUÉS de pintar, como en `fetchFiles`.
      _nativeIndex.persist(next, existing);
    } catch (e) {
      debugPrint('sync incremental falló, cae a fetch: $e');
      await fetchFiles(silent: _files.isNotEmpty);
    }
  }

  Future<void> fetchFiles({bool silent = false}) async {
    // Anti-solape: el watcher, el pull-to-refresh y el resume pueden
    // pedir recargas a la vez; solo un escaneo corre al mismo tiempo.
    if (_fetching) return;
    _fetching = true;
    // Si ya se entregó el bloque de datos con su notificación, el `finally`
    // no vuelve a notificar: un rebuild redundante con 30k filas es un
    // tirón visible.
    var delivered = false;
    // Carga silenciosa: si ya hay datos, no se emite loading para evitar
    // pantallas de carga repetitivas y parpadeos.
    final bool showLoading = !silent || _files.isEmpty;
    if (showLoading) {
      _state = FilesState.loading;
      _errorMessage = null;
      notifyListeners();
    }

    if (Platform.isAndroid) {
      final hasPermission = await _requestAndroidPermissions();
      if (!hasPermission) {
        _state = FilesState.permissionDenied;
        _fetching = false;
        notifyListeners();
        return;
      }
    }

    try {
      // El store es opcional en memoria si la plataforma no lo soporta
      // (p. ej. en tests sin plugin): sin persistencia la app sigue viva.
      try {
        _store ??= await LocalStore.load();
      } catch (e) {
        debugPrint('LocalStore no disponible, modo memoria: $e');
        _store = null;
      }

      // El ajuste de ocultos vive en el ajuste, no en el servicio: se pide
      // una copia con el valor vigente para que un cambio a mitad de sesión
      // no espere al siguiente arranque.
      final loaded = await _fileService.withHidden(_showHiddenFiles).loadFiles();
      final favoriteIds = await _unionFavorites();
      final trashedAt = _store?.trashedAt() ?? {};

      final nextFiles = <FileModel>[];
      final nextTrash = <TrashedFile>[];
      for (final file in loaded) {
        final withFavorite = favoriteIds.contains(file.id)
            ? file.copyWith(isFavorite: true)
            : file;
        final trashed = trashedAt[file.id];
        if (trashed != null) {
          nextTrash.add(TrashedFile(file: withFavorite, trashedAt: trashed));
        } else {
          nextFiles.add(withFavorite);
        }
      }

      if (silent && _files.isNotEmpty) {
        // Actualización incremental: inserta lo nuevo al inicio sin
        // recargar ni parpadear. La fusión ya no notifica por su cuenta.
        _lastInsertedIds = _applyIncrementalUpdate(nextFiles, nextTrash);
      } else {
        _files = nextFiles;
        _trash = nextTrash;
        _lastInsertedIds = {};
        _invalidateCaches();
      }

      await _pruneStaleRecords(
        loaded.map((p) => p.id).toSet(),
        {for (final file in nextFiles) p.dirname(file.path)},
      );
      await loadPrivate();
      await _saveSnapshot(nextFiles);
      loadStorage(silent: true);
      _state = FilesState.loaded;
      notifyListeners();
      delivered = true;
      // Persistencia pesada (N cruces FFI) DESPUÉS de pintar: la UI ya
      // tiene su bloque y el frame sale sin esperar al índice nativo.
      await _persistNativeIndex(nextFiles);
    } catch (e) {
      _errorMessage = 'Error al cargar los archivos: $e';
      _state = FilesState.error;
    } finally {
      _fetching = false;
      if (!delivered) notifyListeners();
    }
  }

  /// Persiste el árbol + mtimes para la próxima hidratación <50ms.
  /// Best-effort y fuera del camino de pintado: si no hay motor, el
  /// snapshot de arriba ya cubre.
  Future<void> _persistNativeIndex(List<FileModel> files) async {
    if (_disposed) return;
    try {
      await _nativeIndex.open();
      final roots = await _fileService.existingRoots();
      if (_disposed) return;
      _nativeIndex.persist(files, roots);
    } catch (e) {
      debugPrint('no se pudo persistir el índice nativo: $e');
    }
  }

  /// Observa las carpetas de origen y recarga sola cuando aparece, se
  /// mueve o se borra un archivo. Con debounce para no escanear por cada
  /// evento en ráfagas (p. ej. descargas múltiples o ráfagas de cámara).
  /// Idempotente: llamar dos veces no duplica observadores.
  /// Barrel de motores: elige nativo si lo hay, si no Dart.
  ///
  /// Vive en el controlador porque es el punto donde la app decide "qué
  /// motor y con qué política".
  ///
  /// Antes el motor venía de `NexoraFs` y el perfil de `NexoraCore`, y por
  /// eso el registry se construit aquí. Ahora los dos viven en el mismo
  /// paquete, pero la frontera sigue igual: dentro de `NexoraCore`, solo
  /// `lib/src/native/` sabe de `dart:ffi`; el resto del núcleo y las apps
  /// hablan en Dart primitivo.
  final FsScannerRegistry engines = FsScannerRegistry();

  /// Miniaturas para las vistas de imagen, por la API asíncrona de
  /// `NexoraCore`.
  ///
  /// Ver [requestThumbnails]. Se inyecta para poder sustituirla en
  /// tests; por defecto usa la capa nativa con degradación a vacío.
  final ThumbsService thumbs;

  /// Índice de medios: EXIF y agrupación por día.
  final MediaIndexService media;

  FilesController({
    FileService? fileService,
    this._store,
    this.privateDirOverride,
    ThumbsService? thumbs,
    MediaIndexService? media,
    NativeFileIndex? nativeIndex,
    FavoritesService? favorites,
  })  : thumbs = thumbs ?? ThumbsService(),
        media = media ?? MediaIndexService(),
        _nativeIndex = nativeIndex ?? NativeFileIndex(),
        _favorites = favorites ?? FavoritesService(),
        _fileService = fileService ?? FileService() {
    // El perfil por defecto (alto) se empuja ya: sin esto el motor arranca
    // con su propia idea de qué es "alta" y puede no coincidir con la del
    // kit.
    engines.applyPerformanceProfile(2);
    // También a la capa de medios. Son dos caminos distintos al mismo
    // motor, y sin esto los isolate arrancarían con su perfil por
    // defecto en lugar del de la app.
    this.thumbs.setPerformanceProfile(2);
    this.media.setPerformanceProfile(2);
  }

  /// Aplica el perfil de rendimiento de `NexoraCore` al motor nativo.
  ///
  /// Se llama al cambiar de perfil. En gama baja el motor deja de leer
  /// cabeceras y recorta la caché de miniaturas, que es de donde sale el
  /// ahorro real de RAM.
  ///
  /// El perfil se propaga a los TRES caminos: el escaneo
  /// ([engines]), las miniaturas ([thumbs]) y el índice de medios
  /// ([media]). Solo propagar al escaneo dejaría las miniaturas en gama
  /// alta, que es justo lo que se quiere evitar.
  void applyPerformanceProfile(CorePerformance performance) {
    final index = switch (performance.mode) {
      CorePerformanceMode.low => 0,
      CorePerformanceMode.medium => 1,
      CorePerformanceMode.high => 2,
    };
    engines.applyPerformanceProfile(index);
    thumbs.setPerformanceProfile(index);
    media.setPerformanceProfile(index);
  }

  /// Miniaturas de un lote de imágenes, vía la API asíncrona.
  ///
  /// Devuelve un mapa `ruta original -> miniatura`. Sin motor nativo la
  /// lista viene vacía y la UI cae a su propio placeholder: degradar es
  /// el estado normal, no un error.
  ///
  /// Con el ajuste "solo con Wi-Fi" ([thumbnailsWifiOnly]) no genera
  /// nada: devuelve únicamente lo que ya está en el mapa de la sesión, sin
  /// tocar el motor. Es el punto donde se connecta una comprobación de red
  /// cuando las miniaturas seResolution desde la nube.
  ///
  /// Lotes acotados a [thumbBatch] porque cada tanda es un viaje al
  /// isolate y porque la memoria nativa del motor es proporcional al
  /// tamaño del lote.
  Future<Map<String, ThumbnailRef>> requestThumbnails(
    List<String> imagePaths, {
    int boxPx = ThumbBox.list,
  }) async {
    if (imagePaths.isEmpty) return const {};
    final out = <String, ThumbnailRef>{};
    for (final batch in _batched(imagePaths, thumbBatch)) {
      if (_disposed) return out;
      final refs = await thumbs.generate(batch, boxPx: boxPx);
      for (final ref in refs) {
        if (ref.isUsable) out[ref.source] = ref;
      }
    }
    return out;
  }

  /// Recuento de medios sin decodificar, para pintar un total antes de
  /// mover datos.
  ///
  /// `null` si no hay motor: quien llama decide si estimar o mostrar lo que
  /// ya tiene.
  Future<int?> countMedia(List<String> imagePaths) async {
    if (imagePaths.isEmpty) return 0;
    final meta = await media.readMetadata(imagePaths);
    return meta?.length;
  }

  /// Secciones por día para agrupar la vista de galería.
  Future<List<MediaSection>> groupByDay(List<String> imagePaths) async {
    if (imagePaths.isEmpty) return const [];
    await media.readMetadata(imagePaths);
    return media.group(groupBy: GroupBy.day);
  }

  /// Miniaturas ya generadas, por ruta original. El valor es la ruta del
  /// JPEG en la caché de Rust.
  final Map<String, String> _thumbnails = {};

  /// Miniaturas de las rutas dadas, usando la caché y generando lo que falte.
  ///
  /// Es idempotente: lo que ya está en [_thumbnails] no se vuelve a pedir, y
  /// lo que el motor tiene en disco sale de ahí sin coste. Se llama ANTES de
  /// pintar, nunca durante: generar un icono abre un isolate, y hacerlo en
  /// un `build` sería a la vez inútil y congelante.
  ///
  /// Avisa a los oyentes cuando hay miniaturas nuevas, que es lo que hace que
  /// las fichas aparezcan con su imagen sin que nadie tenga que forzar el
  /// rebuild.
  Future<Map<String, String>> ensureThumbnails(
    Iterable<String> paths, {
    int boxPx = ThumbBox.list,
  }) async {
    // "Solo con Wi-Fi" activo: no se genera nada. Se devuelve lo que ya
    // hay en el mapa de la sesión, así que una miniatura de disco que ya
    // se había resuelto sigue pintándose y no se tira trabajo ya hecho.
    if (_thumbnailsWifiOnly) return Map.unmodifiable(_thumbnails);

    final wanted = [for (final p in paths) if (!_thumbnails.containsKey(p)) p];
    if (wanted.isEmpty) return Map.unmodifiable(_thumbnails);

    final fresh = await thumbs.thumbnailsFor(wanted, boxPx: boxPx);
    if (_disposed || fresh.isEmpty) return Map.unmodifiable(_thumbnails);
    _thumbnails.addAll(fresh);
    notifyListeners();
    return Map.unmodifiable(_thumbnails);
  }

  /// Miniatura de una ruta, si ya se generó.
  String? thumbnailFor(String path) => _thumbnails[path];

  /// Genera la miniatura de UN archivo ahora, ignorando el ajuste de
  /// red.
  ///
  /// Es el camino de la demanda explícita (abrir un archivo), que es
  /// justo lo que "solo con Wi-Fi" no puede bloquear: el usuario pidió
  /// esa imagen, no un prerrellenado de la pantalla.
  Future<String?> generateThumbnail(
    String path, {
    int? boxPx,
  }) async {
    if (path.isEmpty) return null;
    final ya = _thumbnails[path];
    if (ya != null) return ya;
    final ref = await thumbs.generateOne(path, boxPx: boxPx);
    if (_disposed || ref == null || !ref.isUsable) return null;
    _thumbnails[path] = ref.path;
    notifyListeners();
    return ref.path;
  }

  /// Olvida las rutas del mapa en memoria.
  ///
  /// NO borra la caché de disco: eso es [clearThumbnailCache], que es más
  /// lento y de otra categoría. Esto solo hace que un cambio de tamaño de
  /// ficha vuelva a mirar el motor, que es lo que se quiere al pasar de
  /// mosaico a lista.
  void forgetThumbnails() {
    if (_thumbnails.isEmpty) return;
    _thumbnails.clear();
    notifyListeners();
  }

  /// Borra la caché de miniaturas en disco. Devuelve cuántos archivos.
  ///
  /// Nunca lanza: sin motor, o con un archivo en uso, responde 0 y la UI
  /// lo dice. Un ajuste que puede reventar la pantalla es peor que uno que
  /// no hace nada.
  Future<int> clearThumbnailCache() async {
    try {
      return await thumbs.clearCache();
    } catch (e) {
      debugPrint('no se pudo limpiar la caché de miniaturas: $e');
      return 0;
    }
  }

  /// Tamaño de tanda para miniaturas.
  ///
  /// Público a propósito: la app necesita saberlo para no pedir un lote
  /// gigante por su cuenta, y hay un test que lo vigila.
  static const int thumbBatch = 256;

  /// Parte [items] en trozos de [size], sin copiar más de lo necesario.
  static Iterable<List<T>> _batched<T>(List<T> items, int size) sync* {
    for (var i = 0; i < items.length; i += size) {
      yield items.sublist(
        i,
        i + size > items.length ? items.length : i + size,
      );
    }
  }

  Future<void> startWatching({
    Duration debounce = const Duration(seconds: 2),
  }) async {
    if (_watching || _disposed) return;
    _watching = true;
    _watchDebounceDuration = debounce;
    try {
      final roots = await _fileService.existingRoots();
      if (_disposed) return;
      for (final dir in roots) {
        try {
          _watchers.add(
            dir.watch(recursive: true).listen(
              _onWatchEvent,
              onError: (Object e) =>
                  debugPrint('Watch error en ${dir.path}: $e'),
            ),
          );
        } catch (e) {
          debugPrint('No se pudo observar ${dir.path}: $e');
        }
      }
    } catch (e) {
      debugPrint('startWatching falló: $e');
    }
  }

  void _onWatchEvent(FileSystemEvent event) {
    if (_disposed) return;
    _watchDebounce?.cancel();
    _watchDebounce = Timer(_watchDebounceDuration, () {
      if (!_disposed) fetchFiles(silent: true);
    });
  }

  /// Recarga inmediata (pull-to-refresh, botón, resume).
  Future<void> refresh() => fetchFiles();

  /// Recarga silenciosa de segundo plano: nunca muestra loading si ya hay
  /// datos; inserta lo nuevo al inicio con animación sutil en la UI.
  Future<void> refreshSilent() => fetchFiles(silent: true);

  /// Diferencia [next] contra el estado actual y lo fusiona.
  /// Retorna los ids nuevos (para animar su inserción al inicio).
  ///
  /// No notifica: quien llama entrega el bloque fusionado con un solo
  /// `notifyListeners`, para no pintar dos veces seguidas.
  Set<String> _applyIncrementalUpdate(
    List<FileModel> next,
    List<TrashedFile> nextTrash,
  ) {
    final currentIds = {for (final p in _files) p.id};
    final nextIds = {for (final p in next) p.id};
    final inserted = nextIds.difference(currentIds);

    if (inserted.isEmpty && next.length == _files.length) {
      // Sin altas ni bajas: actualiza metadatos in-place (favoritos, etc).
      final byId = {for (final p in next) p.id: p};
      var changed = false;
      for (var i = 0; i < _files.length; i++) {
        final updated = byId[_files[i].id];
        if (updated != null &&
            (updated.isFavorite != _files[i].isFavorite ||
                updated.dateModified != _files[i].dateModified)) {
          _files[i] = updated;
          changed = true;
        }
      }
      _trash = nextTrash;
      if (changed) _invalidateCaches();
      return const {};
    }

    _files = next;
    _trash = nextTrash;
    _invalidateCaches();
    return inserted;
  }

  Future<void> _saveSnapshot(List<FileModel> files) async {
    final store = _store;
    if (store == null) return;
    try {
      await store.saveSnapshot([
        for (final p in files.take(500))
          {'path': p.path, 'modified': p.dateModified.millisecondsSinceEpoch},
      ]);
    } catch (e) {
      debugPrint('No se pudo guardar snapshot: $e');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _watchDebounce?.cancel();
    for (final sub in _watchers) {
      sub.cancel();
    }
    _watchers.clear();
    super.dispose();
  }

  /// Elimina registros de favoritos/papelera/pines de archivos que ya
  /// no existen.
  Future<void> _pruneStaleRecords(
    Set<String> knownIds,
    Set<String> knownAlbumPaths,
  ) async {
    final store = _store;
    if (store == null) return;

    final favorites = store.favoriteIds();
    final prunedFavorites = favorites.intersection(knownIds);
    if (prunedFavorites.length != favorites.length) {
      await store.saveFavoriteIds(prunedFavorites);
    }

    final trashed = store.trashedAt();
    trashed.removeWhere((id, _) => !knownIds.contains(id));
    if (trashed.length != store.trashedAt().length) {
      await store.saveTrashed(trashed);
    }

  }

  Future<void> _persistFavorites() async {
    final store = _store;
    if (store == null) return;
    await store.saveFavoriteIds({
      for (final file in _files)
        if (file.isFavorite) file.id,
      for (final trashed in _trash)
        if (trashed.file.isFavorite) trashed.file.id,
      for (final file in _private)
        if (file.isFavorite) file.id,
    });
  }

  Future<void> _persistTrash() async {
    final store = _store;
    if (store == null) return;
    await store.saveTrashed({
      for (final trashed in _trash)
        trashed.file.id: trashed.trashedAt,
    });
  }

  Future<void> toggleFavorite(String fileId) async {
    final index = _files.indexWhere((p) => p.id == fileId);
    if (index == -1) return;
    _files[index] = _files[index].copyWith(
      isFavorite: !_files[index].isFavorite,
    );
    _invalidateCaches();
    notifyListeners();
    await _persistFavorites();
  }

  /// Mueve un archivo a la papelera (el archivo se conserva en disco).
  Future<void> moveToTrash(String fileId) async {
    final index = _files.indexWhere((p) => p.id == fileId);
    if (index == -1) return;
    final file = _files.removeAt(index);
    _trash.add(TrashedFile(file: file, trashedAt: DateTime.now()));
    _invalidateCaches();
    notifyListeners();
    await _persistTrash();
  }

  /// Devuelve un archivo de la papelera al explorador.
  Future<void> restoreFromTrash(String fileId) async {
    final index = _trash.indexWhere((t) => t.file.id == fileId);
    if (index == -1) return;
    final trashed = _trash.removeAt(index);
    _files.add(trashed.file);
    _files.sort((a, b) => b.dateModified.compareTo(a.dateModified));
    _invalidateCaches();
    notifyListeners();
    await _persistTrash();
  }

  /// Elimina definitivamente: borra el archivo (best-effort) y el registro.
  Future<void> deletePermanently(String fileId) async {
    final index = _trash.indexWhere((t) => t.file.id == fileId);
    if (index == -1) return;
    final trashed = _trash.removeAt(index);
    try {
      await File(trashed.file.path).delete();
    } catch (e) {
      debugPrint('No se pudo borrar ${trashed.file.path}: $e');
    }
    _invalidateCaches();
    notifyListeners();
    await _persistTrash();
  }

  /// Vacía la papelera por completo (best-effort por archivo).
  Future<void> emptyTrash() async {
    final paths = _trash.map((t) => t.file.path).toList();
    _trash.clear();
    _invalidateCaches();
    notifyListeners();
    await _persistTrash();
    for (final path in paths) {
      try {
        await File(path).delete();
      } catch (e) {
        debugPrint('No se pudo borrar $path: $e');
      }
    }
  }

  // ─── Acciones en lote (selección múltiple) ───

  /// Favoritos: si alguno del lote no es favorito, los marca todos.
  /// Si todos ya son favoritos, los quita.
  Future<void> toggleFavoritesBatch(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    final set = list.toSet();
    final allFavorite =
        _files.where((p) => set.contains(p.id)).every((p) => p.isFavorite);
    for (var i = 0; i < _files.length; i++) {
      if (!set.contains(_files[i].id)) continue;
      _files[i] = _files[i].copyWith(isFavorite: !allFavorite);
    }
    _invalidateCaches();
    notifyListeners();
    await _persistFavorites();
  }

  /// Manda varios elementos a la papelera de una vez.
  Future<void> moveToTrashBatch(Iterable<String> ids) async {
    final set = ids.toSet();
    if (set.isEmpty) return;
    final now = DateTime.now();
    final moved = _files.where((p) => set.contains(p.id)).toList();
    if (moved.isEmpty) return;
    _files = _files.where((p) => !set.contains(p.id)).toList();
    _trash = [..._trash, for (final p in moved) TrashedFile(file: p, trashedAt: now)];
    _invalidateCaches();
    notifyListeners();
    await _persistTrash();
  }

  /// Elimina de verdad varios archivos (usado por la papelera).
  Future<void> deletePermanentlyBatch(Iterable<String> ids) async {
    final set = ids.toSet();
    if (set.isEmpty) return;
    final removed = _trash.where((t) => set.contains(t.file.id)).toList();
    if (removed.isEmpty) return;
    _trash = _trash.where((t) => !set.contains(t.file.id)).toList();
    _invalidateCaches();
    notifyListeners();
    await _persistTrash();
    for (final trashed in removed) {
      try {
        await File(trashed.file.path).delete();
      } catch (e) {
        debugPrint('No se pudo borrar ${trashed.file.path}: $e');
      }
    }
  }

  /// Restaura varios elementos de la papelera.
  Future<void> restoreFromTrashBatch(Iterable<String> ids) async {
    final set = ids.toSet();
    final restored = _trash.where((t) => set.contains(t.file.id)).toList();
    if (restored.isEmpty) return;
    _trash = _trash.where((t) => !set.contains(t.file.id)).toList();
    _files = [..._files, for (final t in restored) t.file]
      ..sort((a, b) => b.dateModified.compareTo(a.dateModified));
    _invalidateCaches();
    notifyListeners();
    await _persistTrash();
  }

  Future<bool> _requestAndroidPermissions() async {
    // Acceso total primero: con él sobra todo lo demás (documentos,
    // descargas, Android/media). Es solo lectura de estado, no abre nada.
    // En APIs <30 el plugin lo degrada y se sigue con el flujo clásico.
    try {
      if (await Permission.manageExternalStorage.isGranted) return true;
    } catch (_) {
      // Sin canal (tests) se cae al flujo clásico, que también falla
      // cerrado y deja el estado en permissionDenied sin reventar.
    }
    if (await Permission.photos.request().isGranted) return true;
    if (await Permission.storage.request().isGranted) return true;
    return false;
  }

  /// Resuelve el acceso al almacenamiento desde la pantalla de denegado.
  ///
  /// Reintenta medios y, si sigue denegado, abre los Ajustes del sistema
  /// para conceder "Acceso a todos los archivos". Al volver, el resume de
  /// la app dispara `refresh()` y la lista aparece sin más toques.
  Future<void> resolveStorageAccess() async {
    if (!Platform.isAndroid) {
      await refresh();
      return;
    }
    if (await _requestAndroidPermissions()) {
      await refresh();
      return;
    }
    try {
      await openAppSettings();
    } catch (_) {
      // Sin canal no hay ajustes que abrir; el estado ya es denegado.
    }
  }
}
