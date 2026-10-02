// lib/widgets/breadcrumbs_bar.dart
//
// Ruta navegable del explorador, en una sola línea con scroll horizontal.
//
// # Qué resuelve
//
// Un gestor de archivos con vista de cuadrícula.groupby te deja a un solo
// nivel de abajo: ves los archivos de una categoría, no de una carpeta. Para
// saber dónde estás tienes dos opciones, y las dos son malas:.title fijo
// ("Documentos") que no dice nada de la carpeta real, o un botón "subir" que
// te sube de uno en uno y obliga a seis toques para volver a la raíz.
//
// El breadcrumb da las dos cosas: la ruta completa visible en una línea, y un
// salto directo a cualquier ancestro con un solo toque.
//
// # Por qué el parser es una función aparte del widget
//
// La lógica interesante —qué segmentos salen de una ruta, cómo se acumulan
// las rutas absolutas, qué etiqueta lleva la raíz— es aritmética de cadenas,
// y probarla a través de un widget sale cara: hace falta montar un `MaterialApp`,
// un ancho concreto y varios `pump`. Separada, se prueba llamando con una
// línea. [parseBreadcrumbs] es la función; el widget solo la pinta.
//
// # El primer segmento y su etiqueta
//
// El primer segmento es la raíz, y mostrarla tal cual es inútil: nadie quiere
// leer `/storage/emulated/0`. Por eso [BreadcrumbsBar.rootLabels] mapea
// prefijos a nombres legibles y lo que se ve es "Almacenamiento interno".
//
// Lo importante es que **la etiqueta no cambia la ruta**: el `path` del primer
// segmento sigue siendo `/storage/emulated/0`. Si se sustituyera uno por otro,
// el callback devolvería un nombre y la app no podría navegar a él.
import 'package:flutter/material.dart';
import 'package:NexoraUi/NexoraUi.dart';

/// Un segmento del breadcrumb.
class BreadcrumbCrumb {
  /// Lo que se ve. Puede ser un nombre legible ("Almacenamiento interno")
  /// o el nombre real de la carpeta ("Download").
  final String label;

  /// Ruta absoluta a la que salta este segmento.
  ///
  /// Siempre acumulada desde la raíz, nunca un trozo suelto: es lo que se
  /// devuelve en [BreadcrumbsBar.onDirectorySelected] y lo que la app tiene
  /// que poder abrir sin recombinar nada.
  final String path;

  /// `true` solo en el último. El actual se destaca y no se pulsa: pulsarlo
  /// no iría a ninguna parte, y un control que no hace nada es un fallo.
  final bool isCurrent;

  const BreadcrumbCrumb({
    required this.label,
    required this.path,
    required this.isCurrent,
  });

  @override
  bool operator ==(Object other) =>
      other is BreadcrumbCrumb &&
      other.label == label &&
      other.path == path &&
      other.isCurrent == isCurrent;

  @override
  int get hashCode => Object.hash(label, path, isCurrent);

  @override
  String toString() => 'BreadcrumbCrumb($label -> $path)';
}

/// Etiqueta que se usa cuando ningún prefijo del mapa encaja.
const String kBreadcrumbFallbackRoot = 'Raíz';

