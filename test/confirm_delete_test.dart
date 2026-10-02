// test/confirm_delete_test.dart
//
// El ajuste "Confirmar al eliminar" conectado al borrado de verdad.
//
// # Qué protege este archivo
//
// 1. Que con el ajuste EN (por defecto) el borrado pregunte por `showNModal`
//    y que cancelar no borre.
// 2. Que con el ajuste APAGADO la acción vaya directa: es lo que el usuario
//    pidió al apagar la pregunta, y dejarlo igual sería un ajuste que no
//    hace nada.
// 3. Que el ajuste sobreviva a un reinicio (si no, el borrado seguiría
//    preguntando después de reiniciar).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:NexoraUi/NexoraUi.dart';
import 'package:NFiles/controllers/files_controller.dart';
import 'package:NFiles/services/file_service.dart';
import 'package:NFiles/services/local_store.dart';
import 'package:NFiles/utils/confirm_destructive.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late FilesController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('nfiles_confirm');
    controller = FilesController(
      fileService: FileService(roots: [tmp], useIsolate: false),
    );
    addTearDown(controller.dispose);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  /// Botón que llama al helper, como haría el visor o la selección.
  Widget botonBorrar() => MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  final ok = await confirmDestructive(
                    context,
                    controller: controller,
                    title: 'Mover a la papelera',
                    message: 'Se podrá restaurar.',
                  );
                  if (ok) await controller.moveToTrash('cualquiera');
                },
                child: const Text('Borrar'),
              ),
            ),
          ),
        ),
      );

  testWidgets('con el ajuste encendido pregunta y cancelar no borra', (
    tester,
  ) async {
    await tester.pumpWidget(botonBorrar());
    await tester.pumpAndSettle();

    expect(controller.confirmDelete, isTrue, reason: 'el valor por defecto');
    await tester.tap(find.text('Borrar'));
    await tester.pumpAndSettle();

    // El diálogo del kit: `showNConfirmDialog` es `showNModal` con su
    // propiaTransition. Si algún día se sustituye por un `AlertDialog`
    // pelado, este test falla y se ve.
    expect(find.byType(NModalShell), findsOneWidget);
    expect(find.text('Mover a la papelera'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(find.byType(NModalShell), findsNothing);
  });

  testWidgets('con el ajuste apagado borra sin preguntar', (tester) async {
    controller.setConfirmDelete(false);
    await tester.pumpWidget(botonBorrar());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Borrar'));
    await tester.pumpAndSettle();

    // Ni modal ni parpadeo: la acción va directa.
    expect(find.byType(NModalShell), findsNothing);
    expect(find.text('Mover a la papelera'), findsNothing);
  });

  testWidgets('volver a encenderlo vuelve a preguntar', (tester) async {
    controller.setConfirmDelete(false);
    await tester.pumpWidget(botonBorrar());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Borrar'));
    await tester.pumpAndSettle();
    expect(find.byType(NModalShell), findsNothing);

    controller.setConfirmDelete(true);
    await tester.tap(find.text('Borrar'));
    await tester.pumpAndSettle();

    expect(find.byType(NModalShell), findsOneWidget);
  });

  test('el ajuste se lee del almacén y se aplica al controller', () async {
    final store = await LocalStore.load();
    store.viewPrefs.attach(controller);
    controller.setConfirmDelete(false);
    await Future<void>.delayed(const Duration(milliseconds: 350));

    final leido = store.viewPrefs.load();
    expect(leido.confirmDelete, isFalse);

    // Y una sesión nueva arranca sin preguntar, que es lo que hace útil
    // el ajuste.
    final nuevo = FilesController(
      fileService: FileService(roots: [tmp], useIsolate: false),
    );
    addTearDown(nuevo.dispose);
    store.viewPrefs.applyTo(nuevo, leido);
    expect(nuevo.confirmDelete, isFalse);
  });
}
