// lib/widgets/day_header.dart
//
// Cabecera de día de "Recientes".
//
// Título centrado `Hoy | N` y, a la derecha, el total general con un icono
// que retrae/expande la sección. El colapso es por día y se recuerda
// mientras la pantalla viva: al recargar no debe saltar todo abierto ni
// perder lo que el usuario dejó plegado.
import 'package:flutter/material.dart';
import 'package:NexoraUi/NexoraUi.dart';

/// Cabecera de un grupo de día.
class DayHeader extends StatelessWidget {
  /// Etiqueta del día: "Hoy", "Ayer", "Hace 2 días", o una fecha.
  final String label;

  /// Archivos de este día.
  final int count;

  /// Total de archivos de la pantalla (todas las cabeceras sumadas).
  final int total;

  /// Si la sección está plegada.
  final bool collapsed;

  final VoidCallback onToggleCollapsed;

  const DayHeader({
    super.key,
    required this.label,
    required this.count,
    required this.total,
    required this.collapsed,
    required this.onToggleCollapsed,
  });

  @override
  Widget build(BuildContext context) {
    final muted = context.nMutedTextColor;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NSpacing.spaceMd,
        NSpacing.spaceMd,
        NSpacing.space2xs,
        NSpacing.spaceXs,
      ),
      child: Row(
        children: [
          // Lado izquierdo equilibra al título centrado sin inventar
          // contenido: así el "Hoy | N" queda centrado de verdad.
          const SizedBox(width: 40),
          Expanded(
            child: Column(
              children: [
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: NTypography.fontFamilyBase,
                    fontWeight: NTypography.weightBold,
                    fontSize: NTypography.sizeMd,
                    color: context.nPrimaryTextColor,
                  ),
                ),
                Text(
                  '| $count',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: NTypography.fontFamilyBase,
                    fontSize: NTypography.sizeXs,
                    color: muted,
                  ),
                ),
              ],
            ),
          ),
          // Lado derecho: total + control de colapso.
          Semantics(
            button: true,
            label: collapsed ? 'Desplegar $label' : 'Plegar $label',
            child: InkWell(
              onTap: onToggleCollapsed,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: NSpacing.space2xs,
                  vertical: NSpacing.space2xs,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$total',
                      style: TextStyle(
                        fontFamily: NTypography.fontFamilyBase,
                        fontSize: NTypography.sizeXs,
                        color: muted,
                      ),
                    ),
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: collapsed ? -0.25 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: Icon(
                        Icons.expand_more,
                        size: 20,
                        color: muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
