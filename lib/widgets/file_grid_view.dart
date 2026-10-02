// lib/widgets/file_grid_view.dart
//
// Cuadrícula de archivos que se adapta al ancho disponible.
//
// # Por qué `MaxCrossAxisExtent` y no `FixedCrossAxisCount`
//
// La cuadrícula anterior usaba `crossAxisCount: 3` fijo. Eso da tres columnas
// enormes en un monitor de 1920 px y tres columnas diminutas en un móvil de
// 360 px, con el mismo código. `SliverGridDelegateWithMaxCrossAxisExtent`
// declara el tamaño MÁXIMO de una casilla y deja que el delegate decida
// cuántas caben: en un monitor salen 8 o 10 columnas de 150 px, y en un móvil
// 2, sin tocar una constante.
//
// La diferencia con un conteo calculado a mano es que el delegate recalcula
// solo. Si mañana el ancho de la pantalla cambia (una ventana redimensionada
// en Linux, un plegable que se abre), el conteo se ajusta sin que nadie
// escriba código de más.
//
// # Por qué la casilla tiene su propia altura y no una proporción de la
// imagen
//
// Con `mainAxisExtent` fijo, la altura de la casilla no depende de lo que la
// imagen tenga. Con la proporción de la imagen, una foto panorámica
// aplasta el texto del nombre hasta hacerlo ilegible y una vertical deja un
// hueco enorme. Un alto fijo mantiene la retícula regular, que es lo que hace
// que un grid se lea de un vistazo.
//
// # El scroll vive aquí, no en la pantalla
//
// `FileGridView` es un `CustomScrollView` con un `SliverGrid`, y no un
// `GridView` con `shrinkWrap`. El motivo es la conmutación lista/grid: con
// `shrinkWrap` dentro de un `ListView` externo, cambiar de un modo a otro
// destruye y recrea todo el árbol de scroll, y con él la posición. Aquí el
// controlador de scroll se conserva, así que alternar deja al usuario donde
// estaba, que es lo que se espera de un botón que solo cambia la
// presentación.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:NexoraCore/NexoraCore.dart' hide MediaQuery;
import 'package:NexoraUi/NexoraUi.dart';

import '../models/file_model.dart';
import 'thumb_image.dart';

/// Clave de `PageStorage` que comparten la lista y la cuadrícula.
///
/// Existe porque compartir el `ScrollController` NO basta para conservar la
/// posición entre modos, que era el error que este widget cometía al
/// cambiar: la posición vive en el `ScrollPosition`, y al desmontarse la
/// vista anterior para montar la nueva, ese objeto se destruye y el
/// controller se queda sin posición a la que apuntar. El resultado era un
/// `0.0` silencioso: el usuario volvía arriba del todo al pulsar el botón.
///
/// `PageStorage` es la capa de Flutter que guarda el offset de un scroll
/// cuando desaparece, y la clave es lo que empareja la salida con la
/// entrada. Sin una clave compartida, cada vista guarda la suya y no se
/// emparejan.
const String kFilesPageStorageKey = 'nfiles_files_scroll';

/// Prefijo de la clave de una celda de carpeta.
///
/// Las claves de `ValueKey` tienen que ser distinguibles entre carpetas y
/// archivos, porque las dos listas comparten delegate y el
/// `findChildIndexCallback` decide por la clave. Sin el prefijo, una carpeta
/// con el mismo nombre que un archivo dejaría al índice en una posición
/// equivocada al borrar ese archivo.
const String _kFolderKeyPrefix = 'folder:';

/// Cuadrícula responsive de archivos.
class FileGridView extends StatelessWidget {
  const FileGridView({
    super.key,
    required this.files,
    required this.onOpen,
    this.onLongPress,
    this.scrollController,
    this.selectedIds = const {},
    this.inSelectionMode = false,
    this.maxTileExtent = 150,
    this.thumbnailFor,
    this.padding,
    this.folderCells = const [],
  });

  final List<FileModel> files;

  /// Se llama con el archivo tocado.
  final void Function(FileModel file) onOpen;

  final void Function(FileModel file)? onLongPress;

  /// Se comparte con la vista de lista para que alternar conserve la
  /// posición del scroll.
  ///
  /// Sin esto, cambiar de lista a cuadrícula tira al usuario al principio:
  /// el `CustomScrollView` anterior se destruye y el nuevo empieza en 0.
  final ScrollController? scrollController;

  /// Archivos marcados en modo selección.
  final Set<String> selectedIds;

  /// `true` si la pantalla está en modo selección.
  final bool inSelectionMode;

