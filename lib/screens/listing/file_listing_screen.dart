// lib/screens/listing/file_listing_screen.dart
//
// Listado base de una carpeta o categoría (Mi Teléfono, Descargas, Cámara,
// Documentos...): UNA sola pantalla genérica para todas.
//
// TopBar con atrás, título dinámico y dos menús (vista/orden + general).
// Renderizado condicional: lista ([NRecentFileCard] en
// [NGroupedCardContainer]) o cuadrícula ([NGridFileCard] agrupada por
// secciones). El orden lo pone [FilesController.sortListing] y el modo
// [FilesController.categoryLayout]: la pantalla no ordena ni recuerda nada.
//
// Es `StatefulWidget` por tres motivos, y los tres son sobre reconstruir:
//  1. Recordar que las miniaturas ya se pidieron (una por rebuild serían
//     decenas de isolates por scroll) y memoizar sus providers para que
//     las imágenes no parpadeen.
//  2. Conservar el `ScrollController` entre lista y cuadrícula: sin él,
//     alternar el modo reconstruye el árbol de scroll y el usuario vuelve
//     al principio.
//  3. Llevar la SELECCIÓN. Es estado de la pantalla y no del controller a
//     propósito: la selección es de "estoy mirando estos", se pierde al
//     salir de la pantalla y no tiene por qué sobrevivir a un refresco del
//     índice. Lo que sí es del controller son las acciones sobre lo
//     seleccionado, que ya existen en lote (`toggleFavoritesBatch`,
//     `moveToTrashBatch`).
//
// # Gestos
//
// Cada fila va en un `Dismissible` con dos acciones horizontales: derecha
// = favorito, izquierda = papelera. Son las dos que se repiten cientos de
// veces al revisar archivos; el resto (comprimir, extraer, mover) siguen
// en menú, donde no compiten por el mismo gesto. La de favorito NO saca
// la fila de la lista: devuelve `false` y la ficha vuelve, porque un
// archivo marcado como favorito sigue estando donde estaba.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:NexoraCore/NexoraCore.dart';
import 'package:NexoraUi/NexoraUi.dart';

import '../../controllers/files_controller.dart';
import '../../models/directory_entry.dart';
import '../../models/file_model.dart';
import '../../utils/confirm_destructive.dart';
import '../files/file_preview_screen.dart';
import '../../widgets/breadcrumbs_bar.dart';
import '../../widgets/filter_bar.dart';
import '../../widgets/folder_view_settings_popup.dart';
import '../../widgets/listing_selection.dart';

class FileListingScreen extends StatefulWidget {
  final FilesController controller;

  /// Título dinámico: la carpeta, la categoría o el dispositivo.
  final String title;
  final IconData icon;

  /// Archivos del listado, ya filtrados por quien la abre.
  final List<FileModel> files;

  /// Agrupa por subcarpeta (lugar de guardado). Solo tiene efecto en
  /// cuadrícula y sin directorio abierto: en lista la card ya muestra la
  /// carpeta, y dentro de un directorio todos comparten la misma.
  final bool groupByFolder;

  const FileListingScreen({
    super.key,
    required this.controller,
    required this.title,
    required this.icon,
    required this.files,
    this.groupByFolder = true,
  });

  @override
  State<FileListingScreen> createState() => _FileListingScreenState();
}

class _FileListingScreenState extends State<FileListingScreen> {
  /// Tarea de miniaturas en curso, para no lanzar una por cada rebuild.
  Future<void>? _thumbTask;

  /// Providers ya creados por miniatura: identidad estable entre rebuilds.
  final Map<String, ImageProvider> _thumbProviders = {};

  /// Scroll compartido por los dos modos para no perder la posición.
  final ScrollController _scroll = ScrollController();

