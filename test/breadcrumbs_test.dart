// test/breadcrumbs_test.dart
//
// El breadcrumb del explorador.
//
// # Qué protege este archivo
//
// 1. Que el parser de rutas divida bien y ACUMULE las rutas absolutas.
// 2. Que el primer segmento lleve etiqueta de almacenamiento sin que eso
//    cambie la ruta a la que salta.
// 3. Que pulsar un ancestro devuelva su ruta, y que el actual no sea
//    pulsable.
// 4. Que el scroll se vaya solo al extremo derecho al cambiar de carpeta.
//
// # Por qué el parser se prueba sin widget
//
// La lógica es aritmética de cadenas. Probarla a través de un widget obliga
// a montar un `MaterialApp`, fijar un ancho y pedir varios `pump`, y cuando
// falla el error es "no encuentro el texto", que no dice nada. Con la función
// suelta, el fallo dice exactamente qué ruta salió mal.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:NFiles/widgets/breadcrumbs_bar.dart';

void main() {
  // ── El parser ─────────────────────────────────────────────────────────

  group('parseBreadcrumbs', () {
    test('divide una ruta de Android en sus segmentos', () {
      final crumbs = parseBreadcrumbs('/storage/emulated/0/Download/PDFs');
      // Sin mapa de etiquetas no se inventa ninguna: `storage` no es la
      // raíz, es una carpeta, y llamarla "Raíz" sería mentir.
      expect(crumbs.map((c) => c.label).toList(),
          ['storage', 'emulated', '0', 'Download', 'PDFs']);
      // El último es el actual y el resto no.
      expect(crumbs.last.isCurrent, isTrue);
      expect(crumbs.where((c) => c.isCurrent).length, 1);
    });

    test('cada segmento lleva su ruta ABSOLUTA acumulada', () {
      // Esto es lo que evita tener que recombinar nada en quien recibe el
      // callback: si un segmento devolviera "0" suelto, la app no podría
      // abrir nada.
      final crumbs = parseBreadcrumbs('/storage/emulated/0/Download/PDFs');
      expect(crumbs.map((c) => c.path).toList(), [
        '/storage',
        '/storage/emulated',
        '/storage/emulated/0',
        '/storage/emulated/0/Download',
        '/storage/emulated/0/Download/PDFs',
      ]);
    });

    test('la ruta de la misión, sus tres predecesores y sus rutas', () {
      // El caso que la misión fija textualmente. Sin mapa de etiquetas, la
      // ruta se ve entera: `Download` es el cuarto chip y `/storage/emulated/0`
      // el tercero. Es el caso con el que el widget se ve "crudo", y el mapa
      // de etiquetas lo convierte en una versión legible.
      final crumbs = parseBreadcrumbs('/storage/emulated/0/Download/PDFs');
      expect(crumbs[2].path, '/storage/emulated/0');
      expect(crumbs[3].label, 'Download');
      expect(crumbs[3].path, '/storage/emulated/0/Download');
      expect(crumbs[4].path, '/storage/emulated/0/Download/PDFs');
    });

    test('la raíz sola es un único segmento', () {
      final crumbs = parseBreadcrumbs('/');
      expect(crumbs.length, 1);
      expect(crumbs.single.label, kBreadcrumbFallbackRoot);
      expect(crumbs.single.path, '/');
      expect(crumbs.single.isCurrent, isTrue);
    });

    test('una ruta vacía no produce segmentos', () {
      // El widget usa esto para no dibujar nada. Si devolviera un segmento
      // vacío, se vería un chip sin etiqueta.
      expect(parseBreadcrumbs(''), isEmpty);
    });

    test('ignora las barras finales y las dobles', () {
      // `/a/b/` y `/a//b` son la misma carpeta que `/a/b`. Si apareciera un
      // segmento vacío en medio, el breadcrumb mostraría un separador sin
      // nada entre medias.
      final a = parseBreadcrumbs('/a/b');
      expect(parseBreadcrumbs('/a/b/').map((c) => c.path).toList(),
          a.map((c) => c.path).toList());
      expect(parseBreadcrumbs('/a//b').map((c) => c.path).toList(),
          a.map((c) => c.path).toList());
    });

    test('resuelve "." y ".." a la ruta real', () {
      // `..` no se descarta: retrocede de verdad. Si solo se ignorara, el
      // segmento quedaría apuntando a una carpeta que no es la que se ve, y
      // el callback devolvería una ruta que abre otra cosa.
      final crumbs = parseBreadcrumbs('/a/b/../c');
      expect(crumbs.map((c) => c.path).toList(), ['/a', '/a/c']);
      expect(parseBreadcrumbs('/a/./b').map((c) => c.path).toList(),
          ['/a', '/a/b']);
    });

    test('un ".." de más no inventa segmentos por encima de la raíz', () {
      // `/../a` es `/a`. Un `..` que se aplicara sin mirar la pila dejaría
      // un breadcrumb que empieza por algo que no existe.
      expect(parseBreadcrumbs('/../a').map((c) => c.path).toList(), ['/a']);
      expect(parseBreadcrumbs('/..').single.path, '/');
    });

    test('una ruta solo de ".." degenera en la raíz', () {
      expect(parseBreadcrumbs('/../..').single.path, '/');
    });
  });

  group('la etiqueta de la raíz', () {
    const labels = {
      '/storage/emulated/0': 'Almacenamiento interno',
      '/storage/1234-5678': 'Tarjeta SD',
    };

    test('el prefijo etiquetado REEMPLAZA a sus segmentos internos', () {
      final crumbs = parseBreadcrumbs(
        '/storage/emulated/0/Download/PDFs',
        rootLabels: labels,
      );
      // `storage`, `emulated` y `0` no aparecen: el nombre del
      // almacenamiento los resume. Dejarlos a la vista daría
      // "Almacenamiento interno › emulated", que es peor que no etiquetar.
      expect(crumbs.map((c) => c.label).toList(),
          ['Almacenamiento interno', 'Download', 'PDFs']);
    });

    test('la etiqueta NO cambia la ruta a la que salta', () {
      // Lo importante de este caso: si la etiqueta sustituyera a la ruta, el
      // callback devolvería "Almacenamiento interno" y no habría forma de
      // abrir nada. El primer chip salta al PREFIJO completo, no al primer
      // segmento.
      final crumbs = parseBreadcrumbs(
        '/storage/emulated/0/Download/PDFs',
        rootLabels: labels,
      );
      expect(crumbs.first.path, '/storage/emulated/0');
      expect(crumbs[1].path, '/storage/emulated/0/Download');
    });

    test('sin entrada en el mapa el primer chip conserva su nombre', () {
      // `/storage` no es la raíz del sistema de archivos, así que no puede
      // llamarse "Raíz". La etiqueta de reserva es para la raíz de verdad.
      final crumbs = parseBreadcrumbs(
        '/home/user',
        rootLabels: const {'/otra/cosa': 'Nada que ver'},
      );
      expect(crumbs.first.label, 'home');
      expect(crumbs.first.path, '/home');
    });

    test('la etiqueta de reserva es para la raíz REAL', () {
      // `/` no tiene ningún nombre que enseñar, así que ahí sí se usa la
      // reserva. En cualquier otra ruta el primer chip conserva su nombre.
      expect(parseBreadcrumbs('/', rootLabels: labels).single.label,
          kBreadcrumbFallbackRoot);
      expect(parseBreadcrumbs('/home/user/fotos', rootLabels: labels)
          .first.label, 'home');
    });

    test('la etiqueta de reserva se puede cambiar', () {
      expect(
        parseBreadcrumbs('/', fallbackRootLabel: 'Este dispositivo')
            .single.label,
        'Este dispositivo',
      );
    });

    test('la raíz también puede venir nombrada por el mapa', () {
      // El mapa puede incluir la entrada "/" explícitamente, que es lo que
      // haría una app que quiere llamar "Este dispositivo" a la raíz.
      final crumbs = parseBreadcrumbs(
        '/a',
        rootLabels: const {'/': 'Este dispositivo'},
      );
      expect(crumbs.first.label, 'Este dispositivo');
      expect(crumbs.first.path, '/');
    });

    test('gana el prefijo MÁS LARGO, no el primero que aparece', () {
      // Los prefijos se solapan en Android: `/storage/emulated/0` y
      // `/storage/emulated/0/Android/data` pueden estar los dos. Si ganara el
      // que se insertó primero, una partición de aplicación se mostraría como
      // "Almacenamiento interno", que es información falsa.
      final crumbs = parseBreadcrumbs(
        '/storage/emulated/0/Android/data/com.app/files',
        rootLabels: const {
          '/storage/emulated/0': 'Almacenamiento interno',
          '/storage/emulated/0/Android/data': 'Datos de aplicaciones',
        },
      );
      expect(crumbs.first.label, 'Datos de aplicaciones');
    });

    test('un prefijo con barra final se comporta igual', () {
      // Escribir la clave con barra final es el error tipográfico más fácil
      // de cometer al armar el mapa, y sin normalizar la etiqueta se pierde
      // en silencio.
      final a = parseBreadcrumbs('/storage/emulated/0/Download',
          rootLabels: const {'/storage/emulated/0': 'Interno'});
      final b = parseBreadcrumbs('/storage/emulated/0/Download',
          rootLabels: const {'/storage/emulated/0/': 'Interno'});
      expect(a.first.label, 'Interno');
      expect(a.first.label, b.first.label);
      expect(a.first.path, b.first.path);
      // Y la etiqueta no se come el segmento siguiente: `Download` sigue
      // estando, que es justo lo que la distingue de "primer chip renombrado".
      expect(a.last.label, 'Download');
    });

    test('un prefijo que NO es ancestro no se aplica', () {
      // `/storage` no es ancestro de `/home`, así que no puede etiquetar esa
      // ruta. Si se aplicara por "empieza por", mostraría "Almacenamiento
      // interno" sobre una carpeta de usuario. Y como no hay entrada que
      // valga, el primer chip conserva su nombre real.
      final crumbs = parseBreadcrumbs(
        '/home/user',
        rootLabels: const {'/storage': 'Almacenamiento interno'},
      );
      expect(crumbs.first.label, 'home');
      expect(crumbs.first.path, '/home');
    });
  });

  // ── El widget ─────────────────────────────────────────────────────────

  /// Ancho POR DEFECTO amplio, para que todo el breadcrumb quepa.
  ///
  /// Con un viewport estrecho, `tester.tap` sobre un chip que queda fuera de
  /// la ventana falla con "would not hit test on the specified widget" y el
  /// error no dice nada del breadcrumb. Los tests de desplazamiento usan
  /// [wrapEstrecho], que es donde el desborde es lo que se quiere medir.
  Widget wrap(Widget child, {double width = 800}) => MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: child),
          ),
        ),
      );

  /// Ancho estrecho a propósito: obliga a que la fila desborde y el
  /// desplazamiento horizontal sea real, que es lo que hay que medir.
  Widget wrapEstrecho(Widget child, {double width = 200}) => MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: child),
          ),
        ),
      );

  group('BreadcrumbsBar', () {
    testWidgets('dibuja un chip por segmento, con el actual destacado',
        (tester) async {
      await tester.pumpWidget(wrap(const BreadcrumbsBar(
        path: '/storage/emulated/0/Download/PDFs',
        onDirectorySelected: _ignore,
      )));
      await tester.pump();

      expect(find.text('storage'), findsOneWidget);
      expect(find.text('emulated'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);
      expect(find.text('PDFs'), findsOneWidget);
      // Un separador menos que segmentos.
      expect(find.byIcon(Icons.chevron_right), findsNWidgets(4));
    });

    testWidgets('el segmento actual NO es pulsable', (tester) async {
      final pulsados = <String>[];
      await tester.pumpWidget(wrap(BreadcrumbsBar(
        path: '/storage/emulated/0/Download/PDFs',
        onDirectorySelected: pulsados.add,
      )));
      await tester.pump();

      // Pulsarlo no debe llamar al callback: la app ya está ahí, y recargar
      // sin motivo en un gestor de archivos es un salto de scroll al
      // principio de la lista.
      await tapVisible(tester, 'PDFs');
      expect(pulsados, isEmpty);
    });

    testWidgets('pulsar un ancestro llama con SU ruta absoluta',
        (tester) async {
      final pulsados = <String>[];
      await tester.pumpWidget(wrap(BreadcrumbsBar(
        path: '/storage/emulated/0/Download/PDFs',
        onDirectorySelected: pulsados.add,
      )));
      await tester.pump();

      await tapVisible(tester, 'Download');
      expect(pulsados, ['/storage/emulated/0/Download']);
    });

    testWidgets('el caso exacto de la misión, con etiqueta de raíz',
        (tester) async {
      final pulsados = <String>[];
      await tester.pumpWidget(wrap(BreadcrumbsBar(
        path: '/storage/emulated/0/Download/PDFs',
        onDirectorySelected: pulsados.add,
        rootLabels: const {
          '/storage/emulated/0': 'Almacenamiento interno',
        },
      )));
      await tester.pump();

      // Con el mapa de etiquetas los chips visibles son cuatro, no cinco:
      // "storage", "emulated" y "0" quedan reagrupados en "Almacenamiento
      // interno". El segundo chip es "Download".
      expect(find.text('Almacenamiento interno'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);
      expect(find.text('PDFs'), findsOneWidget);
      expect(find.text('storage'), findsNothing,
          reason: 'la raíz etiquetada sustituye a sus segmentos internos');

      // Y el segundo chip devuelve la ruta absoluta correcta.
      await tapVisible(tester, 'Download');
      expect(pulsados, ['/storage/emulated/0/Download']);
    });

    testWidgets('cualquier ancestro salta a su carpeta', (tester) async {
      final pulsados = <String>[];
      await tester.pumpWidget(wrap(BreadcrumbsBar(
        path: '/a/b/c/d/e',
        onDirectorySelected: pulsados.add,
      )));
      await tester.pump();

      await tapVisible(tester, 'b');
      await tapVisible(tester, 'd');
      expect(pulsados, ['/a/b', '/a/b/c/d']);
    });

    testWidgets('la raíz con etiqueta de almacenamiento es pulsable',
        (tester) async {
      final pulsados = <String>[];
      await tester.pumpWidget(wrap(BreadcrumbsBar(
        path: '/storage/emulated/0/Download',
        onDirectorySelected: pulsados.add,
        rootLabels: const {
          '/storage/emulated/0': 'Almacenamiento interno',
        },
      )));
      await tester.pump();

      // Se ve el nombre, pero lo que vuelve es la ruta física completa del
      // almacenamiento. Si devolviera la etiqueta, o solo `/storage`, la
      // app abriría la carpeta equivocada.
      await tapVisible(tester, 'Almacenamiento interno');
      expect(pulsados, ['/storage/emulated/0']);
    });

    testWidgets('una ruta vacía no dibuja nada', (tester) async {
      await tester.pumpWidget(wrap(const BreadcrumbsBar(
        path: '',
        onDirectorySelected: _ignore,
      )));
      await tester.pump();

      expect(find.byType(Text), findsNothing);
      expect(find.byType(Scrollbar), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('la raíz sola se dibuja y no rompe', (tester) async {
      await tester.pumpWidget(wrap(const BreadcrumbsBar(
        path: '/',
        onDirectorySelected: _ignore,
      )));
      await tester.pump();

      expect(find.text(kBreadcrumbFallbackRoot), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('el desplazamiento automático', () {
    testWidgets('al empezar ya está al extremo derecho', (tester) async {
      // Un viewport de 200 px con una ruta de cinco segmentos desborda con
      // gusto, así que hay recorrido real que medir.
      await tester.pumpWidget(wrapEstrecho(const BreadcrumbsBar(
        path: '/storage/emulated/0/Download/PDFs/documentos/proyectos',
        onDirectorySelected: _ignore,
      )));
      await tester.pump();
      // El salto va en un post-frame con animación de 240 ms.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final scrollable = find.byType(Scrollable).first;
      final state = tester.state<ScrollableState>(scrollable);
      final position = state.position;
      expect(position.maxScrollExtent, greaterThan(0),
          reason: 'sin esto el test no midría nada: todo cabría');
      expect(position.pixels, closeTo(position.maxScrollExtent, 1.0),
          reason: 'la carpeta actual tiene que quedar visible de inmediato');
    });

    testWidgets('bajar a una carpeta más larga vuelve al extremo',
        (tester) async {
      await tester.pumpWidget(wrapEstrecho(const BreadcrumbsBar(
        path: '/a',
        onDirectorySelected: _ignore,
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // El usuario deja la barra a la izquierda para leer el ancestro.
      final state =
          tester.state<ScrollableState>(find.byType(Scrollable).first);
      state.position.jumpTo(0);
      await tester.pump();
      expect(state.position.pixels, 0);

      // Y al descender, la barra se recoloca sola.
      await tester.pumpWidget(wrapEstrecho(const BreadcrumbsBar(
        path: '/a/una/carpeta/muy/larga/que/hace/seguir/creciendo',
        onDirectorySelected: _ignore,
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(state.position.pixels, closeTo(state.position.maxScrollExtent, 1.0));
    });

    testWidgets('con autoScrollToEnd desactivado no se mueve solo',
        (tester) async {
      // El interruptor tiene que existir de verdad: si no, no hay forma de
      // tener un breadcrumb que no salte al final.
      await tester.pumpWidget(wrapEstrecho(const BreadcrumbsBar(
        path: '/storage/emulated/0/Download/PDFs/documentos/proyectos',
        onDirectorySelected: _ignore,
        autoScrollToEnd: false,
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final state =
          tester.state<ScrollableState>(find.byType(Scrollable).first);
      expect(state.position.pixels, 0);
    });

    testWidgets('no repite la animación en cada rebuild', (tester) async {
      await tester.pumpWidget(wrapEstrecho(const BreadcrumbsBar(
        path: '/storage/emulated/0/Download/PDFs/documentos/proyectos',
        onDirectorySelected: _ignore,
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final state =
          tester.state<ScrollableState>(find.byType(Scrollable).first);
      // El watcher de archivos emite notifyListeners cada segundo. Si cada
      // uno reiniciara la animación, la barra parpadearía de forma visible.
      state.position.jumpTo(0);
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.pumpWidget(wrapEstrecho(const BreadcrumbsBar(
          path: '/storage/emulated/0/Download/PDFs/documentos/proyectos',
          onDirectorySelected: _ignore,
        )));
        await tester.pump();
      }
      expect(state.position.pixels, 0,
          reason: 'misma ruta, no debe volver a empujar al final');
    });
  });
}

/// Callback que no hace nada, para los tests que no miden la pulsación.
void _ignore(String path) {}

/// Pulsa un chip llevándolo antes a la vista.
///
/// Sin esto, `tester.tap` sobre un chip fuera del viewport falla con
/// "would not hit test on the specified widget", un error que no dice nada
/// del breadcrumb. Y el caso es real, no un artefacto del test: una ruta de
/// cinco segmentos mide unos 1.100 px, así que en cualquier pantalla estrecha
/// el chip de la derecha no se ve y hay que desplazar la barra para llegar a
/// él. El test hace lo mismo que el usuario.
Future<void> tapVisible(WidgetTester tester, String label) async {
  final finder = find.text(label);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}
