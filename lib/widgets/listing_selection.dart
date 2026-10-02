// lib/widgets/listing_selection.dart
//
// Las dos piezas de "tocar sin(menu)" del listado: la fila con swipe y la
// barra de selección.
//
// # Por qué `Dismissible` y no un `GestureDetector` con su propia arena
//
// El reparto entre "deslizar la ficha" y "desplazar la lista" es el punto
// difícil, y `Dismissible` ya lo resuelve con el recognizer vertical del
// scroll. Un `GestureDetector` horizontal hecho a mano se lleva los gestos
// diagonales y deja la ficha pegada al scroll en cuanto el dedo se va un
// poco hacia abajo. Además avisa en desarrollo cuando un hijo se descarta
// y sigue en la lista, que es justo el fallo que da una fila fantasma.
//
// # Qué hace cada swipe
//
// - **Derecha → favorito.** No saca la ficha de la lista (el archivo sigue
//   estando donde estaba), así que devuelve `false` y la ficha vuelve.
// - **Izquierda → papelera.** Sale de verdad: devuelve `true` solo si el
//   archivo desapareció. Si el borrado falló, mintiendo con `true` el
//   `Dismissible` se quedaría fuera de la lista.
import 'package:flutter/material.dart';
import 'package:NexoraCore/NexoraCore.dart' show formatBytes;
import 'package:NexoraUi/NexoraUi.dart';

import '../models/file_model.dart';

/// Ficha con las dos acciones horizontales del gestor.
class SwipeableFileRow extends StatelessWidget {
  final FileModel file;
  final Widget child;

  /// Qué pasa al deslizar y si la ficha se va. `true` = fuera de la lista.
  final Future<bool> Function(FileModel, DismissDirection) onSwipe;

  const SwipeableFileRow({
    super.key,
    required this.file,
    required this.child,
    required this.onSwipe,
  });

  @override
  Widget build(BuildContext context) {
    final accent = NOptionTileColors.accentOf(context);
    final danger = Theme.of(context).colorScheme.error;

    Widget fondo(DismissDirection direction, IconData icon, Color color) {
      return Container(
        color: color.withValues(alpha: 0.14),
        alignment: direction == DismissDirection.startToEnd
            ? Alignment.centerLeft
            : Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: NSpacing.spaceLg),
        child: Icon(icon, color: color, size: 22),
      );
    }

    return Dismissible(
      // La clave es la del ARCHIVO y no la del índice: al reordenar, un
      // `Dismissible` con clave de índice se mudaría de fila y arrastraría
      // la animación de otro archivo.
      key: ValueKey<String>('swipe:${file.id}'),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) => onSwipe(file, direction),
      background: fondo(
        DismissDirection.startToEnd,
        file.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
        accent,
      ),
      secondaryBackground: fondo(
        DismissDirection.endToStart,
        Icons.delete_outline_rounded,
        danger,
      ),
      child: child,
    );
  }
}

/// Barra de selección del listado, sobre el [NSelectionBar] del kit.
///
/// Solo traduce archivos a la barra. El contador, el botón de "todo" y las
/// acciones son del kit; lo único que aporta NFiles es el sustantivo
/// ("archivo") y el detalle con el peso de lo marcado, que es el dato que
/// hace entender de un vistazo cuánto se va a mover a la papelera.
class ListingSelectionBar extends StatelessWidget {
  final List<FileModel> selected;
  final int total;
  final VoidCallback onClear;
  final VoidCallback onSelectAll;
  final VoidCallback onToggleFavorites;
  final VoidCallback onTrash;

  /// Acción extra (comprimir, extrae…). `null` = no se ofrece.
  final NActionBarItem? compress;

  const ListingSelectionBar({
    super.key,
    required this.selected,
    required this.total,
    required this.onClear,
    required this.onSelectAll,
    required this.onToggleFavorites,
    required this.onTrash,
    this.compress,
  });

  @override
  Widget build(BuildContext context) {
    final bytes = selected.fold<int>(0, (sum, f) => sum + f.sizeInBytes);
    return NSelectionBar(
      count: selected.length,
      total: total,
      detail: selected.isEmpty ? null : '${formatBytes(bytes)} · de $total',
      singularNoun: 'archivo',
      pluralNoun: 'archivos',
      onClearSelection: onClear,
      onSelectAll: onSelectAll,
      actions: [
        NActionBarItem(
          icon: Icons.star_outline_rounded,
          tooltip: 'Marcar como favorito',
          onTap: onToggleFavorites,
        ),
        ?compress,
        NActionBarItem(
          icon: Icons.delete_outline_rounded,
          tooltip: 'Mover a la papelera',
          destructive: true,
          onTap: onTrash,
        ),
      ],
    );
  }
}
