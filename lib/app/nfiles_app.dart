// lib/app/nfiles_app.dart
//
// Contenedor raíz de NFiles: dos destinos y sus topbars.
//
// Móvil primero. La capa de escritorio del kit sigue cableada en
// [NDesktopLayout] pero ya no es el camino principal: se mantiene para no
// perder el trabajo de navegación lateral, no porque sea la experiencia
// actual.
//
// Las dos pantallas tienen lupa y popup, pero el popup es DISTINTO en cada
// una (ver [_recentPopupItems] y [_explorePopupItems]): no es un menú
// genérico, son dos herramientas distintas.
import 'package:flutter/material.dart';
import 'package:NexoraCore/NexoraCore.dart';
import 'package:NexoraUi/NexoraUi.dart';

import '../controllers/files_controller.dart';
import '../services/local_store.dart';
import '../screens/explore/explore_screen.dart';
import '../screens/recent/recent_screen.dart';
import '../screens/settings/nfiles_settings_screen.dart';
import '../widgets/nfiles_popup.dart';

/// Índice del destino de "Recientes" (el inicial).
const int kRecentTab = 0;

/// Índice del destino de "Explorar".
const int kExploreTab = 1;

class NFilesApp extends StatelessWidget {
  final LocalStore? store;
  final CorePermissions permissions;
  final CorePerformance performance;
  final CoreLocale locale;

  /// Controlador ya construido.
  ///
  /// `null` en producción (lo crea la pantalla). Se puede inyectar para
  /// tests: si no, la pantalla escanea el `$HOME` real del proceso y los
  /// tests no son deterministas.
  final FilesController? controller;

  const NFilesApp({
    super.key,
    this.store,
    required this.permissions,
    required this.performance,
    required this.locale,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return NAppShell(
      title: 'NFiles',
      home: NFilesHome(
        store: store,
        permissions: permissions,
        performance: performance,
        locale: locale,
        controller: controller,
      ),
    );
  }
}

/// Destinos de la bottom bar.
const _navItems = [
  NNavigationDestination(
    icon: Icons.history_outlined,
    activeIcon: Icons.history,
    label: 'Recientes',
  ),
  NNavigationDestination(
    icon: Icons.explore_outlined,
    activeIcon: Icons.explore,
    label: 'Explorar',
  ),
];

class NFilesHome extends StatefulWidget {
  final LocalStore? store;
  final CorePermissions permissions;
  final CorePerformance performance;
  final CoreLocale locale;

  /// Ver [NFilesApp.controller].
  final FilesController? controller;

  const NFilesHome({
    super.key,
    this.store,
    required this.permissions,
    required this.performance,
    required this.locale,
    this.controller,
  });

  @override
  State<NFilesHome> createState() => _NFilesHomeState();
}

class _NFilesHomeState extends State<NFilesHome> with WidgetsBindingObserver {
  int _selectedIndex = kRecentTab;

  /// Controlador único para toda la app: ambas pantallas leen los mismos
  /// archivos, así que un solo escaneo los alimenta a las dos.
  late final FilesController _controller;

  /// `true` si el controlador lo trajo la app (inyectado): entonces no
  /// lo destruimos al salir, porque su dueño es quien lo creó.
  bool get _ownsController => widget.controller == null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = widget.controller ?? FilesController();
    // Si nos pasan un controlador ya cargado no lo re-escaneamos: sus
    // datos son tan válidos como los que acabaríamos de leer, y un
    // segundo escaneo solo provocaría un parpadeo de carga.
    if (_controller.state != FilesState.loaded) {
      _controller.fetchFiles();
    }
    // Recarga dinámica: los archivos nuevos aparecen solos, sin recompilar.
    _controller.startWatching();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al volver del fondo puede haber archivos nuevos (descargas, cámara).
    if (state == AppLifecycleState.resumed) {
      _controller.refresh();
    }
  }

  void _openSettings() {
    pushNPage(
      context,
      NFilesSettingsScreen(
        permissions: widget.permissions,
        locale: widget.locale,
        performance: widget.performance,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isRecent = _selectedIndex == kRecentTab;

    return NMobileLayout(
      title: 'NFiles',
      // `pages` (no `body`): el drag sobre la bottom bar desplaza las
      // pantallas con snap y no reinicia cada destino al volver a él.
      pages: [
        RecentScreen(controller: _controller),
        ExploreScreen(controller: _controller),
      ],
      currentIndex: _selectedIndex,
      onNavigationIndexChanged: (i) => setState(() => _selectedIndex = i),
      navigationItems: _navItems,
      onRefresh: _controller.refresh,
      onSearchChanged: _controller.setSearchQuery,
      onSearchClosed: () => _controller.setSearchQuery(''),
      searchHint: isRecent ? 'Buscar archivos' : 'Buscar en Explorar',
      // El popup depende de la pantalla activa: no es un menú único.
      extraPopupMenuItems: isRecent
          ? buildRecentPopupItems(context, _controller, _openSettings)
          : buildExplorePopupItems(_controller),
      extraActions: [const _TransferAction(), const _SpaceAction()],
    );
  }
}

/// Acción de la topbar: transferir archivos.
///
/// Contrato declarado, sin backend todavía: la fila de "Transferencias"
/// del popup es el sitio donde enchufar la cola real. Se muestra el estado
/// vacío en vez de un botón que no hace nada.
class _TransferAction extends StatelessWidget {
  const _TransferAction();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.swap_vert_circle_outlined),
      tooltip: 'Transferir archivos',
      onPressed: () => _showPending(context),
    );
  }

  void _showPending(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Transferencias: sin cola activa')),
      );
  }
}

/// Acción de la topbar: espacio usado.
class _SpaceAction extends StatelessWidget {
  const _SpaceAction();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.storage_outlined),
      tooltip: 'Espacio',
      onPressed: () => showNSheet(
        context,
        backgroundColor: Theme.of(context).colorScheme.surface,
        child: const _SpaceSheet(),
      ),
    );
  }
}

/// Hoja de espacio: lo ocupado por la app, con el total real del escaneo.
class _SpaceSheet extends StatelessWidget {
  const _SpaceSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(NSpacing.spaceMd),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const NSheetHandle(),
            const SizedBox(height: NSpacing.spaceMd),
            const NSheetTitle('Espacio'),
            const SizedBox(height: NSpacing.spaceMd),
            NCloudStorageCard(
              usedGb: 0,
              totalGb: 0,
              appsUsage: const [],
            ),
            const SizedBox(height: NSpacing.spaceMd),
            Text(
              'Los totales por categoría se calculan sobre el escaneo '
              'completo; se rellenan al indexar el dispositivo.',
              style: TextStyle(
                fontFamily: NTypography.fontFamilyBase,
                fontSize: NTypography.sizeXs,
                color: context.nMutedTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
