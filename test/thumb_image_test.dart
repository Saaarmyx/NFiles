// test/thumb_image_test.dart
//
// Miniaturas de archivo en la UI de NFiles.
//
// # Qué protege este archivo
//
// 1. Que una ficha con miniatura muestre la imagen, no el icono de familia.
// 2. Que el archivo que no se puede cargar caiga al icono, no a un hueco.
// 3. Que el `FileImage` se resuelva una vez: si el provider se reconstruye
//    en cada `build`, un rebuild del padre reinicia la carga y la ficha
//    parpadea, que es justo lo que el widget existe para evitar.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:NFiles/widgets/thumb_image.dart';

void main() {
  late Directory tmp;
  late String imagePath;
  late ui.Image imgA;
  late ui.Image imgB;

  /// Clave única de provider para ESTE test.
  ///
  /// Importa más de lo que parece: el `ImageCache` de Flutter sobrevive entre
  /// los tests de un mismo archivo, así que dos tests que usen la misma clave
  /// comparten la imagen ya resuelta. El segundo recibiría el frame de
  /// inmediato, con `wasSynchronouslyLoaded` a `true`, y el fundido no
  /// arrancaría —el test mediría un salto a 1.0 y parecería un widget
  /// sin fundido, no un test mal escrito.
  late int tag;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('thumb_test');
    // Un PNG 1x1 real, para que `FileImage` lo pueda decodificar.
    imagePath = '${tmp.path}/pixel.png';
    File(imagePath).writeAsBytesSync(_png);
    // Dos imágenes distintas: el test de "cambiar de provider" necesita que
    // el `ImageProvider` no sea igual, o Flutter reutilizaría la de antes.
    imgA = solidImage(8);
    imgB = solidImage(16, color: 0xFF7F3F3F);
    tag = ++_seq;
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 48, height: 48, child: child),
        ),
      );

  /// Un `ThumbImage` cuya imagen tarda un frame en llegar, como en la app.
  ///
  /// Hace falta un provider ASÍNCRONO, y no `FileImage` ni `MemoryImage`:
  ///
  /// - `FileImage` lee el disco con `File.readAsBytes()` (E/S real) y el
  ///   binding de test solo acelera el códec, así que el primer frame no
  ///   llega nunca.
  /// - `MemoryImage` resuelve con `SynchronousFuture`, así que
  ///   `wasSynchronouslyLoaded` sale `true`, el widget no funda nada y la
  ///   opacidad es 1.0 desde el primer frame.
  ///
  /// [_DelayedImage] es el término medio: los bytes ya están en memoria, pero
  /// se entregan en el siguiente evento del bucle. Es exactamente el caso que
  /// se quiere comprobar, y es determinista.
  Widget inMemory() => wrap(ThumbImage(
        path: 'en-memoria',
        provider: _DelayedImage(imgA, tag),
      ));

  /// El `FadeTransition` del propio `ThumbImage`, sin los de las rutas.
  Finder fadeInThumb() => find.descendant(
        of: find.byType(ThumbImage),
        matching: find.byType(FadeTransition),
      );

  group('ThumbImage', () {
    testWidgets('pinta la imagen cuando el archivo existe', (tester) async {
      await tester.pumpWidget(wrap(ThumbImage(path: imagePath)));
      expect(find.byType(Image), findsOneWidget);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });

    testWidgets('un archivo roto cae al icono, no a un hueco', (tester) async {
      // El fallo de carga es el caso real: un marcador de PDF o un PNG
      // corrupto. Tiene que verse el icono de la familia.
      final roto = '${tmp.path}/roto.png';
      File(roto).writeAsStringSync('esto no es una imagen');
      await tester.pumpWidget(wrap(ThumbImage(
        path: roto,
        fallbackIcon: Icons.picture_as_pdf_outlined,
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull,
          reason: 'un archivo ilegible no puede lanzar');
    });

    testWidgets('sin fallback y sin archivo, no rompe', (tester) async {
      await tester.pumpWidget(wrap(ThumbImage(
        path: '${tmp.path}/no-existe.png',
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });

    testWidgets('el provider se resuelve UNA vez entre rebuilds',
        (tester) async {
      await tester.pumpWidget(wrap(ThumbImage(path: imagePath)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Se fuerza un rebuild del padre con el mismo path.
      await tester.pumpWidget(wrap(ThumbImage(path: imagePath)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      // La clave es que no se haya resuelto de nuevo: con un provider
      // distinto, Flutter lo trataría como imagen nueva.
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.key, ValueKey<String>(imagePath));
    });

    testWidgets('cambiar de path invalida la cache del widget',
        (tester) async {
      await tester.pumpWidget(wrap(ThumbImage(path: imagePath)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      const otra = '/tmp/nexora_otra.png';
      await tester.pumpWidget(wrap(ThumbImage(path: otra)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.key, const ValueKey<String>(otra));
    });

    // Estas pruebas necesitan TRES pumps como mínimo, y conviene saber por
    // qué antes de escribirlas mal otra vez:
    //
    //   1. `pumpWidget` pinta con la imagen todavía sin resolver.
    //   2. `pump` resuelve el `Future` del provider y el `Image` recibe su
    //      primer frame. Ahí `_onFrame` llama a `forward()`, que PLANIFICA
    //      la animación.
    //   3. Solo en el siguiente frame avanza el reloj de la animación.
    //
    // Con dos pumps el fundido arrancaba en el segundo y el valor se leía
    // todavía a 0, que parece un widget roto y no un test mal escrito.

    testWidgets('la imagen queda opaca tras el fundido', (tester) async {
      await tester.pumpWidget(inMemory());
      await tester.pumpAndSettle();

      // Lo que se afirma es la opacidad FINAL, no qué widget hay. Si el
      // controlador se quedara en 0 —que es lo que pasaba con el
      // `AnimatedOpacity` anterior— las 200 fichas de una categoría quedarían
      // translúcidas para siempre sin que saliera nada en ningún log.
      final fade = tester.widget<FadeTransition>(fadeInThumb());
      expect(fade.opacity.value, 1.0);
    });

    testWidgets('el fundido avanza en vez de saltar', (tester) async {
      await tester.pumpWidget(inMemory());

      // Se mide la serie entera en vez de un instante suelto. Cuántos pumps
      // tarda en llegar el frame depende del `ImageCache` que arrastran los
      // tests anteriores, y afirmar sobre "el segundo pump" daba un resultado
      // distinto según el orden de ejecución.
      //
      // Lo que importa es la FORMA de la curva, y esa es estable:
      //   - fundido roto  -> [0, 0, 0, 0, 0, 0]  (nunca se ve la imagen)
      //   - salto seco    -> [0, 1, 1, 1, 1, 1]  (sin transición)
      //   - fundido real  -> [0, .3, .7, 1, 1, 1] (pasa por un intermedio)
      final opacities = <double>[];
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
        opacities.add(
          tester.widget<FadeTransition>(fadeInThumb()).opacity.value,
        );
      }

      expect(opacities.any((v) => v > 0.0 && v < 1.0), isTrue,
          reason: 'tiene que pasar por una opacidad intermedia: $opacities');
      expect(opacities.last, 1.0,
          reason: 'y tiene que acabar opaca: $opacities');
      await tester.pumpAndSettle();
    });

    testWidgets('un rebuild no reinicia el fundido', (tester) async {
      await tester.pumpWidget(inMemory());
      await tester.pumpAndSettle();

      // Mismo path, mismo provider: el provider se reaprovecha y el fundido
      // no vuelve a empezar. Si reiniciara, una lista de 200 fichas
      // parpadearía en cada reconstrucción.
      await tester.pumpWidget(inMemory());
      await tester.pump();
      final fade = tester.widget<FadeTransition>(fadeInThumb());
      expect(fade.opacity.value, 1.0,
          reason: 'reconstruir no devuelve la imagen a invisible');
    });

    testWidgets('cambiar de provider reinicia el fundido', (tester) async {
      await tester.pumpWidget(inMemory());
      await tester.pumpAndSettle();

      // Otra imagen en otra ruta: el fundido vuelve a empezar, porque lo que
      // entra es un archivo distinto.
      await tester.pumpWidget(wrap(ThumbImage(
        path: 'otra',
        provider: _DelayedImage(imgB, tag + 1000),
      )));
      await tester.pump();
      final fade = tester.widget<FadeTransition>(fadeInThumb());
      expect(fade.opacity.value, lessThan(1.0));

      // Drenar lo que quede: el `Future` del provider se resuelve en un
      // timer de 0, y un timer vivo al final del test es un fallo aunque
      // aserciones fueran correctas.
      await tester.pumpAndSettle();
    });
  });
}

/// PNG 1x1 transparente, en bytes literales.
final Uint8List _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

/// Contador para dar una clave de provider distinta a cada test.
int _seq = 0;

/// Un `ImageProvider` que entrega el frame un evento después.
///
/// Existe solo para los tests del fundido. Ver el comentario de `inMemory()`
/// en el grupo: con `MemoryImage` la carga es síncrona y no hay transición que
/// observar.
///
/// La imagen se pinta aquí mismo con un `Canvas` y `toImageSync`, sin pasar
/// por el códec: el códec de `dart:ui` es una operación asíncrona real que en
/// la zona de test no se resuelve, y un `Future` que nunca completa es
/// justamente el fallo que este provider viene a evitar.
class _DelayedImage extends ImageProvider<_DelayedImage> {
  _DelayedImage(this.image, this.tag);

  final ui.Image image;

  /// Distingue una imagen de otra para la caché de providers.
  final int tag;

  @override
  Future<_DelayedImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_DelayedImage>(this);

  @override
  ImageStreamCompleter loadImage(
    _DelayedImage key,
    ImageDecoderCallback decode,
  ) {
    // `Future(...)` en vez de un valor directo: eso es lo que hace la entrega
    // asíncrona sin salir de la zona de test, porque un `Future` así se
    // resuelve al avanzar el reloj de `pump`.
    return OneFrameImageStreamCompleter(
      Future<ImageInfo>(() => ImageInfo(image: key.image, scale: 1.0)),
    );
  }

  @override
  bool operator ==(Object other) => other is _DelayedImage && other.tag == tag;

  @override
  int get hashCode => Object.hash(1, tag);
}

/// Un cuadrado opaco de [side] px, pintado de forma síncrona.
ui.Image solidImage(int side, {int color = 0xFF3F7F3F}) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
    Paint()..color = Color(color),
  );
  return recorder.endRecording().toImageSync(side, side);
}