/// Parte una ruta absoluta en sus segmentos acumulando la ruta de cada uno.
///
/// Devuelve `[]` para entrada vacía o nula, y un único segmento para la raíz
/// `/`, que es el caso degenerado que tiene que verse en algún sitio.
///
/// # Por qué se ignoran `.` y `..`
///
/// `/a/./b` y `/a/b` son la misma carpeta, y `/a/b/..` es `/a`. Un breadcrumb
/// que los mostrara como segmentos propios enseñaría una ruta que no existe.
/// Se resuelven durante la construcción, no al mostrar.
///
/// Se resuelven **de verdad**, no solo se descartan: `..` retrocede de
/// verdad, para que `path` sea la ruta real a la que se puede saltar. Un
/// `..` que solo se ignoraría dejaría un segmento cuyo `path` apunta a una
/// carpeta que no es la que se ve.
List<BreadcrumbCrumb> parseBreadcrumbs(
  String path, {
  Map<String, String> rootLabels = const {},
  String fallbackRootLabel = kBreadcrumbFallbackRoot,
}) {
  if (path.isEmpty) return const [];

  // Pila con el camino real de cada carpeta. `..` saca el último.
  //
  // La ruta se RECONSTRUYE al final en vez de mantenerse acumulada en una
  // variable: mantenerla obliga a parchearla a mano en cada rama (`..` deja
  // una barra colgando y sale `/a//c`), y un `join` sobre la pila no puede
  // equivocarse porque no hay estado que sincronizar.
  final pila = <String>[];
  for (final segment in path.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (pila.isNotEmpty) pila.removeLast();
      continue;
    }
    pila.add(segment);
  }

  if (pila.isEmpty) {
    // La entrada era "/", "/.", "/.." o solo "..": solo hay raíz.
    return [
      BreadcrumbCrumb(
        label: _labelFor('/', rootLabels) ?? fallbackRootLabel,
        path: '/',
        isCurrent: true,
      ),
    ];
  }

  // Ruta acumulada de cada segmento, construida desde la pila ya resuelta.
  final paths = <String>[];
  var acc = '';
  for (final segment in pila) {
    acc = '$acc/$segment';
    paths.add(acc);
  }
  final rutaCompleta = paths.last;

  // El prefijo etiquetado se busca contra la ruta COMPLETA, no contra el
  // primer segmento. La diferencia es el motivo de que esto exista: en
  // Android, `/storage/emulated/0` son TRES segmentos y ninguno coincide con
  // el prefijo. Buscarlo contra `paths.first` (que es `/storage`) no
  // encontraría nunca nada, y "Almacenamiento interno" no aparecería jamás.
  final encontrado = _matchPrefix(rutaCompleta, rootLabels);
  final prefijo = encontrado?.prefijo;
  final etiqueta = encontrado?.etiqueta;

  // Cuántos segmentos cubre el prefijo etiquetado.
  //
  // Se cuentan POR PARTE, no comprobando si `paths[i]` empieza por el prefijo:
  // `/storage` no empieza por `/storage/emulated/0`, pero sí es la primera
  // parte de ese prefijo. Con la comparación al revés, `ocultos` se quedaba
  // en cero y la barra mostraba "Almacenamiento interno › storage › emulated".
  var ocultos = 0;
  if (prefijo != null) {
    final partes = prefijo.split('/').where((s) => s.isNotEmpty).toList();
    for (var i = 0; i < partes.length; i++) {
      if (i >= pila.length || pila[i] != partes[i]) break;
      ocultos++;
    }
  }

  final crumbs = <BreadcrumbCrumb>[];
  if (prefijo != null && etiqueta != null) {
    // El primer chip es la etiqueta, pero su `path` es el PREFIJO: es lo que
    // se puede abrir. Si fuera el primer segmento real, saltar a
    // "Almacenamiento interno" abriría `/storage`, que no es el
    // almacenamiento interno.
    crumbs.add(BreadcrumbCrumb(
      label: etiqueta,
      path: prefijo,
      isCurrent: ocultos == paths.length,
    ));
  }
  for (var i = ocultos; i < paths.length; i++) {
    crumbs.add(BreadcrumbCrumb(
      label: pila[i],
      path: paths[i],
      isCurrent: i == paths.length - 1,
    ));
  }

  // Sin prefijo, el primer chip es el primer segmento con su nombre real.
  // Ponerle "Raíz" a `/storage` sería mentir: `/storage` no es la raíz, es
  // una carpeta más. La etiqueta de reserva solo se usa para la raíz de
  // verdad, que es donde no hay ningún nombre que enseñar.
  if (crumbs.isEmpty) {
    crumbs.add(
      BreadcrumbCrumb(label: pila.first, path: paths.first, isCurrent: false),
    );
  }

  // El último es siempre el actual, se haya etiquetado la raíz o no.
  if (crumbs.isNotEmpty) {
    crumbs[crumbs.length - 1] = BreadcrumbCrumb(
      label: crumbs.last.label,
      path: crumbs.last.path,
      isCurrent: true,
    );
  }
  return crumbs;
}

/// Una entrada del mapa que describe [ruta].
typedef _RootMatch = ({String prefijo, String etiqueta});

