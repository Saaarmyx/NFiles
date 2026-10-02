// lib/screens/files/file_preview_screen.dart
//
// Enrutador de visores.
//
// # Por qué una pantalla y no un `if` dentro del visor actual
//
// `FileViewerScreen` está hecho para medios: página a página con un
// `PageView`, gestos de deslizamiento y vídeo con vida propia. Meterle un
// archivo de texto obligaría a comprobar el tipo en dos sitios: antes de
// construir el `PageView` y otra vez al pintar. Con una pantalla aparte,
// cada visor tiene su ciclo de vida entero y añadir un tercero no toca los
// otros dos.
//
// # Por qué el enrutado está en una función aparte
//
// `decideViewerFor` es una función pura que devuelve un enum. Se prueba sin
// montar nada, y el `switch` que la usa es exhaustivo: cuando se añada un
// visor nuevo, el compilador obliga a decidir aquí qué pasa con ese tipo. Sin
// eso, un `kind` nuevo caería en `unsupported` en silencio.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:NexoraCore/NexoraCore.dart';
import 'package:NexoraUi/NexoraUi.dart';

import '../../controllers/files_controller.dart';
import 'file_viewer_screen.dart';
import '../../models/file_model.dart';
/// Qué visor corresponde a un archivo.
enum PreviewKind {
  /// Se abre en el visor de medios, que ya existe.
  media,

  /// Texto o código, con `NTextViewer`.
  text,

  /// PDF, con `NPdfViewerLayout`.
  pdf,

  /// APK, con las piezas del inspector (`NApkHeaderCard` y compañía).
  apk,

  /// No hay visor: se avisa en vez de abrir una pantalla en blanco.
  unsupported,
}

/// Decide el visor de [file] a partir de su tipo.
///
/// Se decide por la extensión y no por el contenido leído, y a propósito: leer
/// el archivo para averiguar cómo mostrarlo es un `open` antes de abrir, y
/// en una lista de 200 archivos son 200 lecturas que el usuario no pidió. La
/// extensión puede fallar —un `.txt` que es en realidad un ZIP— y para eso el
/// visor de texto ya comprueba que los bytes sean texto de verdad.
PreviewKind decideViewerFor(String path) {
  final kind = kindForPath(path);
  switch (kind) {
    case FileKind.code:
      return PreviewKind.text;
    case FileKind.document:
      // Un `.pdf` cae en `document`, igual que un `.docx` o un `.txt`. Por
      // extensión se separa: el PDF tiene su propio visor con páginas y zoom,
      // y un `.docx` no se puede enseñar como texto.
      return _isPdf(path) ? PreviewKind.pdf : PreviewKind.text;
    case FileKind.image:
    case FileKind.video:
    case FileKind.audio:
      return PreviewKind.media;
    case FileKind.apk:
      return PreviewKind.apk;
    case FileKind.spreadsheet:
    case FileKind.presentation:
    case FileKind.archive:
    case FileKind.diskImage:
    case FileKind.other:
      return PreviewKind.unsupported;
  }
}

bool _isPdf(String path) {
  final corte = path.lastIndexOf('.');
  if (corte < 0 || corte == path.length - 1) return false;
  return path.substring(corte + 1).toLowerCase() == 'pdf';
}

/// Pantalla de previsualización: elige visor y lo pinta.
class FilePreviewScreen extends StatefulWidget {
  const FilePreviewScreen({
    super.key,
    required this.file,
    required this.controller,
    this.files = const [],
  });

  final FileModel file;
  final FilesController controller;

  /// Los archivos vecinos, para poder pasar al siguiente.
  final List<FileModel> files;

  @override
  State<FilePreviewScreen> createState() => _FilePreviewScreenState();
}

class _FilePreviewScreenState extends State<FilePreviewScreen> {
  /// Lo que devolvió [TextContentService].
  TextContent? _contenido;

  /// Lo que devolvió [PdfDocumentService].
  PdfInfo? _pdf;

  /// Lo que devolvió [ApkInspectorService].
  ApkInfo? _apk;

  /// `true` mientras se lee.
  bool _cargando = true;

  /// `true` si el texto resultó ser binario aunque la extensión diga texto.
  bool _pareceBinario = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final file = widget.file;
    final kind = decideViewerFor(file.path);