  /// Ancho máximo de una casilla, en píxeles lógicos.
  ///
  /// 150 da una miniatura legible sin que la rejilla se convierta en una
  /// tira de miniaturas indistinguibles. Por debajo de 110 el nombre ya no
  /// cabe en dos líneas y por encima de 220 la rejilla desperdicia espacio en
  /// pantallas anchas sin ganar nada.
  final double maxTileExtent;

  /// Miniatura ya generada en disco, o `null`.
  ///
  /// La resuelve el controlador: generar un icono abre un isolate y un
  /// `build` no puede esperarlo.
  final String? Function(String path)? thumbnailFor;

  /// Celdas de carpeta que van ANTES que los archivos, en la misma rejilla.
  ///
  /// Ya construidas por quien compone, y no una lista de datos, porque la
  /// carpeta puede traerse controles propios (renombrar, mover) y quien
  /// compone es el que sabe de eso. El kit aporta el `NFolderGridTile` y
  /// decide nada.
  ///
  /// Van en la MISMA rejilla y no en un sliver aparte a propósito: dos slivers
  /// obligan a ver "carpetas" y "archivos" como dos bloques, con la frontera
  /// dibujada por el propio `SliverGrid` en vez de por el sistema de
  /// archivos.
  final List<Widget> folderCells;

  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty && folderCells.isEmpty) return const SizedBox.shrink();
    final total = folderCells.length + files.length;

    return CustomScrollView(
      // La clave es lo que hace que el offset sobreviva al desmontaje. Es
      // compartida con la vista de lista a propósito: ambas guardan en el
      // mismo hueco, así que una hereda de la otra.
      key: const PageStorageKey(kFilesPageStorageKey),
      controller: scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: padding ??
              const EdgeInsets.fromLTRB(
                NSpacing.space2xs,
                NSpacing.space2xs,
                NSpacing.space2xs,
                NSpacing.spaceXl,
              ),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: maxTileExtent,
              // La separación horizontal es menor que la vertical porque la
              // banda de texto de la casilla ya da aire entre filas. Con la
              // misma separación, la rejilla se lee como una tabla y no como
              // fotos.
              crossAxisSpacing: NSpacing.space2xs,
              mainAxisSpacing: NSpacing.space2xs,
              // Alto de la banda de texto: dos líneas de 14 px más el
              // padding. Fijado, no calculado de la proporción de la imagen.
              childAspectRatio: _aspectFor(context, maxTileExtent),
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                // Las carpetas ocupan los primeros indices y los archivos van
                // detras. Es un unico delegate, no dos slivers, para que la
                // frontera entre ambos sea invisible.
                if (index < folderCells.length) return folderCells[index];
                final file = files[index - folderCells.length];
                return FileGridTile(
                  file: file,
                  selected: inSelectionMode && selectedIds.contains(file.id),
                  thumbnailPath: thumbnailFor?.call(file.path),
                  onTap: () => onOpen(file),
                  onLongPress:
                      onLongPress == null ? null : () => onLongPress!(file),
                );
              },
              childCount: total,
              // `findChildIndexCallback` sin esto es lo que hace que al
              // eliminar un archivo en modo seleccion el resto de las
              // casillas se reconstruyan todas y las miniaturas parpadeen.
              //
              // El indice que devuelve es el de la LISTA COMPLETA, con las
              // carpetas delante: por eso el desplazamiento de las carpetas
              // no es opcional. Devolver el indice sin corregir haria que al
              // borrar un archivo se reordenaran todas las casillas.
              findChildIndexCallback: (key) {
                final id = key as ValueKey<String>;
                if (id.value.startsWith(_kFolderKeyPrefix)) {
                  final pos = folderCells.indexWhere(
                    (w) => w.key == ValueKey('$id'),
                  );
                  return pos == -1 ? null : pos;
                }
                final index = files.indexWhere((f) => f.id == id.value);
                if (index == -1) return null;
                return index + folderCells.length;
              },
            ),
          ),
        ),
      ],
    );
  }

  /// Proporción de la casilla, calculada con el ancho REAL de la celda.
  ///
  /// Se replica aquí la cuenta de [SliverGridDelegateWithMaxCrossAxisExtent]
  /// a propósito. El delegate decide cuántas columnas caben, pero de la
  /// proporción solo espera un número, así que hay que saber cuál va a ser
  /// el ancho de la celda antes de que la celda exista.
  ///
  /// Adivinarlo ("la pantalla entre tres") falla justo en los anchos que
  /// importan: en un monitor de 1920 el delegate pone ocho columnas y cada
  /// casilla sale con una altura calculada para una celda de 640 px, con lo
  /// que las miniaturas quedan en franjas.
  static double _aspectFor(BuildContext context, double maxTileExtent) {
    // La banda de texto tiene alto fijo, así que solo se resta aquí.
    const bandaTexto = 36.0;
    final separacion = NSpacing.space2xs;
    final anchoPantalla = MediaQuery.sizeOf(context).width;

    // Cuántas columnas caben, y con cuántas, cuánto mide cada una.
    final util = anchoPantalla - separacion;
    var columnas = (util / (maxTileExtent + separacion)).ceil();
    if (columnas < 1) columnas = 1;
    final anchoCelda = (util / columnas) - separacion;
    if (anchoCelda <= 0) return 1.0;

    // Imagen cuadrada más la banda de texto.
    return anchoCelda / (anchoCelda + bandaTexto);
  }
}