/// Prefijo del mapa que es ancestro de [ruta], el más largo que encaje.
///
/// Devuelve `null` si ninguno encaja. Devuelve la etiqueta **junto** al
/// prefijo, y no solo el prefijo, porque la clave del mapa puede llevar barra
/// final: al buscar la etiqueta con el prefijo ya normalizado, la entrada
/// `'/storage/emulated/0/'` no se encuentra a sí misma y su etiqueta se
/// pierde en silencio.
///
/// "El más largo" y no "el primero del mapa" porque los prefijos se solapan:
/// `/storage/emulated/0` y `/storage/emulated/0/Android/data` pueden estar
/// los dos, y el específico es el que describe bien esa carpeta.
///
/// La clave `"/"` (o cualquier cosa que solo sean barras) es un caso
/// especial: nombra la raíz y encaja con TODO. Se trata aparte porque al
/// normalizar queda vacía, y una clave vacía descartada haría que esa
/// entrada no sirviera nunca.
_RootMatch? _matchPrefix(String ruta, Map<String, String> rootLabels) {
  _RootMatch? mejor;
  for (final entry in rootLabels.entries) {
    final prefijo = entry.key.replaceAll(RegExp(r'/+$'), '');
    if (prefijo.isEmpty) {
      // Solo era la raíz: encaja siempre, pero es la opción menos específica,
      // así que solo entra si no hay ninguna otra.
      mejor ??= (prefijo: '/', etiqueta: entry.value);
      continue;
    }
    final coincide = ruta == prefijo || ruta.startsWith('$prefijo/');
    if (!coincide) continue;
    // `/` no compite por longitud: le faltan caracteres a cualquier prefijo
    // real, así que siempre perdería y hay que descartarlo aparte.
    if (mejor == null ||
        mejor.prefijo == '/' ||
        prefijo.length > mejor.prefijo.length) {
      mejor = (prefijo: prefijo, etiqueta: entry.value);
    }
  }
  return mejor;
}

/// Etiqueta exacta de una ruta, si el mapa la nombra de forma literal.
///
/// Se aceptan las dos formas de escribir la clave, con y sin barra final, que
/// es el error tipográfico más fácil de cometer al escribir el mapa.
String? _labelFor(String ruta, Map<String, String> rootLabels) {
  final directa = rootLabels[ruta];
  if (directa != null) return directa;
  if (ruta == '/') return null;
  return rootLabels['$ruta/'];
}

/// Barra de ruta navegable.
class BreadcrumbsBar extends StatefulWidget {
  const BreadcrumbsBar({
    super.key,
    required this.path,
    required this.onDirectorySelected,
    this.rootLabels = const {},
    this.fallbackRootLabel = kBreadcrumbFallbackRoot,
    this.height = 40.0,
    this.autoScrollToEnd = true,
  });

  /// Ruta absoluta de la carpeta actual.
  final String path;

  /// Se llama con la ruta absoluta del segmento pulsado.
  ///
  /// Nunca se llama con el segmento actual: ese no es pulsable. Si se
  /// llamara, quien lo recibe abriría la carpeta en la que ya está, y eso
  /// en un gestor de archivos significa recargar sin motivo.
  final void Function(String absolutePath) onDirectorySelected;

  /// Prefijos de raíz y su nombre legible.
  ///
  /// El prefijo más largo que encaja gana, para que un mapa con
  /// `/storage/emulated/0` y `/storage/emulated/0/Android/data` distinga el
  /// almacenamiento interno de una partición concreta de la aplicación.
  final Map<String, String> rootLabels;

  /// Lo que se muestra si ningún prefijo encaja.
  final String fallbackRootLabel;

  final double height;

  /// Si el scroll se va solo al extremo derecho al cambiar de ruta.
  ///
  /// En `true` la carpeta actual queda visible sin que el usuario tenga que
  /// arrastrar. Se puede desactivar para una vista donde el scroll lo
  ///	goberna otra cosa, o para los tests que miden el desplazamiento.
  final bool autoScrollToEnd;

  @override
  State<BreadcrumbsBar> createState() => _BreadcrumbsBarState();
}

class _BreadcrumbsBarState extends State<BreadcrumbsBar> {
  /// El scroll se controla a mano, no con un `PrimaryScrollController`.
  ///
  /// Robar el controlador primario rompe cualquier otro `Scrollable` del
  /// subárbol, y además haría que el estado del scroll sobreviviera a la
  /// pantalla, que es justo lo contrario de lo que quiere un breadcrumb: la
  /// posición depende de la ruta, no de un historial de scroll.
  final ScrollController _scroll = ScrollController();

  /// Ruta para la que se ha hecho el auto-scroll.
  ///
  /// Se guarda para no repetir el `animateTo` en cada rebuild. Sin esto, un
  /// `notifyListeners` del controlador que se dispara cada segundo (por el
  /// watcher de archivos) reiniciaría la animación y la barra parpadearía.
  String? _scrolledFor;