    switch (kind) {
      case PreviewKind.text:
        // El contenido se pide con el tope por defecto. Un `.log` de 300 MB
        // no se lee entero: el servicio corta y lo dice, y el visor lo
        // declara en vez de fingir que ese era todo el archivo.
        final content = await TextContentService.read(file.path);
        if (!mounted) return;
        setState(() {
          _contenido = content;
          _pareceBinario = content.truncation == TextTruncation.unreadable;
          _cargando = false;
        });
      case PreviewKind.pdf:
        final info = await PdfDocumentService.inspect(file.path);
        if (!mounted) return;
        setState(() {
          _pdf = info;
          _cargando = false;
        });
      case PreviewKind.apk:
        // La inspección es E/S real con seeks: corre en el `await` como el
        // texto y el PDF, y la pantalla pinta el indicador mientras tanto.
        final apk = await ApkInspectorService.inspect(file.path);
        if (!mounted) return;
        setState(() {
          _apk = apk;
          _cargando = false;
        });
      case PreviewKind.media:
      case PreviewKind.unsupported:
        if (!mounted) return;
        setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    final kind = decideViewerFor(file.path);

    if (kind == PreviewKind.media) {
      // Los medios ya tienen su visor, con su propia galería. Delegar en él
      // en vez de duplicarlo aquí.
      return FileViewerScreen(
        controller: widget.controller,
        initialIndex: _indiceDe(file),
        filesOverride: widget.files.isEmpty ? [file] : widget.files,
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _barra(
              context,
              file,
              kind == PreviewKind.pdf ? _pdf?.pageCount : null,
            ),
            Expanded(
              child: _cargando
                  ? const Center(
                      child: NLoader(size: 32, color: Colors.white),
                    )
                  : _cuerpo(kind, file),
            ),
          ],
        ),
      ),
    );
  }

  int _indiceDe(FileModel file) {
    if (widget.files.isEmpty) return 0;
    final i = widget.files.indexWhere((f) => f.id == file.id);
    return i < 0 ? 0 : i;
  }

  Widget _barra(BuildContext context, FileModel file, int? paginas) {
    final subtitulo = switch (decideViewerFor(file.path)) {
      PreviewKind.text => _contenido == null
          ? null
          : _contenido!.totalBytes > _contenido!.readBytes
              ? 'Mostrando los primeros ${_contenido!.readBytes ~/ 1024} KB de '
                  '${TextContentService.defaultMaxBytes ~/ (1024 * 1024)} MB '
                  'admitidos'
              : null,
      PreviewKind.pdf => _pdf == null
          ? null
          : !_pdf!.isValidPdf
              ? 'No se pudo leer el PDF'
              : _pdf!.encrypted
                  ? 'Cifrado: no se puede mostrar'
                  : paginas != null && paginas > 0
                      ? '$paginas ${paginas == 1 ? 'página' : 'páginas'}'
                      : 'Páginas no determinadas',
      PreviewKind.apk => _apk == null
          ? null
          : !_apk!.isValidApk
              ? 'No se pudo leer el APK'
              : _apk!.versionLabel,
      _ => null,
    };

    return NViewerTopBar(
      title: file.title,
      subtitle: subtitulo,
      onClose: () => Navigator.of(context).maybePop(),
    );
  }

  Widget _cuerpo(PreviewKind kind, FileModel file) {
    switch (kind) {
      case PreviewKind.text:
        return _cuerpoTexto();
      case PreviewKind.pdf:
        return _cuerpoPdf(file);
      case PreviewKind.apk:
        return _cuerpoApk(file);
      case PreviewKind.media:
      case PreviewKind.unsupported:
        return _noSoportado(file);
    }
  }

  Widget _cuerpoTexto() {
    final content = _contenido;
    if (content == null) return const SizedBox.shrink();

    if (_pareceBinario) {
      // La extensión dice texto pero los bytes no lo son. Se declara en vez
      // de pintar 200.000 caracteres de control.
      return _aviso(
        Icons.warning_amber_rounded,
        'Este archivo no es texto',
        'La extensión dice que lo es, pero su contenido es binario. '
            'Puede que se haya renombrado.',
      );
    }

    if (content.totalBytes == 0) {
      return _aviso(
        Icons.description_outlined,
        'Archivo vacío',
        'No hay nada que mostrar.',
      );
    }

    final esCodigo = kindForPath(widget.file.path) == FileKind.code;

    return NTextViewerShortcuts(
      onCopyAll: () => _copiar(content.text),
      child: NTextViewer(
        text: content.text,
        // Números de línea y ajuste al ancho solo tienen sentido leyendo
        // código. En un `.txt` proselto un número de línea cada 4 palabras
        // es ruido, y envolver el texto es lo que hace legible un párrafo.
        showLineNumbers: esCodigo,
        monospace: esCodigo,
        wrapLines: !esCodigo,
        header: NTextViewerStatusBar(
          totalLines: content.lines.length,
          bytesRead: content.readBytes,
          totalBytes: content.totalBytes,
        ),
      ),
    );
  }

  Widget _cuerpoPdf(FileModel file) {
    final info = _pdf;
    if (info == null) return const SizedBox.shrink();

    if (!info.isValidPdf) {
      return _aviso(
        Icons.picture_as_pdf_outlined,
        'No es un PDF válido',
        'El archivo no tiene la estructura de un PDF, o no se pudo leer.',
      );
    }

    if (info.encrypted) {
      return _aviso(
        Icons.lock_outline,
        'PDF cifrado',
        'Necesita una contraseña y aquí no hay forma de introducirla.',
      );
    }

    // Aquí es donde entraría el renderizador. Como no hay motor de PDF, se
    // declara lo que se sabe en vez de dejar una pantalla en blanco, que
    // es lo que un usuario no puede distinguir de un fallo.
    return _aviso(
      Icons.info_outline,
      info.pageCount > 0
          ? 'Documento de ${info.pageCount} '
              '${info.pageCount == 1 ? 'página' : 'páginas'}'
          : 'Documento PDF',
      'Este visor no puede mostrar el contenido todavía. El archivo está '
          'localizado y se puede abrir con otra aplicación.',
    );
  }

  /// Cuerpo del inspector de APK.
  ///
  /// Con scroll propio: cabecera, especificaciones y permisos no caben en
  /// una pantalla de móvil a la vez, y sin scroll la lista de permisos
  /// empujaría el resto fuera sin forma de llegar a él.
  Widget _cuerpoApk(FileModel file) {
    final info = _apk;
    if (info == null) return const SizedBox.shrink();

    if (!info.isValidApk) {
      return _aviso(
        Icons.android,
        'No se pudo leer el APK',
        info.error ?? 'El archivo no es un paquete válido.',
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NApkHeaderCard(
            appName: info.displayName,
            packageName: info.packageName ?? file.title,
            versionLabel: info.versionLabel,
            iconBytes: info.iconBytes,
          ),
          const SizedBox(height: 20),
          NApkInfoSection(
            minSdk: info.minSdk,
            targetSdk: info.targetSdk,
            // El tamaño y la fecha los pone el modelo de la app, no el
            // manifiesto: el APK no declara ninguno de los dos.
            sizeBytes: file.sizeInBytes,
            modified: file.dateModified,
          ),
          const SizedBox(height: 20),
          NApkPermissionsList(
            permissions: [
              for (final p in info.permissions)
                NApkPermission(name: p.name, risk: _riesgo(p.risk)),
            ],
          ),
        ],
      ),
    );
  }

  /// Traduce el riesgo del núcleo al del kit. Exhaustivo a propósito: si el
  /// núcleo añade un nivel, el compilador obliga a decidir aquí qué pinta
  /// la UI, en vez de caer en un `unknown` silencioso.
  NApkPermissionRisk _riesgo(ApkPermissionRisk risk) {
    switch (risk) {
      case ApkPermissionRisk.normal:
        return NApkPermissionRisk.normal;
      case ApkPermissionRisk.dangerous:
        return NApkPermissionRisk.dangerous;
      case ApkPermissionRisk.special:
        return NApkPermissionRisk.special;
      case ApkPermissionRisk.signature:
        return NApkPermissionRisk.signature;
      case ApkPermissionRisk.unknown:
        return NApkPermissionRisk.unknown;
    }
  }

  Widget _noSoportado(FileModel file) {
    return _aviso(
      iconForPath(file.path),
      'Sin vista previa',
      'Este tipo de archivo no se puede mostrar aquí.',
    );
  }

  /// Pantalla de aviso con icono, título y explicación.
  Widget _aviso(IconData icon, String titulo, String detalle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Colors.white54),
            const SizedBox(height: 16),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: NTypography.fontFamilyBase,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              detalle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: NTypography.fontFamilyBase,
                fontSize: 13,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copiar(String texto) async {
    await Clipboard.setData(ClipboardData(text: texto));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Copiado al portapapeles')),
      );
  }
}

/// Abre el visor adecuado para [file].
///
/// Punto de entrada único desde la lista y la rejilla: decide el tipo y
/// empuja la pantalla que corresponda. Devolver un `Future` permite que quien
/// llama espere al cierre, como hace el resto de aperturas de la app.
Future<void> openFilePreview(
  BuildContext context, {
  required FilesController controller,
  required FileModel file,
  List<FileModel> files = const [],
}) {
  return pushNPage<void>(
    context,
    FilePreviewScreen(
      file: file,
      controller: controller,
      files: files,
    ),
  );
}
