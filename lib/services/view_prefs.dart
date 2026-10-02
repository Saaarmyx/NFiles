// lib/services/view_prefs.dart
//
// Persistencia del popup de la topbar (⋮) de NFiles: orden, modo de
// vista, filtro, y las preferencias de Explorar y Categorías.
//
// Gemelo del de NPhotos y con el mismo criterio: el estado completo
// vive en una pieza (`FilesViewState`) que el controller restaura de
// golpe sin notificar, y el guardado cuelga de un único `addListener`.
// Todos los setters del controller pasan por `notifyListeners()`, así que
// no hay ningún ajuste que pueda olvidarse de persistir.
import 'dart:async';

import 'package:NexoraUi/NexoraUi.dart';

import '../controllers/files_controller.dart';

/// Lee y escribe [FilesViewState] en el almacén.
class FilesViewPrefs {
  final NViewPrefs _prefs;
  Timer? _debounce;

  FilesViewPrefs(NKeyValueStore store)
      : _prefs = NViewPrefs(store, prefix: 'nfiles_view_');

  /// Lee lo guardado. Cada clave cae a su valor por defecto, así que un
  /// almacén a medias no deja ningún ajuste sin valor.
  ///
  /// Las siete claves de la pantalla de ajustes se leen aquí y no en la
  /// pantalla: la pantalla pinta lo que dice el controller, y el controller
  /// se restaura de golpe al arrancar. Si se leyeran allí, el primer frame
  /// mostraría los valores por defecto durante el salto al valor guardado.
  FilesViewState load() => FilesViewState(
        sort: _prefs.enumOf(FilesSort.values, 'sort', FilesSort.captureDay),
        viewMode: _prefs.enumOf(
            FilesViewMode.values, 'view_mode', FilesViewMode.byDate),
        filter:
            _prefs.enumOf(FilesFilter.values, 'filter', FilesFilter.all),
        exploreViewMode: _prefs.enumOf(ExploreViewMode.values,
            'explore_view_mode', ExploreViewMode.compact),
        categoryLayout: _prefs.enumOf(CategoryLayout.values,
            'default_view_mode', CategoryLayout.list),
        listingField: _prefs.enumOf(ListingSortField.values,
            'default_sort_field', ListingSortField.name),
        // La clave es la que escribe [FilesViewState.toMap]
        // (`sort_direction`), no una variante: leer y escribir con nombres
        // distintos deja el ajuste en su valor por defecto para siempre,
        // sin ningún error visible.
        listingDirection: _prefs.enumOf(
            SortDirection.values, 'sort_direction', SortDirection.asc),
        showHiddenFiles: _prefs.boolOf('show_hidden_files'),
        showFileExtensions: _prefs.boolOf('show_file_extensions',
            fallback: true),
        thumbnailsWifiOnly: _prefs.boolOf('thumbnails_wifi_only'),
        confirmDelete: _prefs.boolOf('confirm_delete', fallback: true),
        autoEmptyTrashDays:
            _prefs.intOf('auto_empty_trash_days', fallback: 30),
      );

  /// Aplica lo guardado al controller, sin emitir cambios.
  void applyTo(FilesController c, FilesViewState state) {
    c.restoreViewState(state);
  }

  Future<void> save(FilesViewState state) => _prefs.writeAll(state.toMap());

  /// Guarda el estado actual del controller, agrupando 250 ms.
  void attach(FilesController c) {
    c.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 250), () {
        unawaited(save(FilesViewState.of(c)));
      });
    });
  }

  void dispose() {
    _debounce?.cancel();
    _debounce = null;
  }
}