  /// Ids marcados. Vacío = no hay modo selección.
  ///
  /// Vive en la pantalla y no en el controller porque es "qué estoy
  /// mirando": se pierde al salir de la pantalla y no tiene por qué
  /// sobrevivir a un refresco del índice. Lo que sí es del controller son
  /// las acciones sobre lo seleccionado, que ya existen en lote.
  final Set<String> _selected = <String>{};

  bool get _inSelection => _selected.isNotEmpty;

  /// Los archivos marcados, en el orden en que se ven.
  List<FileModel> _selectedFiles(List<FileModel> sorted) =>
      [for (final f in sorted) if (_selected.contains(f.id)) f];

  /// ¿El archivo sigue en el listado? Decide si un swipe se anima fuera
  /// o vuelve: decir que se fue algo que sigue ahí deja un `Dismissible`
  /// huérfano, que es como Flutter avisa de un hijo descartado sin motivo.
  bool _isPresent(String id) => widget.controller.isBrowsingDirectory
      ? widget.controller.browsableFiles.any((f) => f.id == id)
      : widget.files.any((f) => f.id == id);

  void _toggleSelected(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  /// Pulsación larga: entra en modo selección con SOLO ese archivo, que es
  /// lo que espera cualquiera que venga de usar un gestor de archivos.
  void _startSelection(String id) => setState(() => _selected.add(id));

  void _clearSelection() => setState(_selected.clear);

  /// "Seleccionar todo" y su inverso en el mismo botón: con 300 archivos
  /// marcar uno a uno es absurdo, y con 3 ya marcados "todo" es lo natural.
  void _toggleSelectAll(List<FileModel> sorted) {
    setState(() {
      if (_selected.length == sorted.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(sorted.map((f) => f.id));
      }
    });
  }

  /// Tap normal: en modo selección marca o desmarca; si no, abre.
  void _onFileTap(FileModel file, List<FileModel> files) {
    if (_inSelection) {
      _toggleSelected(file.id);
      return;
    }
    openFilePreview(
      context,
      controller: widget.controller,
      file: file,
      files: files,
    );
  }

  void _onFileLongPress(FileModel file) {
    if (_inSelection) {
      _toggleSelected(file.id);
    } else {
      _startSelection(file.id);
    }
  }

  /// Acción del swipe: `true` solo si la fila debe irse de verdad.
  ///
  /// El favorito devuelve siempre `false` (el archivo sigue ahí y la ficha
  /// vuelve); la papelera, solo si el archivo desapareció.
  Future<bool> _onSwipe(FileModel file, DismissDirection direction) async {
    final controller = widget.controller;
    if (direction == DismissDirection.startToEnd) {
      await controller.toggleFavorite(file.id);
      return false;
    }
    final ok = await confirmDestructive(
      context,
      controller: controller,
      title: 'Mover a la papelera',
      message: '“${file.title}” se moverá a la papelera.',
      confirmLabel: 'Mover',
    );
    if (!ok) return false;
    await controller.moveToTrash(file.id);
    return !_isPresent(file.id);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Acciones masivas de la barra de selección.
  ///
  /// Se vacían los lotes hacia el controller, que ya sabe mover a papelera
  /// y marcar favoritos de uno en uno sin pedir nada a la UI. Después la
  /// selección se limpia: si no, el contador seguiría marcando archivos
  /// que ya no están en la lista.
  Future<void> _toggleFavoritesOfSelection(List<FileModel> sorted) async {
    final ids = _selectedFiles(sorted).map((f) => f.id).toList();
    await widget.controller.toggleFavoritesBatch(ids);
    if (mounted) _clearSelection();
  }

  Future<void> _trashSelection(List<FileModel> sorted) async {
    final files = _selectedFiles(sorted);
    final controller = widget.controller;
    final ok = await confirmDestructive(
      context,
      controller: controller,
      title: 'Mover a la papelera',
      message: files.length == 1
          ? '“${files.first.title}” se moverá a la papelera.'
          : '${files.length} archivos se moverán a la papelera.',
      confirmLabel: 'Mover',
    );
    if (!ok) return;
    await controller.moveToTrashBatch(files.map((f) => f.id));
    if (mounted) _clearSelection();
  }

  /// Se piden las miniaturas UNA vez, no en cada `build`.
  void _ensureThumbnails() {
    // Las de lo que se va a pintar, no las de todo el almacenamiento:
    // pedir miniaturas de 30.000 archivos para ver 200 abriría un isolate
    // por archivo que no se va a ver.
    final rutas = [
      for (final f in widget.controller.isBrowsingDirectory
          ? widget.controller.browsableFiles
          : widget.files)
        f.path,
    ];
    if (rutas.isEmpty) return;
    _thumbTask ??= widget.controller
        .ensureThumbnails(rutas)
        .then((_) => _thumbTask = null);
  }

  /// Provider memoizado para la miniatura de [file], o `null`.
  ImageProvider? _thumbOf(FileModel file) {
    final cached = widget.controller.thumbnailFor(file.path);
    if (cached != null) {
      return _thumbProviders.putIfAbsent(
        'gen:$cached',
        () => FileImage(File(cached)),
      );
    }
    final isMedia =
        file.isVideo || kindForPath(file.path) == FileKind.image;
    if (!isMedia) return null;
    return _thumbProviders.putIfAbsent(
      'orig:${file.path}',
      () => FileImage(File(file.path)),
    );
  }

  @override
  Widget build(BuildContext context) {
    _ensureThumbnails();
    return Scaffold(
      appBar: NSecondaryTopBar(
        title: widget.title,
        actions: [
          FolderViewSettingsPopup(controller: widget.controller),
          _GeneralMenu(controller: widget.controller),
        ],
      ),
      bottomNavigationBar: _inSelection
          ? ListingSelectionBar(
              selected: _selectedFiles(_sorted(widget.controller)),
              total: _sorted(widget.controller).length,
              onClear: _clearSelection,
              onSelectAll: () => _toggleSelectAll(_sorted(widget.controller)),
              onToggleFavorites: () =>
                  _toggleFavoritesOfSelection(_sorted(widget.controller)),
              onTrash: () => _trashSelection(_sorted(widget.controller)),
            )
          : null,
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          // Con un directorio abierto, "vacío" significa que no hay ni
          // carpetas ni archivos. Una carpeta con subcarpetas pero sin
          // archivos NO está vacía, y sin esta comprobación la pantalla
          // mostraría un "Nada por aquí" encima del árbol de carpetas.
          final vacio = widget.controller.isBrowsingDirectory
              ? widget.controller.browsableFiles.isEmpty &&
                  widget.controller.currentFolders.isEmpty
              : widget.files.isEmpty;
          if (vacio) {
            return NEmptyState(
              icon: widget.icon,
              // El texto tiene que decir DÓNDE está vacía. Con un
              // directorio abierto, "No hay archivos en Documentos" sería
              // falso: lo vacío es la subcarpeta.
              title: 'Nada por aquí',
              subtitle: widget.controller.currentPath == null
                  ? 'No hay archivos en ${widget.title}.'
                  : 'Esta carpeta está vacía.',
            );
          }
          final ruta = widget.controller.currentPath;
          final content = widget.controller.categoryLayout ==
                  FileViewMode.list
              ? _buildList()
              : _buildGrid();
          // El breadcrumb vive en el cuerpo y no en la topbar: la secundaria
          // del kit no admite segunda fila, y reservar su alto en un
          // `PreferredSize` obligaría a adivinarlo. Aquí solo aparece con
          // un directorio abierto; en la vista global no hay ruta desde la
          // que saltar.
          final cuerpo = Column(
            children: [
              FilterBar(controller: widget.controller),
              if (ruta != null) BreadcrumbsBar(
                path: ruta,
                // El salto a un ancestro entra en ese directorio: el
                // breadcrumb no sabe de permisos ni de escaneos.
                onDirectorySelected: widget.controller.navigateTo,
                // Sin este mapa la barra mostraría "storage › emulated ›
                // 0", que no le dice nada a nadie.
                rootLabels: kAndroidRootLabels,
              ),
              Expanded(child: content),
            ],
          );
          // Los filtros van SIEMPRE, también en la vista global: son el
          // mismo trabajo de "de 30.000 a 12" y es donde se llega desde
          // cualquier categoría.
          return cuerpo;
        },
      ),
    );
  }

