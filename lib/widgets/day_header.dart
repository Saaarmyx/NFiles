// lib/widgets/day_header.dart
//
// Cabecera de día de "Recientes".
//
// `"{Fecha} • {N} elementos"` a la izquierda y el control de
// colapso a la derecha. El colapso es por día y se recuerda mientras la
// pantalla viva: al recargar no debe saltar todo abierto ni perder lo que
// el usuario dejó plegado.
import 'package:flutter/material.dart';
import 'package:NexoraUi/NexoraUi.dart';

/// Cabecera de un grupo de día.
class DayHeader extends StatelessWidget {
  /// Etiqueta del día: "Hoy", "Ayer", "Hace 2 días", o una fecha.
  final String label;

  /// Archivos de este día.
  final int count;

  /// Si la sección está plegada.
  final bool collapsed;

  final VoidCallback onToggleCollapsed;

  const DayHeader({
    super.key,
    required this.label,
    required this.count,
    required this.collapsed,
    required this.onToggleCollapsed,
  });

  @override
  Widget build(BuildContext context) {
    final muted = context.nMutedTextColor;
    // Mismo horizontal que la tarjeta de grupo (spaceMd a cada lado):
    // ni el texto ni el icono sobresalen de la card.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NSpacing.spaceMd,
        NSpacing.spaceMd,
        NSpacing.spaceMd,
        NSpacing.spaceXs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$label • $_countText',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: NTypography.fontFamilyBase,
                fontWeight: NTypography.weightSemibold,
                fontSize: NTypography.sizeMd,
                color: context.nPrimaryTextColor,
              ),
            ),
          ),
          Semantics(
            button: true,
            label: collapsed ? 'Desplegar $label' : 'Plegar $label',
            child: InkWell(
              onTap: onToggleCollapsed,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(NSpacing.space2xs),
                child: AnimatedRotation(
                  // Plegada apunta a la derecha; abierta, hacia abajo.
                  turns: collapsed ? -0.25 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 22,
                    color: muted,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _countText =>
      count == 1 ? '1 elemento' : '$count elementos';
}
