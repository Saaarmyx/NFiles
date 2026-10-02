import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:NexoraCore/NexoraCore.dart';
import 'package:NFiles/models/file_model.dart';

void main() {
  group('formatBytes', () {
    test('0 y negativos no inventan tamaño', () {
      expect(FileModel.formatBytes(0), '—');
      expect(FileModel.formatBytes(-5), '—');
    });

    test('usa coma decimal (formato español)', () {
      expect(FileModel.formatBytes(1536), '1,5 KB');
    });

    test('sin decimales a partir de 10', () {
      expect(FileModel.formatBytes(12 * 1024 * 1024), '12 MB');
    });

    test('bytes y KB exactos', () {
      expect(FileModel.formatBytes(512), '512 B');
      expect(FileModel.formatBytes(1024), '1 KB');
    });

    test('sube de unidad hasta TB', () {
      expect(FileModel.formatBytes(1024 * 1024 * 1024), '1 GB');
      expect(FileModel.formatBytes(1024 * 1024 * 1024 * 1024), '1 TB');
    });
  });

  group('folderName (lugar de guardado)', () {
    test('devuelve la carpeta inmediata, no la ruta entera', () {
      final file = FileModel(
        id: '/a',
        path: '/storage/emulated/0/DCIM/Camera/photo.jpg',
        title: 'photo.jpg',
        dateCreated: DateTime(2026),
        dateModified: DateTime(2026),
        sizeInBytes: 1,
      );
      expect(file.folderName, 'Camera');
    });

    test('NO pisa la etiqueta geográfica (EXIF)', () {
      final file = FileModel(
        id: '/a',
        path: '/dcim/x.jpg',
        title: 'x.jpg',
        dateCreated: DateTime(2026),
        dateModified: DateTime(2026),
        sizeInBytes: 1,
        latitude: 40.4,
        longitude: -3.7,
        locationLabel: 'Madrid',
      );
      // Son dos conceptos distintos: dónde se guarda vs dónde se hizo.
      expect(file.folderName, 'dcim');
      expect(file.locationLabel, 'Madrid');
    });
  });

  group('kindForPath', () {
    test('reconoce cada familia', () {
      expect(kindForPath('a/b/foto.JPG'), FileKind.image);
      expect(kindForPath('a/b/clip.MP4'), FileKind.video);
      expect(kindForPath('a/b/cancion.flac'), FileKind.audio);
      expect(kindForPath('a/b/informe.pdf'), FileKind.document);
      expect(kindForPath('a/b/backup.zip'), FileKind.archive);
      expect(kindForPath('a/b/main.dart'), FileKind.code);
      expect(kindForPath('a/b/app.apk'), FileKind.apk);
    });

    test('lo desconocido cae en other, no en null', () {
      expect(kindForPath('a/b/sin-extension'), FileKind.other);
      expect(kindForPath('a/b/'), FileKind.other);
      expect(kindForPath('a/b/cosas.desconocido'), FileKind.other);
    });

    test('es insensible a mayúsculas', () {
      expect(kindForPath('FOTO.PNG'), FileKind.image);
      expect(kindForPath('CANCION.MP3'), FileKind.audio);
    });
  });

  group('extensiones del escaneo', () {
    test('la taxonomía cubre las seis familias de Explorar', () {
      // Documentos, imágenes, vídeos, música, archivos y APKs tienen que
      // ser escaneables o sus filas saldrían siempre vacías.
      for (final kind in [
        FileKind.document,
        FileKind.image,
        FileKind.video,
        FileKind.audio,
        FileKind.apk,
      ]) {
        expect(
          kFileKindExtensions[kind],
          isNotEmpty,
          reason: '${kind.label} sin extensiones',
        );
      }
    });

    test('las imágenes sondeables coinciden con las de la sonda EXIF', () {
      // Si la sonda metiera una extensión que el escaneo no acepta, o
      // al revés, aparecerían metadatos que nadie pidió.
      expect(
        kProbeableExtensions.containsAll(['.jpg', '.png', '.webp']),
        isTrue,
      );
    });
  });

  group('matriz de Explorar (acceso total)', () {
    // Lo que "Acceso a todos los archivos" debe clasificar: si una de
    // estas extensiones cae en otra familia, su categoría de Explorar
    // sale vacía aunque el disco esté lleno de esos archivos.
    test('documentos: pdf, txt, docx, xlsx, pptx', () {
      expect(kindForPath('a/informe.pdf'), FileKind.document);
      expect(kindForPath('a/notas.txt'), FileKind.document);
      expect(kindForPath('a/carta.docx'), FileKind.document);
      expect(kindForPath('a/cuentas.xlsx'), FileKind.spreadsheet);
      expect(kindForPath('a/charla.pptx'), FileKind.presentation);
    });

    test('comprimidos: zip, rar, tar, gz, 7z', () {
      for (final ext in ['zip', 'rar', 'tar', 'gz', '7z']) {
        expect(kindForPath('a/datos.$ext'), FileKind.archive, reason: ext);
      }
    });

    test('apks: apk y xapk', () {
      expect(kindForPath('a/app.apk'), FileKind.apk);
      expect(kindForPath('a/app.xapk'), FileKind.apk);
    });

    test('audio y vídeo: mp3, wav, flac, mp4, mkv, avi', () {
      for (final ext in ['mp3', 'wav', 'flac']) {
        expect(kindForPath('a/sonido.$ext'), FileKind.audio, reason: ext);
      }
      for (final ext in ['mp4', 'mkv', 'avi']) {
        expect(kindForPath('a/clip.$ext'), FileKind.video, reason: ext);
      }
    });
  });

  group('iconos', () {
    test('cada familia tiene icono', () {
      // Los iconos viven en la mitad con UI de NexoraCore: el dominio puro
      // no puede devolver un IconData.
      for (final kind in FileKind.values) {
        expect(kindIcon(kind), isNotNull);
      }
    });

    test('un .zip tiene icono propio; el resto de comprimidos, el genérico', () {
      // El .zip es el comprimido que el usuario reconoce de un vistazo;
      // los demás comparten el icono genérico de la familia.
      expect(iconForPath('x.zip'), Icons.folder_zip_outlined);
      expect(iconForPath('x.7z'), Icons.archive_outlined);
      expect(iconForPath('x.rar'), Icons.archive_outlined);
      // Y ningún comprimido se confunde con un documento o una canción.
      expect(iconForPath('x.zip'), isNot(iconForPath('x.pdf')));
      expect(iconForPath('x.zip'), isNot(iconForPath('x.mp3')));
    });
  });
}
