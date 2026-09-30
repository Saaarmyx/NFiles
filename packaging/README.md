# Packaging NFiles: compilaciones por canal (release/beta/debug)

Las salidas van a `compilaciones/` (ignorada por git):

```
compilaciones/
  apk/release|beta|debug/
  deb/release|beta|debug/
```

El canal se deduce del sufijo de `version:` en pubspec.yaml
(`26.09.28-release` → `release`, `-beta` → `beta`, `-debug` o sin
sufijo → `debug`).

## 1. El icono: un solo PNG por plataforma

Fuente de verdad en `assets/` (la primera que exista, en este orden):
`NFiles.svg` (recomendada) o `NFiles.png` (raster ≥1024px ideal).
Foreground dedicado opcional con el mismo criterio:
`NFiles-foreground.svg` / `NFiles-foreground.png` (si falta, se
reutiliza el icono completo).

Regenerar todo tras cambiar el arte:

```bash
./packaging/icons/build-icons.sh
```

El foreground se renderiza al 72% con aire (`FG_SCALE` en el script)
porque el launcher recorta a la zona segura; sin ese inset el icono
se ve cropeado/con zoom. El legacy y Ubuntu van a sangre.

| Pieza | Ruta |
|---|---|
| Android legacy | `res/mipmap-<mdpi…xxxhdpi>/ic_launcher.png` (48/72/96/144/192) |
| Android adaptativo | `res/mipmap-anydpi-v26/ic_launcher.xml` + `res/mipmap-<dpi>/ic_launcher_foreground.png` (108/162/216/324/432) |
| Fondo adaptativo | `res/values/colors.xml` (`ic_launcher_background`, no se toca) |
| Linux hicolor | `packaging/linux/icons/hicolor/512x512/apps/NFiles.png` |
| `.desktop` | `packaging/linux/NFiles.desktop` |

> ⚠️ **Falta el arte maestro.** `assets/` no existe todavía en NFiles, así
> que `build-icons.sh` aborta con un mensaje explícito hasta que pongas
> `assets/NFiles.svg` (o `.png`). El PNG de hicolor que hay hoy en
> `packaging/linux/` es un **provisional heredado de NPhotos**: sirve
> para que el `.deb` se pueda ensamblar, pero hay que sustituirlo por el
> arte real antes de publicar.

## 2. APK Android

```bash
./packaging/apk/build-apk.sh
```

Copia los 3 APK (uno universal por canal) a
`compilaciones/apk/<canal>/NFiles_<versión>-<canal>.apk`. La base
`AA.MM.DD` sale de `version:` en pubspec y el canal se inyecta con
`--build-name`, así el `versionName` horneado coincide con la carpeta
y el archivo.

**Firma release** (una vez):

```bash
keytool -genkey -v -keystore ~/keystores/NFiles-release.jks \
  -alias NFiles -keyalg RSA -keysize 2048 -validity 10000
cp android/key.properties.example android/key.properties  # y rellenar
```

Sin `android/key.properties`, la release se firma con clave debug (aviso,
no apto para Play Store). `applicationId`: `com.nexora.nfiles`.

## 3. .deb Ubuntu

```bash
./packaging/deb/build-deb.sh
# o con mantenedor propio:
DEB_MAINTAINER="Nombre <email>" ./packaging/deb/build-deb.sh
```

Genera `compilaciones/deb/<canal>/NFiles_<versión>_amd64.deb`: binario en
`/usr/lib/NFiles`, enlace en `/usr/bin/NFiles`, `.desktop` en
`/usr/share/applications` e iconos en `/usr/share/icons`. Instalar con
`sudo apt install ./NFiles_*_amd64.deb`
(`Depends: libgtk-3-0 | libgtk-3-0t64, libblkid1, liblzma5, libglib2.0-0, libmpv2`).
