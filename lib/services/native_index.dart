// lib/services/native_index.dart
//
// Hidratación instantánea (<50ms) + sincronización incremental por `mtime`.
//
// # Protocolo
//
// 1. Al arrancar: `open()` (support dir) + `hydrate()` → `List<FileModel>`
//    con un `memcpy` desde redb, sin tocar el disco. La grilla pinta al
//    instante aunque el escaneo aún no haya empezado.
// 2. En segundo plano (sin bloquear la UI): `changedRoots()` filtra por
//    `mtime` de carpeta y solo esas se re-escannean con `FileService`.
// 3. Tras el diff: `persist()` guarda filas + `mtime` de carpetas.
//
// Sin motor nativo todo degrada a `[]`/`false` y el controlador cae a su
// snapshot de `SharedPreferences`: el índice es una optimización, no un
// requisito.
import 'dart:io';

import 'package:NexoraCore/NexoraCore.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/file_model.dart';
import 'file_service.dart';

/// Nombre del `.redb` en el support dir de la app.
const String kNFilesIndexName = 'nfiles_index.redb';

class NativeFileIndex {
  final NativeIndexStore _store;
  final Future<Directory> Function()? supportDirForTest;

  NativeFileIndex({
    NativeIndexStore? store,
    this.supportDirForTest,
  }) : _store = store ?? NativeIndexStore();

  bool get isAvailable => _store.isAvailable;

  /// Abre el `.redb`. `false` sin motor: el llamante usa el snapshot viejo.
  Future<bool> open() async {
    if (!_store.isAvailable) return false;
    try {
      final override = supportDirForTest;
      final dir = override != null
          ? await override()
          : await getApplicationSupportDirectory();
      final dbPath = p.join(dir.path, kNFilesIndexName);
      return _store.open(dbPath);
    } catch (_) {
      return false;
    }
  }

  /// Lee todo el índice y lo mapea a [FileModel]. Rápido por diseño: un
  /// `memcpy` desde redb, sin `stat` por archivo.
  List<FileModel> hydrate({Set<String>? favoriteIds}) {
    if (!_store.isAvailable) return const [];
    final entries = _store.load();
    if (entries.isEmpty) return const [];
    final favs = favoriteIds ?? const <String>{};
    final out = <FileModel>[
      for (final e in entries)
        if (e.type == EntryType.file)
          FileModel(
            id: e.path,
            path: e.path,
            title: p.basename(e.path),
            dateCreated: e.created ?? e.modified,
            dateModified: e.modified,
            sizeInBytes: e.size < 0 ? 0 : e.size,
            isFavorite: favs.contains(e.path),
            isVideo: FileService.videoExtensions.contains(
              p.extension(e.path).toLowerCase(),
            ),
          ),
    ];
    out.sort((a, b) => b.dateModified.compareTo(a.dateModified));
    return out;
  }

  /// Raíces cuyo `mtime` cambió (o nuevas): SOLO esas se re-escannean.
  ///
  /// Recibe directorios existentes (ya filtrados por `existingRoots`).
  /// Sin índice devuelve todas (escaneo completo como antes).
  List<String> changedRoots(List<Directory> existing) {
    final paths = [for (final d in existing) d.path];
    return _store.changedDirs(paths);
  }

  /// Persiste filas + `mtime` de las raíces escaneadas.
  int persist(List<FileModel> files, List<Directory> roots) {
    if (!_store.isAvailable || files.isEmpty) return 0;
    final entries = <FileEntry>[
      for (final f in files)
        FileEntry(
          path: f.path,
          name: f.title,
          type: EntryType.file,
          size: f.sizeInBytes,
          modified: f.dateModified,
          created: f.dateCreated,
          kind: kindForPath(f.path),
          isHidden: false,
        ),
    ];
    final n = _store.putAll(entries);
    _store.touchDirs([for (final r in roots) r.path]);
    return n;
  }

  int? count() => _store.count();
}
