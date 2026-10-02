// test/thumbnails_policy_test.dart
//
// El ajuste "Miniaturas solo con Wi-Fi" conectado al servicio de
// miniaturas.
//
// # Qué protege este archivo
//
// 1. Que con el ajuste EN, el prerrellenado por scroll NO llame al motor:
//    es el trabajo en segundo plano que el ajuste corta. Antes el flag se
//    guardaba y no hacía nada, que es peor que no ofrecerlo.
// 2. Que las miniaturas ya resueltas se sigan usando: apagar el ajuste no
//    tira trabajo ya hecho.
// 3. Que la demanda explícita (abrir un archivo) sí genere, porque a eso
//    no se le puede negar por un ajuste de red.
import 'dart:io';

import 'package:NexoraCore/NexoraCore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:NFiles/controllers/files_controller.dart';
import 'package:NFiles/services/file_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late _SpyThumbs thumbs;
  late FilesController controller;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('nfiles_thumb');
    thumbs = _SpyThumbs();
    controller = FilesController(
      fileService: FileService(roots: [tmp], useIsolate: false),
      thumbs: thumbs,
    );
    addTearDown(controller.dispose);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('con el ajuste apagado el prerrellenado pide al motor', () async {
    expect(controller.thumbnailsWifiOnly, isFalse);

    final out = await controller.ensureThumbnails(['/tmp/a.jpg']);

    expect(thumbs.lotes, 1);
    expect(out['/tmp/a.jpg'], '/cache/a.jpg');
  });

  test('con el ajuste encendido el prerrellenado no toca el motor', () async {
    controller.setThumbnailsWifiOnly(true);

    final out = await controller.ensureThumbnails(['/tmp/a.jpg']);

    expect(thumbs.lotes, 0, reason: 'el ajuste corta el trabajo en segundo plano');
    expect(out, isEmpty, reason: 'y la ficha cae al icono de familia');
  });

  test('apagado y encendido no se pisan: el mapa se respeta', () async {
    await controller.ensureThumbnails(['/tmp/a.jpg']);
    expect(thumbs.lotes, 1);

    controller.setThumbnailsWifiOnly(true);
    final out = await controller.ensureThumbnails(['/tmp/a.jpg', '/tmp/b.jpg']);

    // Lo ya generado sigue disponible: apagar el ajuste no borra caché.
    expect(out['/tmp/a.jpg'], '/cache/a.jpg');
    expect(thumbs.lotes, 1, reason: 'b.jpg no se pide con el ajuste activo');
    expect(controller.thumbnailFor('/tmp/a.jpg'), '/cache/a.jpg');
  });

  test('la demanda explícita genera aunque el ajuste esté activo', () async {
    controller.setThumbnailsWifiOnly(true);

    final ruta = await controller.generateThumbnail('/tmp/a.jpg');

    expect(thumbs.una, 1);
    expect(ruta, '/cache/a.jpg');
    expect(controller.thumbnailFor('/tmp/a.jpg'), '/cache/a.jpg');
  });

  test('volver a apagar el ajuste reanuda el prerrellenado', () async {
    controller.setThumbnailsWifiOnly(true);
    await controller.ensureThumbnails(['/tmp/a.jpg']);
    expect(thumbs.lotes, 0);

    controller.setThumbnailsWifiOnly(false);
    await controller.ensureThumbnails(['/tmp/b.jpg']);

    expect(thumbs.lotes, 1);
  });
}

/// Motor de miniaturas de mentira que cuenta las llamadas.
///
/// No hace falta el `.so`: lo que se comprueba es si el controller llama
/// o no al servicio, y con un motor real el resultado dependería de si la
/// caché de disco está vacía.
class _SpyThumbs extends ThumbsService {
  int lotes = 0;
  int una = 0;

  @override
  Future<Map<String, String>> thumbnailsFor(
    Iterable<String> paths, {
    int? boxPx,
  }) async {
    lotes++;
    return {
      for (final p in paths) p: '/cache/${p.split('/').last}',
    };
  }

  @override
  Future<ThumbnailRef?> generateOne(String path, {int? boxPx}) async {
    una++;
    return ThumbnailRef(
      source: path,
      path: '/cache/${path.split('/').last}',
      width: 200,
      height: 200,
      status: ThumbStatus.generated,
    );
  }
}