  @override
  void didUpdateWidget(BreadcrumbsBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      // La ruta anterior ya no describe el scroll: si el usuario lo había
      // dejado a la izquierda para leer el ancestro viejo, al descender esa
      // posición no significa nada.
      _scrolledFor = null;
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Lleva el scroll al extremo derecho tras el primer frame.
  ///
  /// Se hace con `addPostFrameCallback` porque en el `build` el ancho del
  /// viewport todavía no está calculado: el `maxScrollExtent` es 0 hasta que
  /// el `Scrollable` se ajusta, y saltarse ese paso deja la barra al
  /// principio, que es el fallo clásico de esto.
  void _autoScrollIfNeeded(List<BreadcrumbCrumb> crumbs) {
    if (!widget.autoScrollToEnd) return;
    if (crumbs.isEmpty || _scrolledFor == widget.path) return;
    _scrolledFor = widget.path;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (max <= 0) return;
      _scroll.animateTo(
        max,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final crumbs = parseBreadcrumbs(
      widget.path,
      rootLabels: widget.rootLabels,
      fallbackRootLabel: widget.fallbackRootLabel,
    );

    if (crumbs.isEmpty) {
      // Sin ruta no hay nada que dibujar. Un SizedBox vacío en vez de un
      // separador: el hueco de la barra lo pone quien la usa.
      return SizedBox(height: widget.height);
    }

    _autoScrollIfNeeded(crumbs);

    // Por qué no hay un `NotificationListener` para "no robar el gesto
    // vertical": esa reparto no se hace con notificaciones. Cuando un
    // scroll horizontal y otro vertical se tocan, ambos entran en el
    // `GestureArena` y gana el del eje con más recorrido, que es
    // exactamente el comportamiento que se quiere aquí. Un filtro manual
    // por eje, ademas, no tendria eje con el que comparar.
    //
    // Lo que sí hay que evitar es el `NeverScrollableScrollPhysics`, que
    // desactiva el arrastre y con el la sensacion de "arrastrar y no pasa
    // nada". `AlwaysScrollableScrollPhysics` mantiene el arrastre vivo
    // incluso sin contenido que desplazar.
    return SizedBox(
      height: widget.height,
      child: Scrollbar(
        controller: _scroll,
        thumbVisibility: false,
        child: SingleChildScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: NSpacing.spaceMd,
            ),
            child: Row(
              children: [
                for (var i = 0; i < crumbs.length; i++) ...[
                  if (i > 0) const _CrumbSeparator(),
                  _CrumbChip(
                    crumb: crumbs[i],
                    onTap: widget.onDirectorySelected,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Separador entre segmentos: el chevron del kit, atenuado.
///
/// Un `chevron_right` de `Icons` y no el `NImageBadge` del visor, porque
/// este es un separador de ruta y no un indicador de carrusel.
class _CrumbSeparator extends StatelessWidget {
  const _CrumbSeparator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: NSpacing.space2xs),
      child: Icon(
        Icons.chevron_right,
        size: 18,
        color: context.nMutedTextColor.withValues(alpha: 0.55),
      ),
    );
  }
}

/// Un segmento pulsable.
class _CrumbChip extends StatelessWidget {
  final BreadcrumbCrumb crumb;

  final void Function(String absolutePath) onTap;

  const _CrumbChip({required this.crumb, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final muted = context.nMutedTextColor;
    final primary = context.nPrimaryBrandColor;

    // El actual se destaca con el color de marca y negrita; los ancestros
    // con el color atenuado pero PLUMEA. Atenuado no significa deshabilitado:
    // es un destino válido, solo que no es donde estás.
    final color = crumb.isCurrent ? primary : muted;
    final weight = crumb.isCurrent
        ? NTypography.weightBold
        : NTypography.weightMedium;

    final label = Text(
      crumb.label,
      maxLines: 1,
      // Sin esto, un nombre de carpeta largo empuja el resto de la fila
      // fuera de la pantalla y el ancestro más cercano —el que más se usa—
      // se queda invisible justo cuando hace falta.
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: NTypography.fontFamilyBase,
        fontSize: NTypography.sizeSm,
        fontWeight: weight,
        color: color,
      ),
    );

    // Sin chip, el segmento actual no se puede tocar ni a palos.
    //
    // En `Semantics` se marca como `selected` y `header`, que es lo más
    // parecido que tiene Flutter al `aria-current="page"` de ARIA. Flutter
    // no tiene un flag "current": ponerlo como `button` haría que el lector
    // de pantalla anuncie un botón que al pulsarse no hace nada.
    if (crumb.isCurrent) {
      return Semantics(
        selected: true,
        header: true,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 220),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: NSpacing.space2xs),
          child: label,
        ),
      );
    }

    return Semantics(
      button: true,
      label: 'Ir a ${crumb.label}',
      child: Tooltip(
        // El nombre completo en el tooltip: aquí va el elipsis, y quien
        // tenga el ratón puede ver la ruta entera sin salir de la barra.
        message: crumb.path,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onTap(crumb.path),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 220),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(
                horizontal: NSpacing.space2xs,
                vertical: NSpacing.space3xs,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: context.nHoverColor,
              ),
              child: label,
            ),
          ),
        ),
      ),
    );
  }
}
