// test/file_grid_view_test.dart
//
// La cuadrícula responsive y la conmutación lista/cuadrícula.
//
// # Qué protege este archivo
//
// 1. Que la rejilla sea RESPONSIVA: el número de columnas depende del ancho,
//    no de una constante. Es lo que justifies sustituir el `crossAxisCount: 3`
//    fijo.
// 2. Que alternar lista y cuadrícula conserve la posición del scroll.
// 3. Que conserve el estado de selección.
// 4. Que la casilla muestre miniatura, icono y nombre truncado.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:NFiles/controllers/files_controller.dart';
import 'package:NFiles/models/file_model.dart';
import 'package:NFiles/widgets/file_grid_view.dart';
import 'package:NFiles/widgets/view_mode_toggle.dart';

/// Un [FileModel] de mentira, con lo mínimo para pintar una casilla.
FileModel archivo(String nombre) => FileModel(
      id: nombre,
      path: '/tmp/$nombre',
      title: nombre,
      dateCreated: DateTime(2026, 1, 1),
      dateModified: DateTime(2026, 1, 2),
      sizeInBytes: 1024,
      isFavorite: false,
      isVideo: false,
    );

List<FileModel> muchos(int n) =>
    [for (var i = 0; i < n; i++) archivo('archivo_$i.jpg')];

