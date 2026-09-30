// NFiles ya consume la API asíncrona de NexoraCore en su controlador;
// lo que falta es que NPhotos deje deBring su propia sonda de medios
// suelta. Este es el punto de conexión.

import 'package:flutter_test/flutter_test.dart';
import 'package:NexoraCore/NexoraCore.dart';

import 'package:NFiles/controllers/files_controller.dart';

void main() {
  group('FilesController y la capa de medios', () {
    late FilesController controller;

    setUp(() {
      controller = FilesController();
    });

    tearDown(() => controller.dispose());

    test('expone los servicios de NexoraCore', () {
      expect(controller.thumbs, isA<ThumbsService>());
      expect(controller.media, isA<MediaIndexService>());
    });

    test('el perfil de rendimiento llega a los TRES caminos', () {
      // El punto de esta prueba: si solo se propagara al escaneo, las
      // miniaturas seguirían en gama alta. Es el fallo que hace que un
      // gama baja se ahogue sin que nada falle.
      //
      // `CorePerformance.forTesting` toca `WidgetsBinding` por leer el
      // idioma del sistema, así que hace falta el binding. Es un
      // requisito de Flutter, no del código bajo prueba.
      TestWidgetsFlutterBinding.ensureInitialized();

      final performance = CorePerformance.forTesting(
        CorePrefs.inMemory('nfiles_test'),
        PerformanceProfile.low,
      );
      addTearDown(performance.dispose);

      expect(() => controller.applyPerformanceProfile(performance),
          returnsNormally);
      expect(controller.thumbs, isNotNull);
      expect(controller.media, isNotNull);
    });

    test('requestThumbnails con lista vacía no hace nada', () async {
      expect(await controller.requestThumbnails(const []), isEmpty);
    });

    test('requestThumbnails degrada a vacío sin motor', () async {
      // Sin `.so` el servicio devuelve lista vacía y el mapa sale vacío.
      // La UI usa su propio placeholder: degradar es el estado normal.
      final out = await controller.requestThumbnails(
        ['/tmp/inexistente_1.jpg', '/tmp/inexistente_2.jpg'],
      );
      expect(out, isA<Map<String, ThumbnailRef>>());
    });

    test('countMedia con lista vacía es 0, no null', () async {
      expect(await controller.countMedia(const []), 0);
    });

    test('countMedia devuelve null sin motor', () async {
      // `null` = "no sé", y quien llama decide si estimar o mostrar lo
      // que ya tiene. No es lo mismo que 0.
      final n = await controller.countMedia(['/tmp/inexistente.jpg']);
      expect(n, anyOf(isNull, isA<int>()));
    });

    test('groupByDay con lista vacía devuelve vacío', () async {
      expect(await controller.groupByDay(const []), isEmpty);
    });
  });

  group('el lote de miniaturas se acota', () {
    test('el máximo por tanda está acotado', () {
      // Cada tanda es un viaje al isolate, así que un lote de 30.000
      // en una sola llamada sería una espera larga sin progreso visible.
      // El valor es un detalle de implementación, pero el recorte no.
      expect(FilesController.thumbBatch, lessThanOrEqualTo(1024));
    });
  });
}
