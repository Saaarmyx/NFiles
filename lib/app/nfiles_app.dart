// lib/app/nfiles_app.dart
//
// Contenedor raíz de NFiles: dos destinos y sus topbars.
//
// Móvil primero. La capa de escritorio del kit sigue cableada en
// [NDesktopLayout] pero ya no es el camino principal: se mantiene para no
// perder el trabajo de navegación lateral, no porque sea la experiencia
// actual.
//
// Cada pantalla tiene SU topbar: Recientes (nombre + lupa + popup de vista
// y ajustes) y Explorar (nombre + popup de vista/orden + ajustes). El popup
// es DISTINTO en cada una (ver [buildRecentPopupItems] y
// [buildExplorePopupItems]): no es un menú genérico, son dos herramientas
// distintas.
import 'package:flutter/material.dart';
import 'package:NexoraCore/NexoraCore.dart';
import 'package:NexoraUi/NexoraUi.dart';

import '../controllers/files_controller.dart';
import '../services/local_store.dart';
import '../screens/explore/explore_screen.dart';
import '../screens/recent/recents_screen.dart';
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
    // El popup se lee del almacén antes de que la UI se suscriba, y a
    // partir de ahí se guarda solo en cada cambio.
    widget.store?.applyViewPreferences(_controller);
    // Arranque instantáneo: primero la BD local (<50ms, sin disco) y el
    // espacio vía `statvfs` (µs); el diff incremental por `mtime` corre
    // después en segundo plano sin `loading` ni parpadeo.
    if (_controller.state != FilesState.loaded) {
      _controller.hydrateFromCache().then((_) {
        if (!mounted) return;
        // Si la hidratación llenó la grilla, solo sincroniza lo cambiado;
        // si no (primer arranque), escaneo completo como antes.
        if (_controller.files.isNotEmpty) {
          _controller.syncIncrementalBackground();
        } else {
          _controller.fetchFiles();
        }
      });
    } else {
      _controller.loadStorage();
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
        // Los ajustes de archivos cuelgan del mismo controller que ya
        // tiene el layout: es el que guarda y el que lee en cada fila.
        controller: _controller,
      ),
    );
  }

  void _openAccount() {
    // La cuenta vive en NCloud desde que su pantalla tiene sitio propio
    // (perfil, cuota, recomendaciones y apps). `NAccountScreen` ya no
    // existe en el kit: era el mismo contenido con otro nombre.
    pushNPage(
      context,
      NCloudScreen(profile: nFilesProfileData),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isRecent = _selectedIndex == kRecentTab;

    return NMobileLayout(
      // Título por destino: izquierda el nombre de la pantalla activa.
      title: isRecent ? 'Recientes' : 'Explorar',
      // `pages` (no `body`): el drag sobre la bottom bar desplaza las
      // pantallas con snap y no reinicia cada destino al volver a él.
      pages: [
        RecentsScreen(controller: _controller),
        ExploreScreen(controller: _controller),
      ],
      currentIndex: _selectedIndex,
      onNavigationIndexChanged: (i) => setState(() => _selectedIndex = i),
      navigationItems: _navItems,
      onRefresh: _controller.refresh,
      // Recientes: lupa para buscar archivos. Explorar: sin búsqueda.
      onSearchChanged: isRecent ? _controller.setSearchQuery : null,
      onSearchClosed: isRecent ? () => _controller.setSearchQuery('') : null,
      searchHint: 'Buscar archivos',
      // Explorar: acceso directo a ajustes. Recientes lo lleva en el popup.
      onSettingsPressed: isRecent ? null : _openSettings,
      // El popup depende de la pantalla activa: no es un menú único.
      extraPopupMenuItems: isRecent
          ? buildRecentPopupItems(
              _controller,
              _openAccount,
              _openSettings,
            )
          : buildExplorePopupItems(_controller),
    );
  }
}