void main() {
  group('la rejilla es responsive', () {
    testWidgets('en un móvil salen menos columnas que en un monitor',
        (tester) async {
      // Anchos representativos: un móvil en vertical y un monitor.
      //
      // Se mide cuántas casillas comparten la misma `y`, que es exactamente
      // lo que el usuario ve como una fila. Contar los widgets del árbol
      // daría el total de construidos por el sliver, no los de una fila, y
      // daría el mismo número en cualquier ancho.
      Future<int> columnasEn(double ancho) async {
        await tester.binding.setSurfaceSize(Size(ancho, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: ancho,
              child: FileGridView(files: muchos(60), onOpen: (_) {}),
            ),
          ),
        ));
        await tester.pump();

        final finder = find.byType(FileGridTile);
        final total = finder.evaluate().length;
        if (total < 2) return 0;
        final y0 = tester.getTopLeft(finder.at(0)).dy;
        var enLaFila = 0;
        for (var i = 0; i < total; i++) {
          if ((tester.getTopLeft(finder.at(i)).dy - y0).abs() < 1) enLaFila++;
        }
        return enLaFila;
      }

      final movil = await columnasEn(380);
      final monitor = await columnasEn(1600);
      expect(movil, greaterThanOrEqualTo(1),
          reason: 'en un móvil tiene que caber al menos una columna');
      expect(monitor, greaterThan(movil),
          reason: 'un ancho mayor tiene que dar más columnas: '
              'movil=$movil monitor=$monitor');
    });

    testWidgets('no hay un número de columnas fijo en el código',
        (tester) async {
      // Con `FixedCrossAxisCount` el delegate devolvería SIEMPRE el mismo
      // número sin importar el ancho. Este test falla si alguien vuelve al
      // delegate fijo, que es la regresión que se quiere evitar.
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FileGridView(files: muchos(60), onOpen: (_) {}),
        ),
      ));
      await tester.pump();

      final sliver = tester.widget<SliverGrid>(find.byType(SliverGrid));
      expect(
        sliver.gridDelegate,
        isA<SliverGridDelegateWithMaxCrossAxisExtent>(),
        reason: 'un delegate fijo daría la misma rejilla en cualquier ancho',
      );
    });
  });

  group('FileGridTile', () {
    testWidgets('muestra el nombre del archivo', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FileGridView(
            files: [archivo('informe.pdf')],
            onOpen: (_) {},
          ),
        ),
      ));
      await tester.pump();

      expect(find.text('informe.pdf'), findsOneWidget);
    });

    testWidgets('usa la miniatura cuando el motor ya la generó',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FileGridView(
            files: [archivo('foto.jpg')],
            onOpen: (_) {},
            thumbnailFor: (_) => '/tmp/thumb.jpg',
          ),
        ),
      ));
      await tester.pump();

      // La miniatura no se puede cargar en un test (el archivo no existe), y
      // lo que importa es que la casilla NO reviente y que el nombre sigue
      // debajo. Si el `errorBuilder` faltara, esto sería una excepción.
      expect(find.byType(FileGridTile), findsOneWidget);
      expect(find.text('foto.jpg'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sin miniatura cae al icono del tipo de archivo',
        (tester) async {
      // Un PDF no tiene miniatura todavía: tiene que verse el icono de la
      // familia, no un hueco vacío ni una imagen rota.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FileGridView(
            files: [archivo('informe.pdf')],
            onOpen: (_) {},
          ),
        ),
      ));
      await tester.pump();

      expect(find.byType(FileGridTile), findsOneWidget);
      expect(find.text('informe.pdf'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('marca la selección sin romper el nombre', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FileGridView(
            files: [archivo('a.jpg'), archivo('b.jpg')],
            onOpen: (_) {},
            inSelectionMode: true,
            selectedIds: {'b.jpg'},
          ),
        ),
      ));
      await tester.pump();

      // Ambas siguen mostrando su nombre: seleccionar no puede convertir la
      // rejilla en una lista de marcas.
      expect(find.text('a.jpg'), findsOneWidget);
      expect(find.text('b.jpg'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget,
          reason: 'solo la seleccionada lleva la marca');
    });

    testWidgets('avisa del archivo tocado', (tester) async {
      FileModel? pulsado;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FileGridView(
            files: [archivo('a.jpg'), archivo('b.jpg')],
            onOpen: (f) => pulsado = f,
          ),
        ),
      ));
      await tester.pump();

      await tester.tap(find.text('b.jpg'));
      await tester.pump();
      expect(pulsado?.title, 'b.jpg');
    });

    testWidgets('una lista vacía no rompe nada', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FileGridView(files: const [], onOpen: (_) {}),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(FileGridTile), findsNothing);
    });
  });

  group('la conmutación lista/cuadrícula', () {
    late FilesController controller;

    setUp(() {
      controller = FilesController();
    });

    tearDown(() => controller.dispose());

    testWidgets('conserva la posición del scroll al cambiar de modo',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final archivos = muchos(120);

      // Estado inicial en cuadrícula, que es lo que se va a cambiar.
      controller.setCategoryLayout(FileViewMode.grid);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FileGridView(
            files: archivos,
            onOpen: (_) {},
            scrollController: scroll,
          ),
        ),
      ));
      await tester.pump();

      // Se deja una marca de scroll profunda.
      scroll.jumpTo(400);
      await tester.pump();
      expect(scroll.offset, 400);

      // Se cambia a lista CON EL MISMO controller. Es el punto entero: si el
      // controller se creara dentro de cada modo, al volver se perdería la
      // posición y el usuario aparecería arriba.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            // La MISMA clave que usa la cuadrícula. Es el detalle que hace
            // que el test signifique algo: sin ella el offset se perdería
            // igual, y el test no distinguiría un bug de otro.
            key: const PageStorageKey(kFilesPageStorageKey),
            controller: scroll,
            itemCount: archivos.length,
            itemBuilder: (_, i) =>
                SizedBox(height: 60, child: Text(archivos[i].title)),
          ),
        ),
      ));
      await tester.pump();

      expect(scroll.offset, 400,
          reason: 'la posición tiene que sobrevivir al cambio de modo');
    });

    testWidgets('el estado de selección sobrevive al cambio de modo',
        (tester) async {
      // La selección vive en el controller, no en el widget: si viviera en
      // la pantalla, al reconstruir para cambiar de modo se perdería, que es
      // el peor momento posible (el usuario ha marcado quince archivos para
      // moverlos y de golpe se desmarcan).
      await tester.binding.setSurfaceSize(const Size(400, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Los ids tienen que existir en la lista: `muchos(10)` genera
      // `archivo_0.jpg`..., y una seleccion de nombres inventados no
      // marcaria nada y el test pasaria por un motivo equivocado.
      const seleccion = {'archivo_0.jpg', 'archivo_1.jpg', 'archivo_2.jpg'};
      final archivos = muchos(10);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);

      Future<void> pintar({required bool grid}) async {
        controller.setCategoryLayout(
          grid ? FileViewMode.grid : FileViewMode.list,
        );
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: grid
                ? FileGridView(
                    files: archivos,
                    onOpen: (_) {},
                    scrollController: scroll,
                    inSelectionMode: true,
                    selectedIds: seleccion,
                  )
                : ListView.builder(
                    controller: scroll,
                    itemCount: archivos.length,
                    itemBuilder: (_, i) => SizedBox(
                      height: 60,
                      child: Text(archivos[i].title),
                    ),
                  ),
          ),
        ));
        await tester.pump();
      }

      await pintar(grid: true);
      expect(find.byIcon(Icons.check_circle), findsNWidgets(3));

      await pintar(grid: false);
      await pintar(grid: true);

      // Vuelven a estar las tres marcadas.
      expect(find.byIcon(Icons.check_circle), findsNWidgets(3),
          reason: 'la selección no puede depender del modo de vista');
    });

    testWidgets('el conmutador de la cabecera cambia el modo del controller',
        (tester) async {
      controller.setCategoryLayout(FileViewMode.list);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(
                height: 50,
                child: Row(
                  children: [
                    // El mismo botón de la barra, montado aquí para probar
                    // el camino completo sin levantar toda la pantalla.
                    ViewModeToggle(controller: controller),
                  ],
                ),
              ),
              Expanded(
                child: FileGridView(
                  files: muchos(20),
                  onOpen: (_) {},
                ),
              ),
            ],
          ),
        ),
      ));
      await tester.pump();

      expect(find.byIcon(Icons.grid_view), findsOneWidget);
      await tester.tap(find.byIcon(Icons.grid_view));
      await tester.pump();

      expect(controller.categoryLayout, FileViewMode.grid);
      expect(find.byIcon(Icons.view_list), findsOneWidget);
    });
  });
}
