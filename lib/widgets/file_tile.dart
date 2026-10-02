// lib/widgets/file_tile.dart
//
// Adaptador de dominio: mapea el modelo `FileModel` a las primitivas de
// imagen del kit (NImageTile + insignias). No contiene lógica visual
// propia salvo la regla de insignias, que es del dominio.
//
// Reglas de insignias:
// - Siempre hay miniatura. En vídeos NO se intenta decodificar el
//   archivo (fallaría siempre): se usa NVideoThumb, reconocible.
// - Arriba derecha: favorito (si aplica).
// - Abajo centro: si es vídeo, play + duración.
// - Abajo izquierda: solo archivos, máximo 2 iconos
//   (motion > HD/+50MP > selfie). En vídeos va vacío.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:NexoraUi/NexoraUi.dart';

import '../models/file_model.dart';
import 'thumb_image.dart';

class FileTile extends StatelessWidget {
  final String path;
  final int cacheWidth;
  final BoxFit fit;
  final double? width;
  final bool isVideo;

  /// Modelo rico opcional. Si se pasa, las insignias se derivan de él.
  /// Mantiene compat con llamadas legacy que solo pasan [path]/[isVideo].
  final FileModel? file;

  /// Modo selección: si no es null, se muestra el estado seleccionado.
  final bool? selected;

  /// Silencia las insignias (para listas de selección compactas).
  final bool showBadges;

  /// Miniatura ya generada en disco por el motor nativo, o `null`.
  ///
  /// La resuelve el controlador antes de pintar. Cuando viene, la casilla
  /// pinta el JPEG de la caché en vez de decodificar el archivo entero: en
  /// una cuadrícula con 300 fichas, cargar un APK o un PDF en crudo por
  /// ficha es lo que hace que el scroll se atasque.
  final String? thumbnailPath;

  const FileTile({
    super.key,
    required this.path,
    this.cacheWidth = 250,
    this.fit = BoxFit.cover,
    this.width,
    this.isVideo = false,
    this.file,
    this.selected,
    this.showBadges = true,
    this.thumbnailPath,
  });

  bool get _effectiveIsVideo => file?.isVideo ?? isVideo;
  bool get _effectiveIsFavorite => file?.isFavorite ?? false;
  String get _effectivePath => file?.path ?? path;

  @override
  Widget build(BuildContext context) {
    final video = _effectiveIsVideo;
    final inSelection = selected != null;
    final badges = showBadges && !inSelection ? _buildBadges(video) : const <NImageBadge>[];
    final thumb = thumbnailPath;

    return NImageTile(
      selected: selected,
      image: _buildImage(video, thumb),
      badges: badges,
    );
  }

  /// Decide qué se pinta en la casilla.
  ///
  /// Tres casos, en este orden:
  ///
  /// 1. **Vídeo sin miniatura**: el `NVideoThumb` de siempre, con su icono de
  ///    cámara. Es un marcador conocido y no se intenta adivinar el fotograma.
  /// 2. **Con miniatura nativa** (un APK, un PDF): el JPEG de la caché. Se
  ///    decodifica 300x300 en vez de un archivo que puede pesar cientos de
  ///    megas, y con fundido al entrar.
  /// 3. **Foto sin miniatura**: el archivo original, con `cacheWidth` para
  ///    que el decodificador reduzca durante la lectura.
  Widget _buildImage(bool video, String? thumb) {
    if (thumb != null) {
      return ThumbImage(
        path: thumb,
        isThumb: true,
        fit: fit,
        // El motor no decodifica lo que no entiende: deja un marcador de
        // texto, y eso hay que sustituirlo por el mosaico del kit, no
        // intentar pintarlo como imagen.
        errorBuilder: (context, _, _) => const NImageFallback(),
      );
    }
    if (video) return const NVideoThumb();
    return Image.file(
      File(_effectivePath),
      width: width,
      fit: fit,
      cacheWidth: cacheWidth,
      errorBuilder: (context, error, stack) => const NImageFallback(),
    );
  }

  List<NImageBadge> _buildBadges(bool video) {
    return [
      if (_effectiveIsFavorite)
        const NImageBadge(
          anchor: NBadgeAnchor.topEnd,
          child: NImageCircleBadge(icon: Icons.favorite, iconColor: Colors.red),
        ),
      if (video)
        NImageBadge(
          anchor: NBadgeAnchor.bottomCenter,
          margin: 0,
          child: Center(
            child: NVideoBadge(label: file?.formattedDuration),
          ),
        )
      else if (_statusIcons().isNotEmpty)
        NImageBadge(
          anchor: NBadgeAnchor.bottomStart,
          child: NImageBadgeRow(icons: _statusIcons()),
        ),
    ];
  }

  /// Máximo 2 iconos de estado para archivos. Prioridad:
  /// motion > HD/+50MP > selfie.
  List<IconData> _statusIcons() {
    final p = file;
    if (p == null || p.isVideo) return const [];
    final icons = <IconData>[];
    if (p.isMotionPhoto) icons.add(Icons.motion_photos_on_outlined);
    if (p.isHighResolution) icons.add(Icons.hd_outlined);
    if (p.isSelfie) icons.add(Icons.face_outlined);
    if (icons.length > 2) return icons.sublist(0, 2);
    return icons;
  }
}