  /// Los archivos que se pintan, ya ordenados.
  ///
  /// Con un directorio abierto son los de ESE directorio, no los de la
  /// categoría: es lo que hace que el breadcrumb tenga efecto.
  List<FileModel> _sorted(FilesController controller) {
    final base = controller.isBrowsingDirectory
        ? controller.browsableFiles
        : widget.files;
    return controller.sortListing(base);
  }

  Widget _buildList() {
    final sorted = _sorted(widget.controller);
    final carpetas = widget.controller.currentFolders;

    return ListView.builder(
      // La misma clave de `PageStorage` que la cuadrícula: la posición vive
      // en el `ScrollPosition`, que se destruye al cambiar de vista, y la
      // clave es lo que empareja la salida con la entrada.
      key: const PageStorageKey(kListingPageStorageKey),
      controller: _scroll,
      padding: const EdgeInsets.only(bottom: NSpacing.spaceXl),
      itemCount: carpetas.length + 1,
      itemBuilder: (context, index) {
        // Las carpetas van PRIMERO y son un bloque contiguo: mezclarlas con
        // los archivos haría que una carpeta apareciera entre dos archivos.
        if (index < carpetas.length) {
          final carpeta = carpetas[index];
          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: NSpacing.spaceMd,
            ),
            child: NFolderTile(
              folderName: carpeta.name,
              // Sin conteo: `listDirectory` no lo da, y poner 0 sería mentir.
              onTap: () => widget.controller.navigateTo(carpeta.path),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NSpacing.spaceMd,
          ),
          child: NGroupedCardContainer(
            children: [
              for (final file in sorted)
                SwipeableFileRow(
                  file: file,
                  onSwipe: _onSwipe,
                  child: _ListingCard(
                    file: file,
                    files: sorted,
                    controller: widget.controller,
                    thumbnail: _thumbOf(file),
                    selected: _inSelection ? _selected.contains(file.id) : null,
                    onTap: () => _onFileTap(file, sorted),
                    onLongPress: () => _onFileLongPress(file),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGrid() {
    final sorted = _sorted(widget.controller);
    final carpetas = widget.controller.currentFolders;
    // Dentro de un directorio, agrupar por carpeta es inútil: todos los
    // archivos tienen la misma, la que se está viendo, así que saldría un
    // único grupo con todo dentro.
    if (!widget.groupByFolder || widget.controller.isBrowsingDirectory) {
      return _sectionGrid(
        files: sorted,
        folders: carpetas,
        withPaddingTop: true,
      );
    }

    // Agrupado por "lugar de guardado": en un gestor de archivos saber
    // dónde está cada cosa es tan útil como saber qué es.
    final byFolder = <String, List<FileModel>>{};
    for (final file in sorted) {
      byFolder.putIfAbsent(file.folderName, () => []).add(file);
    }
    final folders = byFolder.keys.toList()..sort();

    return ListView(
      key: const PageStorageKey(kListingPageStorageKey),
      controller: _scroll,
      padding: const EdgeInsets.only(bottom: NSpacing.spaceXl),
      children: [
        for (var s = 0; s < folders.length; s++) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(
              NSpacing.spaceMd,
              s == 0 ? NSpacing.spaceMd : NSpacing.spaceSm,
              NSpacing.spaceMd,
              NSpacing.space2xs,
            ),
            child: NSectionLabel(
              title: folders[s],
              color: context.nMutedTextColor,
            ),
          ),
          _sectionGrid(
            files: byFolder[folders[s]]!,
            // Las carpetas del directorio, solo en la primera sección:
            // repetirlas en cada grupo las duplicaría en pantalla.
            folders: s == 0 ? carpetas : const [],
          ),
        ],
      ],
    );
  }

  /// Una rejilla de [files] con sus [folders] delante.
  Widget _sectionGrid({
    required List<FileModel> files,
    required List<DirectoryEntry> folders,
    bool withPaddingTop = false,
  }) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        NSpacing.spaceMd,
        withPaddingTop ? NSpacing.spaceMd : NSpacing.space2xs,
        NSpacing.spaceMd,
        NSpacing.space2xs,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: NSpacing.spaceSm,
        mainAxisSpacing: NSpacing.spaceSm,
        // Visual cuadrado + dos líneas de texto.
        childAspectRatio: 0.72,
      ),
      itemCount: folders.length + files.length,
      itemBuilder: (context, index) {
        if (index < folders.length) {
          final carpeta = folders[index];
          return NFolderGridTile(
            folderName: carpeta.name,
            onTap: () => widget.controller.navigateTo(carpeta.path),
          );
        }
        final file = files[index - folders.length];
        return SwipeableFileRow(
          file: file,
          onSwipe: _onSwipe,
          child: NGridFileCard(
            icon: iconForPath(file.path),
            thumbnail: _thumbOf(file),
            title: file.displayNameFor(widget.controller.showFileExtensions),
            subtitle: file.formattedSize,
            selected: _inSelection ? _selected.contains(file.id) : null,
            onTap: () => _onFileTap(file, files),
            onLongPress: () => _onFileLongPress(file),
          ),
        );
      },
    );
  }
}

/// Clave de `PageStorage` que comparten lista y cuadrícula para conservar
/// la posición al alternar.
const String kListingPageStorageKey = 'nfiles_listing_scroll';

/// Raíces de Android con su nombre legible.
///
/// Vive aquí y no en el widget porque es un dato de la plataforma, y el
/// widget del breadcrumb no debe saber de Android.
const Map<String, String> kAndroidRootLabels = {
  '/storage/emulated/0': 'Almacenamiento interno',
};

/// Card de un archivo del listado: resuelve icono, miniatura, título y
/// subtítulo del modelo, y delega el gesto a quien la monta.
///
/// El tap y la pulsación larga entran por parámetro y no se hacen aquí:
/// en modo selección el mismo gesto tiene que MARCAR en vez de abrir, y
/// esa decisión es de la pantalla, no de la ficha.
class _ListingCard extends StatelessWidget {
  final FileModel file;
  final List<FileModel> files;
  final FilesController controller;
  final ImageProvider? thumbnail;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// `null` = fuera del modo selección. `true/false` = marcado o no, que
  /// es lo que tiñe la ficha y lo que anuncia el lector de pantalla.
  final bool? selected;

  const _ListingCard({
    required this.file,
    required this.files,
    required this.controller,
    this.thumbnail,
    this.onTap,
    this.onLongPress,
    this.selected,
  });

  @override
  Widget build(BuildContext context) {
    return NRecentFileCard(
      icon: iconForPath(file.path),
      thumbnail: thumbnail,
      title: file.displayNameFor(controller.showFileExtensions),
      subtitle: '${file.formattedSize} • ${file.folderName}',
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

/// Menú general del listado: acciones que no son vista ni orden.
class _GeneralMenu extends StatelessWidget {
  final FilesController controller;

  const _GeneralMenu({required this.controller});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded, size: 22),
      tooltip: 'Más opciones',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      onSelected: (_) => controller.refresh(),
      itemBuilder: (_) => const [
        PopupMenuItem<String>(
          value: 'refresh',
          child: Row(
            children: [
              Icon(Icons.refresh_rounded, size: 20),
              SizedBox(width: 12),
              Expanded(
                child: Text('Actualizar', style: TextStyle(fontSize: 14)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