/// Una casilla de la cuadrícula.
class FileGridTile extends StatelessWidget {
  const FileGridTile({
    super.key,
    required this.file,
    required this.selected,
    this.thumbnailPath,
    this.onTap,
    this.onLongPress,
  });

  final FileModel file;
  final bool selected;
  final String? thumbnailPath;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final thumb = thumbnailPath;
    final esImagen = kindForPath(file.path) == FileKind.image;

    return Semantics(
      button: true,
      selected: selected,
      label: file.title,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            // El borde solo aparece en selección. Un borde permanente en
            // cada casilla convierte la rejilla en una tabla y compite con
            // las miniaturas, que es lo que se está mirando.
            border: selected
                ? Border.all(
                    color: context.nPrimaryBrandColor,
                    width: 2,
                  )
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Column(
                children: [
                  Expanded(child: _preview(context, thumb, esImagen)),
                  _Caption(
                    title: file.title,
                    selected: selected,
                  ),
                ],
              ),
              if (selected)
                Positioned.fill(
                  child: IgnorePointer(
                    child: NSelectionOverlay(selected: true),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// La parte de arriba: miniatura, o icono del tipo de archivo.
  Widget _preview(BuildContext context, String? thumb, bool esImagen) {
    if (thumb != null) {
      return ThumbImage(
        path: thumb,
        isThumb: true,
        fit: BoxFit.cover,
        // El motor deja un marcador de texto para PDF y vídeo, que Flutter
        // no puede pintar. Antes de caer en el fallo se comprueba que sea una
        // imagen de verdad, leyendo los primeros bytes: 8 en PNG.
        errorBuilder: (context, _, _) => _icon(context),
      );
    }
    if (esImagen) {
      // Foto sin miniatura todavía: se usa el original. `cacheWidth` limita
      // la decodificación, que en una rejilla de 200 casillas es la
      // diferencia entre 2 MB de memoria y 200 MB.
      return Image.file(
        File(file.path),
        fit: BoxFit.cover,
        cacheWidth: 300,
        errorBuilder: (context, _, _) => _icon(context),
      );
    }
    return _icon(context);
  }

  /// Icono del tipo de archivo, tintado como el resto de la app.
  Widget _icon(BuildContext context) {
    return ColoredBox(
      color: context.nHoverColor,
      child: Center(
        child: Icon(
          iconForPath(file.path),
          size: 34,
          color: context.nMutedTextColor,
        ),
      ),
    );
  }
}

/// Banda de texto bajo la imagen: nombre y marca de selección.
class _Caption extends StatelessWidget {
  const _Caption({required this.title, required this.selected});

  final String title;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      // Alto fijo, no el del contenido: es la banda que hace que todas las
      // casillas tengan la misma altura y la rejilla se lea regular.
      height: 36,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: NSpacing.space2xs),
      color: context.nHoverColor,
      child: Row(
        children: [
          if (selected) ...[
            Icon(
              Icons.check_circle,
              size: 14,
              color: context.nPrimaryBrandColor,
            ),
            const SizedBox(width: NSpacing.space3xs),
          ],
          Expanded(
            child: Text(
              title,
              // Dos líneas como máximo: con una, los nombres largos se cortan
              // sin contexto; con tres, la banda deja de ser fija y la
              // rejilla se descuadra.
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: NTypography.fontFamilyBase,
                fontSize: NTypography.sizeXs,
                color: selected
                    ? context.nPrimaryTextColor
                    : context.nMutedTextColor,
                fontWeight: selected
                    ? NTypography.weightSemibold
                    : NTypography.weightRegular,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
