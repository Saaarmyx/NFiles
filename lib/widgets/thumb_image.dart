// lib/widgets/thumb_image.dart
//
// Foto o miniatura con desvanecimiento al aparecer.
//
// # Por qué un widget propio y no `Image.file` a secas
//
// Dos motivos, ambos con la misma causa: el `ListView.builder` reutiliza las
// fichas, y una miniatura native llega del motor DESPUÉS del primer pintado.
//
//  1. **`Image.file` pierde la imagen al reconstruir.** Cuando el widget se
//     reconstruye (por ejemplo, al cambiar el filtro de la categoría),
//     Flutter descarta la imagen resuelta y la vuelve a pedir. En una lista
//     de 200 fichas eso son 200 parpadeos.
//  2. **La miniatura no está lista en el primer `build`.** La ruta llega por
//     el controlador tras abrir un isolate, así que la ficha se pinta primero
//     con el icono de familia y luego con la imagen.
//
// Aquí se resuelve una vez y se cachea el `ImageProvider` en el `State`, así
// que un rebuild no reinicia la carga, y el desvanecido ocurre una sola vez
// por archivo.
//
// # Por qué `AnimationController` y no `AnimatedOpacity`
//
// La versión anterior metía un `AnimatedOpacity` dentro del `frameBuilder`,
// calculando `opacity: frame == null ? 0 : 1`. Parece más simple, y no
// funciona: `onEnd` solo se dispara si la animación *llega a empezar*, y con
// la opacidad en 0 no hay nada que anime. El widget se queda a 0 para
// siempre, sin llegar a verse.
//
// Con un controlador propio el orden es explícito y comprobable: cuando
// llega el primer frame se lanza `forward()` y el `FadeTransition` sube de 0
// a 1 exactamente una vez. Tras eso `_started` impide relanzarlo.
//
// # El fallback
//
// Un archivo que no se puede decodificar (un PNG corrupto, o el marcador de
// texto que el motor deja para un PDF) no puede dejar un hueco gris: cae al
// icono de la familia, que es lo que el usuario entiende.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:NexoraUi/NexoraUi.dart';

/// Imagen de archivo con *fade-in* único y espacio reservado por quien la
/// mete.
///
/// No fija tamaño: el hueco lo determina el `SizedBox` del llamador, que ya
/// sabe las medidas de la ficha. Ponerlas aquí obligaría a duplicarlas en
/// los dos sitios y a que se desincronizasen.
class ThumbImage extends StatefulWidget {
  const ThumbImage({
    super.key,
    required this.path,
    this.provider,
    this.fit = BoxFit.cover,
    this.isThumb = false,
    this.fallbackIcon,
    this.errorBuilder,
  });

  /// Ruta absoluta de lo que se pinta: la miniatura en caché o el original.
  ///
  /// Se usa para la clave del widget y para el `ImageProvider` por defecto.
  final String path;

  /// Fuente de la imagen, si se quiere una que no sea el archivo.
  ///
  /// Por defecto es `FileImage(File(path))`. Existe por dos razones: un
  /// `MemoryImage` sirve cuando los bytes ya están en memoria, y en los
  /// tests es la única vía de ejercitar el fundido, porque `FileImage` hace
  /// `File.readAsBytes()` —E/S real— antes de decodificar, y el binding de
  /// test solo acelera el códec, no la lectura del disco. Con `FileImage` el
  /// primer frame nunca llega y el fundido no se puede observar.
  final ImageProvider? provider;

  final BoxFit fit;

  /// `true` si [path] es una miniatura generada y no el archivo original.
  ///
  /// Solo informativo: el widget no cambia su comportamiento por esto. Está
  /// para que el llamador pueda documentar qué está pintando.
  final bool isThumb;

  /// Icono a mostrar si la imagen no se puede cargar.
  ///
  /// `null` = no pinta nada, y quien lo use debe haber reservado el hueco.
  final IconData? fallbackIcon;

  /// Qué se pinta cuando la carga falla, en vez de [fallbackIcon].
  ///
  /// Existe para el caso de la cuadrícula, que ya tiene su propio mosaico
  /// (`NImageFallback` del kit) con el color de la superficie correcta. Con
  /// solo [fallbackIcon] habría dos estilos distintos de "no se pudo cargar"
  /// según de dónde venga el widget.
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;

  @override
  State<ThumbImage> createState() => _ThumbImageState();
}

class _ThumbImageState extends State<ThumbImage>
    with SingleTickerProviderStateMixin {
  /// El provider queda cacheado para no re-resolver en cada rebuild.
  ///
  /// Es la clave de que un `setState` del padre no reinicie la carga: si se
  /// construyera `FileImage` en cada `build`, la identidad de la imagen
  /// cambiaría y Flutter la trataría como una imagen nueva.
  ImageProvider? _provider;

  /// Desvanecimiento de entrada, 0 (invisible) a 1 (opaca).
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  /// `true` cuando el fundido ya se lanzó. Impide que un rebuild lo reinicie.
  bool _started = false;

  @override
  void didUpdateWidget(ThumbImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Solo se invalida si cambia el archivo de verdad. Un rebuild con las
    // mismas props no toca nada, que es justo el caso de las 200 fichas de
    // una lista que se reconstruyen al filtrar.
    if (oldWidget.path != widget.path || oldWidget.provider != widget.provider) {
      _provider = null;
      _started = false;
      _fade.value = 0;
    }
  }

  @override
  void dispose() {
    // Sin esto, cada ficha de la lista deja un ticker vivo en el `TickerMode`
    // del árbol, y una categoría con muchas acaba consumiendo batería para
    // animar imágenes que ya no están.
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _provider ??= widget.provider ?? FileImage(File(widget.path));

    return FadeTransition(
      // `FadeTransition` escucha al controlador, así que se reconstruye sola
      // durante la animación sin necesidad de un `setState` por frame.
      opacity: _fade,
      child: Image(
        key: ValueKey<String>(widget.path),
        image: _provider!,
        fit: widget.fit,
        width: double.infinity,
        height: double.infinity,
        // `gaplessPlayback`: al reconstruir la ficha, mantiene el fotograma
        // anterior en vez de volver a negro. Sin esto, la lista parpadea.
        gaplessPlayback: true,
        frameBuilder: _onFrame,
        errorBuilder: (context, e, s) =>
            widget.errorBuilder?.call(context, e, s) ?? _fallback(context),
      ),
    );
  }

  /// Lanza el fundido en cuanto hay algo que enseñar.
  ///
  /// Se llama en cada frame que entrega `Image`, incluido el `null` inicial.
  /// El `null` se ignora a propósito: fundir desde una imagen que aún no
  /// existe es fundir desde la nada, y el usuario ve un destello.
  Widget _onFrame(
    BuildContext context,
    Widget child,
    int? frame,
    bool wasSynchronouslyLoaded,
  ) {
    if (frame != null && !_started) {
      _started = true;
      // Con `wasSynchronouslyLoaded` la imagen ya está en pantalla: no hay
      // transición que enseñar, y arrancar el fundido solo añadiría un parpadeo.
      if (wasSynchronouslyLoaded) {
        _fade.value = 1;
      } else {
        _fade.forward();
      }
    }
    return child;
  }

  Widget _fallback(BuildContext context) {
    final icon = widget.fallbackIcon;
    if (icon == null) return const SizedBox.shrink();
    // El fondo se pone para que el icono tenga contraste sobre cualquier
    // wallpaper, igual que en el resto de la app.
    return ColoredBox(
      color: context.nHoverColor,
      child: Center(
        child: Icon(icon, size: 22, color: context.nMutedTextColor),
      ),
    );
  }
}
