# NFiles

> Explorador de archivos de Nexora Labs — capa de UI migrada desde NPhotos, con escaneo local, bóveda privada y visor multimedia.

![Flutter](https://img.shields.io/badge/Flutter-3.47.5-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.13.4-0175C2?logo=dart&logoColor=white)
![Version](https://img.shields.io/badge/version-26.09.28--release-blue)
![License](https://img.shields.io/badge/license-Proprietary-red)
![Android](https://img.shields.io/badge/platform-Android-3DDC84?logo=android&logoColor=white)
![Linux](https://img.shields.io/badge/platform-Linux-FCC624?logo=linux&logoColor=black)

## 1. Propósito e Integración

**Responsabilidad única (SRP):** NFiles es la app de exploración y gestión de archivos locales del ecosistema Nexora. Escanea, clasifica, previsualiza y organiza archivos del dispositivo. No contiene Design System ni lógica de dominio genérica: los delega.

**Integración en la suite Nexora (monorepo):**

| Paquete | Rol | Dependencia |
|---|---|---|
| `NexoraCore` (`../NexoraCore`) | Núcleo compartido: `CorePrefs`, `CoreLocale`, `CorePerformance`, `CorePermissions`, dominio de archivos (`FileKind`, `FsScannerRegistry`, `ThumbsService`, `MediaIndexService`) con motor nativo Rust vía FFI | `path:` |
| `NexoraUi` (`../NexoraUi`) | Design System: `NAppShell`, `NMobileLayout`, `NNavigationDestination`, tokens `NSpacing`, `NTypography`, `NCloudStorageCard` | `path:` |
| `NFiles` (este módulo) | UI + estado: `FilesController`, `FileService`, pantallas `Recent` / `Explore` / `Category`, bóveda privada | app final (`publish_to: none`) |

Flujo de arranque (`lib/main.dart`): Núcleo (`CorePrefs` → `CoreLocale` → `CorePerformance` → `CorePermissions`) → `LocalStore.load()` → `CoreAppScope` → `NFilesHome`. El `FilesController` es único por app y alimenta ambas pestañas con un solo escaneo.

Plataformas objetivo: **Android** y **Linux**. No hay carpetas `ios/`, `macos/` ni `windows/`.

## 2. Estructura del Proyecto

```text
NFiles/
├── lib/
│   ├── main.dart                  # Bootstrap: núcleo + LocalStore + CoreAppScope
│   ├── app/
│   │   └── nfiles_app.dart        # NFilesApp / NFilesHome (Recientes + Explorar)
│   ├── controllers/
│   │   └── files_controller.dart  # ChangeNotifier central (escaneo, filtros, papelera, bóveda)
│   ├── models/
│   │   ├── file_model.dart        # FileModel inmutable + formatBytes()
│   │   └── explore_section.dart   # Secciones del explorador por categoría
│   ├── screens/
│   │   ├── recent/recents_screen.dart  # RecentsScreen (cards NRecentFileCard)
│   │   ├── explore/explore_screen.dart
│   │   ├── listing/file_listing_screen.dart  # Vista base: lista/grid + orden
│   │   ├── files/file_viewer_screen.dart
│   │   └── settings/              # settings (ajustes), about, permissions, vault
│   ├── services/
│   │   ├── file_service.dart      # Escaneo por raíces (Android/Linux) + isolate
│   │   ├── local_store.dart       # Snapshot, favoritos, papelera, orígenes privados
│   │   ├── private_vault.dart     # Bóveda privada en support dir
│   │   └── media_probe.dart       # EXIF / dimensiones (solo imágenes)
│   ├── utils/
│   │   └── file_viewer.dart       # Resolución de visor por extensión
│   └── widgets/
│       ├── file_tile.dart / file_row.dart
│       ├── day_header.dart
│       └── nfiles_popup.dart      # Popups Recientes vs Explorar
├── test/                          # app_test, files_controller, file_kind, viewer, local_store…
├── android/ / linux/              # Hosts nativos (solo estos dos)
├── assets/NFiles.svg
├── packaging/ / compilaciones/    # Salidas por canal (release/beta/debug)
├── pubspec.yaml                   # version: 26.09.28-release+1, sdk: ^3.13.4
└── analysis_options.yaml          # flutter_lints
```

## 3. Funcionalidades y Componentes Clave

**Modelos:**

- `FileModel` — `id/path/title`, `sizeInBytes`, `dateCreated/dateModified`, `isVideo/isFavorite/isMotionPhoto/isSelfie`, `width/height/duration`, GPS EXIF (`latitude/longitude/locationLabel`), getters `folderName`, `formattedSize`, `formattedDuration`, `megapixels`, `isHighResolution`, `copyWith()`.
- `ExploreSection` — sección tipada del explorador (imágenes, documentos, audio, APK, descargas, cámara, etc.).
- `TrashedFile` — envoltorio `{file, trashedAt}` para papelera.

**Servicios:**

- `FileService({roots, useIsolate, showHidden})` — `loadFiles()`, `existingRoots()`, `withHidden(bool)`; raíces Android vs Ubuntu; `imageExtensions` / `videoExtensions` / `supportedExtensions`; sonda de metadatos solo para imágenes. `showHidden` enciende los `.` (archivos y carpetas del sistema) y solo se aplica si el barrido se pide con él.
- `LocalStore` — `load()`, `loadSnapshot()/saveSnapshot()`, `favoriteIds()/saveFavoriteIds()`, `trashedAt()/saveTrashed()`, `privateOrigins()/savePrivateOrigins()`, `applyAppearance()`, `prefs` (el `SharedPreferences` crudo) y `viewPrefs`.
- `FilesViewPrefs` — persiste `FilesViewState` con prefijo `nfiles_view_`: `sort`, `view_mode`, `filter`, `explore_view_mode`, `default_view_mode`, `default_sort_field`, `sort_direction`, `show_hidden_files`, `show_file_extensions`, `thumbnails_wifi_only`, `confirm_delete`, `auto_empty_trash_days`. `load()` restaura el bloque de golpe; `attach(controller)` guarda con 250 ms de debounce.
- `PrivateVault(dir)` — `files()`, `moveIn(File)`, `moveOut(path, targetDir)`; directorio `getApplicationSupportDirectory()/private`.
- `MediaProbe` — lectura EXIF/dimensiones delegada a `MediaIndexService` de `NexoraCore`.

**Estado (`FilesController extends ChangeNotifier`):**

- Estados `FilesState {initial, permissionDenied, loading, loaded, error}` + `fetchFiles({silent})`, `refresh()`, `refreshSilent()`, `hydrateFromCache()`.
- Filtros topbar: `FilesSort {captureDay, addedDay}`, `FilesViewMode {byDate, compact}`, `FilesFilter {all, camera}`, búsqueda `setSearchQuery()`, derivados `visibleFiles`, `visibleGroups`.
- Categorías por `FileKind`: `imageFiles`, `documentFiles`, `musicFiles`, `apkFiles`, `archiveFiles`, `otherFiles`; por carpeta: `downloadFiles`, `cameraFiles`, `screenshotFiles`, `recorderFiles`, `instagramFiles`, `whatsappFiles`; `filesOfKind(kind)`, `filesInFolderNamed(names)`; favoritos unidos con NPhotos (`FavoritesService`, `favoriteUnion`).
- Papelera + lote: `moveToTrash/restoreFromTrash/deletePermanently/emptyTrash` y variantes `*Batch`, `toggleFavorite(s)`.
- Bóveda: `privateFiles`, `loadPrivate()`, `moveToPrivate(id)`, `restoreFromPrivate(id)`.
- Ajustes (los de la pantalla, con sus setters): `categoryLayout`, `listingField`, `listingDirection`, `showHiddenFiles`, `showFileExtensions`, `thumbnailsWifiOnly`, `confirmDelete`, `autoEmptyTrashDays`; `FilesViewState.of(c)/.fresh()` y `restoreViewState(state)`. Los dos con efecto real: `thumbnailsWifiOnly` corta el prerrellenado por scroll (`ensureThumbnails` no llama al motor; lo ya generado se sigue usando y `generateThumbnail(path)` es la demanda explícita que no se niega), y `confirmDelete` lo lee `confirmDestructive(context, controller: …)`, que devuelve `true` sin abrir nada cuando está apagado.
- Motor nativo: `FsScannerRegistry engines`, `ThumbsService thumbs`, `MediaIndexService media`, `applyPerformanceProfile()`, `ensureThumbnails(paths)`, `generateThumbnail(path)`, `thumbnailFor(path)`, `countMedia()`, `groupByDay()`, `clearThumbnailCache()`; `startWatching({debounce})` con anti-solape `_fetching`.

**Widgets y pantallas:**

- Pantallas: `NFilesHome` (tabs `Recientes`/`Explorar` + `NMobileLayout`), `RecentsScreen` (cards `NRecentFileCard` del kit), `ExploreScreen` (cuatro bloques; **una categoría con 0 elementos no se pinta**, y si un grupo se queda sin filas tampoco pinta su título; sin archivos se dice con un aviso en vez de dejar la pantalla a medias), `FileListingScreen` (vista base de carpetas y categorías: lista `NRecentFileCard` o cuadrícula `NGridFileCard`, orden `ListingSortField` + `SortDirection` desde `FolderViewSettingsPopup`), `FileViewerScreen` (media_kit), `NFilesSettingsScreen`, `NFilesAboutScreen`, `NFilesPermissionsScreen`.
- Ajustes: `NFilesSettingsScreen` (una sola pantalla: delega en `NSettingsScreen` del kit e inyecta `NFilesFilesSettingsContent` por `extraBlocks`, sin pantalla intermedia) con los tres grupos **Visualización**, **Almacenamiento y miniaturas**, **Seguridad y papelera**; `NFilesVaultScreen` (carpeta segura). Sufijos del kit: switch plano en booleanos (`NOptionTile.toggle`), chevron en lo que abre selector o navega, `NCheckmark` en la opción activa del selector. El contenido es una columna, no una lista: vive dentro del `ListView` de Ajustes.
- `confirmDestructive(context, controller:, title:, message:)` en `lib/utils/` pregunta por `showNConfirmDialog` (o sea `showNModal`) solo si `confirmDelete` está activo.
- Widgets: `FileTile`, `FileRow`, `DayHeader` (`"Fecha • N elementos"` + colapso), `NRecentFileCard` (icono o miniatura + `peso • origen`) y `NGroupedCardContainer` (tarjeta por día, en el kit) en `RecentsScreen`; `buildRecentPopupItems()` (`MODO DE VISTA` + `AJUSTES`: Cuenta, Configuración) / `buildExplorePopupItems()`.

## 4. Guía de Uso Rápido

Dependencia local desde otra app del monorepo (solo lectura del dominio, la UI es app final):

```yaml
# pubspec.yaml
dependencies:
  NexoraCore:
    path: ../NexoraCore
  NexoraUi:
    path: ../NexoraUi
```

Arranque mínimo (producción, mismo orden que `lib/main.dart`):

```dart
import 'package:flutter/material.dart';
import 'package:NexoraCore/NexoraCore.dart';
import 'package:NFiles/app/nfiles_app.dart';
import 'package:NFiles/services/local_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await CorePrefs.open('nfiles_');
  final locale = await CoreLocale.open(prefs);
  final performance = await CorePerformance.open(prefs);
  final permissions = CorePermissions();
  final store = await LocalStore.load();

  runApp(
    CoreAppScope(
      locale: locale,
      child: NFilesApp(
        store: store,
        permissions: permissions,
        performance: performance,
        locale: locale,
      ),
    ),
  );
}
```

Consumo del controlador (filtrado + agrupado por día):

```dart
import 'package:NFiles/controllers/files_controller.dart';

final controller = FilesController();

// Escaneo inicial (pide Permission.photos/storage en Android)
await controller.fetchFiles();

// Búsqueda + filtros de la topbar
controller.setSearchQuery('factura');
controller.setSort(FilesSort.captureDay);
controller.setViewMode(FilesViewMode.byDate);

// Lo que pinta la grilla
final visibles = controller.visibleFiles;
final porDia = controller.visibleGroups;

// Categorías por familia (extensión, no carpeta)
final pdfs = controller.documentFiles;
final apks = controller.apkFiles;

// Papelera y bóveda
await controller.moveToTrash(visibles.first.id);
await controller.moveToPrivate(visibles.last.id);
```

Inyección en tests (evita escanear `$HOME` real):

```dart
final fake = FilesController(
  fileService: FileService(roots: [], useIsolate: false),
);
```

## 5. Desarrollo y Pruebas Locales

Requisitos: Flutter `3.47.5` (canal `stable`), Dart `^3.13.4`, monorepo con `../NexoraCore` y `../NexoraUi` al mismo nivel.

```bash
# 1. Dependencias (desde NFiles/)
flutter pub get

# 2. Análisis estático (flutter_lints)
flutter analyze

# 3. Formato
dart format lib test

# 4. Tests (8 suites: app, controller, file_kind, viewer, local_store…)
flutter test
flutter test test/files_controller_test.dart --plain-name "papelera"

# 5. Ejecución local
flutter run -d linux              # escritorio
flutter run -d emulator-5554      # Android (o <device-id> de `flutter devices`)

# 6. Build por canal (calendario Nexora AA.MM.DD-canal)
flutter build apk --release --target-platform android-arm64
flutter build linux --release
```

Notas:

- En `testWidgets` usar `FileService(roots: [...], useIsolate: false)` — `compute` no completa bajo reloj falso.
- Permisos Android: `Permission.photos` → fallback `Permission.storage`; en Linux no se solicitan.
- Nunca commitear `android/key.properties`, `*.jks`, `*.keystore` (ya ignorados).

## 6. Estándar de Contribución y Commits

Este módulo sigue **Conventional Commits**. Todo commit y PR debe adherirse a la especificación:

- `feat:` — nueva funcionalidad (ej. `feat: añadir filtro por cámara en Explorar`)
- `fix:` — corrección de bug (ej. `fix: evitar parpadeo en refresh silencioso`)
- `refactor:` — cambio interno sin alterar comportamiento
- `perf:` — mejora de rendimiento (escaneo, miniaturas, isolate)
- `docs:` — solo documentación (`README`, comentarios `dartdoc`)
- `test:` — añadir o corregir pruebas
- `chore:` — tooling, dependencias, packaging
- `build:` — sistema de build (Gradle, CMake, canales release/beta/debug)

Reglas:

1. Un commit = una intención. No mezclar `feat` + `fix`.
2. Scope opcional con área: `feat(controller): …`, `fix(vault): …`, `docs(readme): …`.
3. `version` en `pubspec.yaml` sigue calendario Nexora (`26.09.28-release+1`); el bump va en commit dedicado (`chore(release): …`).
4. Antes de pushear: `flutter analyze` + `flutter test` en verde.
