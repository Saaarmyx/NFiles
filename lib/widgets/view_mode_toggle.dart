// lib/widgets/view_mode_toggle.dart
//
// Botón que alterna entre lista y cuadrícula.
//
// # Por qué un toggle y no dos botones
//
// Dos botones abatibles ocupan el doble para decir lo mismo, y el usuario
// tiene que leer los dos iconos para saber en qué modo está. Un solo botón
// que muestra el modo AL QUE SE VA es la convención de Android, de iOS y de
// Windows Explorer, y cabe en el hueco de una acción de la barra.
//
// # Por qué el icono muestra el destino y no el estado
//
// Es contraintuitivo y por eso lleva comentario: un botón con `view_list`
// junto a una lista activa parece "estoy en modo lista" cuando en realidad
// pulsarlo cambia A lista. Mostrar el destino evita la lectura invertida, que
// es el error clásico de estos botones.
//
// # Qué persiste
//
// El modo vive en [FilesController], que ya lo guarda con debounce de 250 ms
// a través de `FilesViewPrefs`. Este widget no toca el almacén: si guardara
// por su cuenta habría dos fuentes de verdad para el mismo ajuste, y la
// segunda en escribir siempre perdería.
import 'package:flutter/material.dart';
import 'package:NexoraUi/NexoraUi.dart';

import '../controllers/files_controller.dart';

/// Alterna la vista entre lista y cuadrícula.
class ViewModeToggle extends StatelessWidget {
  const ViewModeToggle({
    super.key,
    required this.controller,
    this.size = 40,
  });

  final FilesController controller;

  /// Alto y ancho del área táctil.
  ///
  /// 40 px es el mínimo comfortable: por debajo, en un dedo, el fallo de
  /// pulsación se dispara con facilidad.
  final double size;

  @override
  Widget build(BuildContext context) {
    // AnimatedBuilder y no una escucha propia: el controlador ya notifica
    // y este widget no tiene estado que mantener sincronizado. Suscribirse
    // aparte obligaría a acordarse de quitar el listener en `dispose`.
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final esLista = controller.categoryLayout == FileViewMode.list;
        final destino = esLista ? FileViewMode.grid : FileViewMode.list;
        return Semantics(
          button: true,
          toggled: esLista,
          // El nombre dice la ACCIÓN, no el estado: "Cambiar a cuadrícula" es
          // lo que un lector de pantalla debe anunciar, porque es lo que
          // hará el siguiente toque.
          label: esLista ? 'Cambiar a cuadrícula' : 'Cambiar a lista',
          child: Tooltip(
            message: esLista ? 'Cuadrícula' : 'Lista',
            child: InkWell(
              onTap: () => controller.setCategoryLayout(destino),
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: size,
                height: size,
                child: Icon(
                  esLista ? Icons.grid_view : Icons.view_list,
                  size: 22,
                  color: context.nPrimaryTextColor,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
