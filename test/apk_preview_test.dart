// test/apk_preview_test.dart
//
// El inspector de APK dentro de la pantalla de previsualización.
//
// # Qué protege este archivo
//
// 1. Que tocar un APK abra el inspector y no "Sin vista previa".
// 2. Que la cabecera, las especificaciones y los permisos se pinten con lo
//    que devuelve el núcleo.
// 3. Que un APK roto pinte el motivo en vez de tirar la pantalla.
//
// # Por qué el APK falso se construye aquí y no se reutiliza el del núcleo
//
// El constructor del test de `NexoraCore` vive en otro paquete y los tests
// no se exportan. Duplicar 80 líneas de constructor es mejor que acoplar
// los tests de NFiles a los de otro paquete: si el núcleo cambia su
// andamiaje, estos tests tienen que seguir valiendo.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:NFiles/controllers/files_controller.dart';
import 'package:NFiles/models/file_model.dart';
import 'package:NFiles/screens/files/file_preview_screen.dart';
import 'package:NexoraUi/NexoraUi.dart';

const List<int> _png1x1 = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
];

int _crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final b in data) {
    crc ^= b;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}

void _u16(List<int> out, int v) =>
    out.addAll([v & 0xFF, (v >> 8) & 0xFF]);
void _u32(List<int> out, int v) => out.addAll(
    [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
void _i32(List<int> out, int v) => _u32(out, v & 0xFFFFFFFF);

Uint8List _zip(Map<String, List<int>> entries) {
  final body = <int>[];
  final central = <int>[];
  for (final e in entries.entries) {
    final name = e.key.codeUnits;
    final data = e.value;
    final local = body.length;
    body.addAll([0x50, 0x4B, 0x03, 0x04]);
    _u16(body, 20);
    _u16(body, 0);
    _u16(body, 0);
    _u16(body, 0);
    _u16(body, 0);
    _u32(body, _crc32(data));
    _u32(body, data.length);
    _u32(body, data.length);
    _u16(body, name.length);
    _u16(body, 0);
    body.addAll(name);
    body.addAll(data);

    central.addAll([0x50, 0x4B, 0x01, 0x02]);
    _u16(central, 20);
    _u16(central, 20);
    _u16(central, 0);
    _u16(central, 0);
    _u16(central, 0);
    _u16(central, 0);
    _u32(central, _crc32(data));
    _u32(central, data.length);
    _u32(central, data.length);
    _u16(central, name.length);
    _u16(central, 0);
    _u16(central, 0);
    _u16(central, 0);
    _u16(central, 0);
    _u32(central, 0);
    _u32(central, local);
    central.addAll(name);
  }
  final out = <int>[];
  out.addAll(body);
  final cdOffset = out.length;
  out.addAll(central);
  final cdSize = central.length;
  out.addAll([0x50, 0x4B, 0x05, 0x06]);
  _u16(out, 0);
  _u16(out, 0);
  _u16(out, entries.length);
  _u16(out, entries.length);
  _u32(out, cdSize);
  _u32(out, cdOffset);
  _u16(out, 0);
  return Uint8List.fromList(out);
}

class _Attr {
  final String name;
  final int type;
  final int data;
  final String? text;

  _Attr.str(this.name, this.text)
      : type = 0x03,
        data = -1;
  _Attr.strNoNs(this.name, this.text)
      : type = 0x03,
        data = -1;
  _Attr.int(this.name, this.data) : text = null, type = 0x10;
  bool get noNs => this is _NoNs;
}

class _NoNs extends _Attr {
  _NoNs(super.name, super.text) : super.strNoNs();
}

Uint8List _axml({
  required String package,
  String? versionName,
  int? versionCode,
  int? minSdk,
  int? targetSdk,
  List<String> permissions = const [],
  String? appLabel,
  String? appIcon,
}) {
  final strings = <String>[
    'http://schemas.android.com/apk/res/android',
    'manifest',
    'package',
    package,
  ];
  int s(String v) {
    var i = strings.indexOf(v);
    if (i < 0) {
      strings.add(v);
      i = strings.length - 1;
    }
    return i;
  }

  final chunks = <int>[];

  void start(String name, int ns, List<_Attr> attrs) {
    final a = <int>[];
    _u16(a, 0x0102);
    _u16(a, 16);
    _u32(a, 36 + attrs.length * 20);
    _u32(a, 0);
    _i32(a, -1);
    _i32(a, ns);
    _u32(a, s(name));
    _u16(a, 20);
    _u16(a, 20);
    _u16(a, attrs.length);
    _u16(a, 0);
    _u16(a, 0);
    _u16(a, 0);
    for (final at in attrs) {
      _i32(a, at.noNs ? -1 : s('http://schemas.android.com/apk/res/android'));
      _u32(a, s(at.name));
      _i32(a, -1);
      _u16(a, 8);
      a.add(0);
      a.add(at.type);
      _u32(a, at.type == 0x03 ? s(at.text!) : at.data);
    }
    chunks.addAll(a);
  }

  void end(String name, int ns) {
    final e = <int>[];
    _u16(e, 0x0103);
    _u16(e, 16);
    _u32(e, 24);
    _u32(e, 0);
    _i32(e, -1);
    _i32(e, ns);
    _u32(e, s(name));
    chunks.addAll(e);
  }

  final m = <_Attr>[_NoNs('package', package)];
  if (versionCode != null) m.add(_Attr.int('versionCode', versionCode));
  if (versionName != null) m.add(_Attr.str('versionName', versionName));
  start('manifest', -1, m);
  final sdk = <_Attr>[];
  if (minSdk != null) sdk.add(_Attr.int('minSdkVersion', minSdk));
  if (targetSdk != null) sdk.add(_Attr.int('targetSdkVersion', targetSdk));
  if (sdk.isNotEmpty) {
    start('uses-sdk', -1, sdk);
    end('uses-sdk', -1);
  }
  for (final p in permissions) {
    start('uses-permission', -1, [_Attr.str('name', p)]);
    end('uses-permission', -1);
  }
  final app = <_Attr>[];
  if (appLabel != null) app.add(_Attr.str('label', appLabel));
  if (appIcon != null) app.add(_Attr.str('icon', appIcon));
  start('application', -1, app);
  end('application', -1);
  end('manifest', -1);

  final pool = <int>[];
  _u16(pool, 0x0001);
  _u16(pool, 28);
  final datos = <int>[];
  final offs = <int>[];
  for (final st in strings) {
    offs.add(datos.length);
    final by = st.codeUnits;
    _u16(datos, by.length);
    if (by.length < 128) {
      datos.add(by.length);
    } else {
      datos.add(0x80 | (by.length >> 8));
      datos.add(by.length & 0xFF);
    }
    datos.addAll(by);
    datos.add(0);
  }
  final ss = 28 + strings.length * 4;
  _u32(pool, ss + datos.length);
  _u32(pool, strings.length);
  _u32(pool, 0);
  _u32(pool, 1 << 8);
  _u32(pool, ss);
  _u32(pool, 0);
  for (final o in offs) {
    _u32(pool, o);
  }
  pool.addAll(datos);

  final out = <int>[];
  _u16(out, 0x0003);
  _u16(out, 8);
  _u32(out, 8 + pool.length + chunks.length);
  out.addAll(pool);
  out.addAll(chunks);
  return Uint8List.fromList(out);
}

FileModel _archivo(String ruta, {int size = 100}) => FileModel(
      id: ruta,
      path: ruta,
      title: ruta.split('/').last,
      dateCreated: DateTime(2026, 1, 1),
      dateModified: DateTime(2026, 1, 2),
      sizeInBytes: size,
      isFavorite: false,
      isVideo: false,
    );

void main() {
  late FilesController controller;
  late Directory dir;

  setUp(() {
    controller = FilesController();
    dir = Directory.systemTemp.createTempSync('nfiles_apk');
  });

  tearDown(() {
    controller.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  String en(String nombre) => '${dir.path}/$nombre';

  /// Misma razón que en `file_preview_test.dart`: la pantalla lee el disco
  /// en un `await` con E/S real, y bajo el reloj falso hay que envolver el
  /// montaje entero en `runAsync` o el indicador de carga no se va nunca.
  Future<void> montar(WidgetTester tester, FileModel file) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: FilePreviewScreen(file: file, controller: controller),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });
  }

  String apkValido() {
    final path = en('app.apk');
    File(path).writeAsBytesSync(_zip({
      'AndroidManifest.xml': _axml(
        package: 'com.ejemplo.app',
        versionName: '2.0',
        versionCode: 20,
        minSdk: 26,
        targetSdk: 34,
        permissions: const [
          'android.permission.CAMERA',
          'android.permission.INTERNET',
        ],
        appLabel: 'Mi App',
        appIcon: 'res/mipmap-xxxhdpi/ic_launcher.png',
      ),
      'res/mipmap-xxxhdpi/ic_launcher.png': _png1x1,
    }));
    return path;
  }

  group('el inspector dentro de la pantalla', () {
    testWidgets('un APK abre la cabecera con sus datos', (tester) async {
      final path = apkValido();
      await montar(tester, _archivo(path));

      expect(find.byType(NApkHeaderCard), findsOneWidget);
      expect(find.text('Mi App'), findsOneWidget);
      expect(find.text('com.ejemplo.app'), findsOneWidget);
      // Dos veces a propósito: en el subtítulo de la barra y en la pastilla
      // de la cabecera. Si solo saliera una, una de las dos no se pintaría.
      expect(find.text('2.0 (20)'), findsNWidgets(2));
    });

    testWidgets('enseña especificaciones y permisos', (tester) async {
      final path = apkValido();
      await montar(tester, _archivo(path));

      expect(find.byType(NApkInfoSection), findsOneWidget);
      expect(find.text('API 26'), findsOneWidget);
      expect(find.text('API 34'), findsOneWidget);
      expect(find.byType(NApkPermissionsList), findsOneWidget);
      expect(find.text('CAMERA'), findsOneWidget);
      expect(find.text('Sensible'), findsOneWidget);
    });

    testWidgets('un APK roto pinta el motivo', (tester) async {
      final path = en('roto.apk');
      File(path).writeAsBytesSync([1, 2, 3, 4]);
      await montar(tester, _archivo(path));

      expect(find.byType(NApkHeaderCard), findsNothing);
      // En la barra y en el aviso: el motivo se ve sin hacer scroll.
      expect(find.text('No se pudo leer el APK'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('sin icono sale el genérico', (tester) async {
      final path = en('sinicono.apk');
      File(path).writeAsBytesSync(_zip({
        'AndroidManifest.xml': _axml(package: 'com.ejemplo.solo'),
      }));
      await montar(tester, _archivo(path));

      // Hay cabecera pero sin imagen extraída: el genérico ocupa su sitio.
      expect(find.byType(NApkHeaderCard), findsOneWidget);
      expect(find.byIcon(Icons.android), findsOneWidget);
    });

    testWidgets('sin etiqueta se enseña el paquete', (tester) async {
      final path = en('sinlabel.apk');
      File(path).writeAsBytesSync(_zip({
        'AndroidManifest.xml': _axml(package: 'com.ejemplo.sinlabel'),
      }));
      await montar(tester, _archivo(path));

      expect(find.text('com.ejemplo.sinlabel'), findsWidgets);
    });
  });
}
