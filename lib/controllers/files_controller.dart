// lib/controllers/files_controller.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

// El dominio de archivos (FileKind, FsScannerRegistry, kindForPath…) y el
// perfil de rendimiento (CorePerformance) viven en el MISMO paquete: el motor
// nativo en Rust pasó de NexoraFs a NexoraCore, así que basta un import.
import 'package:NexoraCore/NexoraCore.dart';
import '../models/file_model.dart';
import '../services/local_store.dart';
import '../services/file_service.dart';
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

/// Cómo se ven los archivos dentro de una categoría: lista o cuadrícula.
enum CategoryLayout { list, grid }

/// Orden alfabético dentro de una categoría.
enum CategorySort { az, za }

class TrashedFile {
  final FileModel file;
  final DateTime trashedAt;

  const TrashedFile({required this.file, required this.trashedAt});
}

/// Pin de la pantalla Álbumes (máx 4).
///
/// [id] es `album:<dirPath>` para carpetas reales o `__videos__`,
/// `__trash__`, `__favorites__` para listas sintéticas.
class FilesController extends ChangeNotifier {
  final FileService _fileService;
  LocalStore? _store;

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

  CategoryLayout _categoryLayout = CategoryLayout.list;
  CategoryLayout get categoryLayout => _categoryLayout;

  CategorySort _categorySort = CategorySort.az;
  CategorySort get categorySort => _categorySort;

  void setExploreViewMode(ExploreViewMode value) {
    if (_exploreViewMode == value) return;
    _exploreViewMode = value;
    notifyListeners();
  }

  void setCategoryLayout(CategoryLayout value) {
    if (_categoryLayout == value) return;
    _categoryLayout = value;
    notifyListeners();
  }

  void setCategorySort(CategorySort value) {
    if (_categorySort == value) return;
    _categorySort = value;
    notifyListeners();
  }

  /// Ordena por nombre según [categorySort] (A→Z o Z→A).
  ///
  /// Sobre una copia: la lista original va por fecha y la usan otras
  /// pantallas.
  List<FileModel> applyCategorySort(List<FileModel> files) {
    final list = List<FileModel>.of(files);
    list.sort((a, b) {
      final cmp = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      return _categorySort == CategorySort.az ? cmp : -cmp;
    });
    return list;
  }

  void setSearchQuery(String value) {
    final q = value.trim().toLowerCase();
    if (_searchQuery == q) return;
    _searchQuery = q;
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
  Map<DateTime, List<FileModel>> get visibleGroups {
    final groups = <DateTime, List<FileModel>>{};
    for (final p in visibleFiles) {
      groups.putIfAbsent(dayKeyOf(p), () => []).add(p);
    }
    final keys = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    return {for (final k in keys) k: groups[k]!};
  }

  /// Archivos tras aplicar filtro (todos / cámara), búsqueda y orden.
  /// Es lo que pinta la grilla principal.
  List<FileModel> get visibleFiles {
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
    final sorted = list.toList()
      ..sort((a, b) => _sortKey(b).compareTo(_sortKey(a)));
    return sorted;
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

  /// Documentos (PDF, ofimática, texto).
  List<FileModel> get documentFiles => filesOfKind(FileKind.document);

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
  List<FileModel> get otherFiles => _files
      .where((f) => const {
        FileKind.other,
        FileKind.code,
        FileKind.archive,
        FileKind.apk,
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

  /// Volumen total en bytes de los archivos escaneados.
  int get totalBytes =>
      _files.fold(0, (sum, f) => sum + f.sizeInBytes);

  /// Volumen formateado ('1,4 GB') para la fila de espacio.
  String get totalFormattedSize => FileModel.formatBytes(totalBytes);

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

  /// Hidrata la grilla desde el snapshot local para apertura en ~0ms.
  /// No toca el estado de carga: si hay caché, pasa directo a loaded.
  Future<void> hydrateFromCache() async {
    if (_files.isNotEmpty || _state == FilesState.loaded) return;
    try {
      _store ??= await LocalStore.load();
    } catch (_) {
      return;
    }
    final snapshot = _store!.loadSnapshot();
    if (snapshot.isEmpty) return;
    final favoriteIds = _store!.favoriteIds();
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

  Future<void> fetchFiles({bool silent = false}) async {
    // Anti-solape: el watcher, el pull-to-refresh y el resume pueden
    // pedir recargas a la vez; solo un escaneo corre al mismo tiempo.
    if (_fetching) return;
    _fetching = true;
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

      final loaded = await _fileService.loadFiles();
      final favoriteIds = _store?.favoriteIds() ?? {};
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
        // recargar ni parpadear. Solo se notifica una vez.
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
      _state = FilesState.loaded;
    } catch (e) {
      _errorMessage = 'Error al cargar los archivos: $e';
      _state = FilesState.error;
    } finally {
      _fetching = false;
      notifyListeners();
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
  })  : thumbs = thumbs ?? ThumbsService(),
        media = media ?? MediaIndexService(),
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
      if (changed) {
        _invalidateCaches();
        notifyListeners();
      }
      return const {};
    }

    _files = next;
    _trash = nextTrash;
    _invalidateCaches();
    notifyListeners();
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
    if (await Permission.photos.request().isGranted) return true;
    if (await Permission.storage.request().isGranted) return true;
    return false;
  }
}
