# AGENTS.md — Core Linux ISO (perfil archiso)

Instrucciones para cualquier agente que trabaje en este repositorio. **Léete esto antes de tocar nada.**

---

## 1. Qué es este repo

Perfil de **archiso** (no un proyecto compilable): define una ISO live "Core Linux" (GNU/Linux, KDE/Plasma).
El repositorio **no contiene código**: solo el perfil que `mkarchiso` consume para construir la ISO.

- Perfil: `/home/m4teo/archlatam-iso/Archlatam-ISO`
- Build: `sudo mkarchiso -m iso .` (desde la raíz del perfil)
- ISO live: sesion KDE Plasma en RAM (`cow_spacesize`), instalador Calamares, arranque BIOS + UEFI.

### Regla de oro
**NO compiles la ISO.** El usuario la compila por su cuenta. Trabaja solo sobre ficheros del perfil y verifica con
inspección/lint estático. Si necesitas un build, pregunta antes.

### Regla de oro 2
**No toques `pacman.conf`** ni los bloques comentados al final de `packages.x86_64` (`#calamares-*`, `#core-*`):
son modificaciones del usuario, no tuyas.

---

## 2. Arquitectura del perfil (lo que hay que saber para no romper nada)

### 2.1 El initramfs lo genera mkinitcpio, no archiso
Archiso **no genera el initramfs**: copia el `/boot` del chroot. El `initramfs-linux.img` lo produce el
**hook de pacman de `mkinitcpio`** dentro del chroot, usando:

- `/etc/mkinitcpio.conf` (del paquete `mkinitcpio`) + el drop-in del airootfs
  `airootfs/etc/mkinitcpio.conf.d/archiso.conf` → aquí es donde se añaden los HOOKS.
- El preset `airootfs/etc/mkinitcpio.d/linux.preset` (`PRESETS=('archiso')`, config = ese drop-in).

⇒ **Para meter algo en el initramfs: añade el hook en `airootfs/etc/mkinitcpio.conf.d/archiso.conf`.**

Hooks actuales:
```bash
HOOKS=(base udev microcode modconf kms plymouth memdisk archiso archiso_loop_mnt block filesystems keyboard)
COMPRESSION="xz"
```
Este initramfs **no usa el hook `systemd`** → los hooks que dependen de systemd (ej. `plymouth`) caen al camino
legacy `add_runscript` (`/usr/lib/initcpio/hooks/<hook>`). Es correcto aquí, no lo "arregles".

### 2.2 Parámetros de kernel
El mecanismo estándar de archiso es `%KERNEL_PARAMS%` en los `.cfg` + `kernel_params_<arch>` en `profiledef.sh`.
Sustitución en `mkarchiso`: líneas 522 (syslinux), 643 (grub), 725 (loopback), 884 (systemd-boot, ya no se usa).

```bash
kernel_params_x86_64="quiet splash"
```
- `%KERNEL_PARAMS%` **solo** en la entrada normal; la entrada de accesibilidad (speakup) **no** lo lleva
  (sin `splash` en el cmdline Plymouth no dibuja el splash → el braille de brltty funciona).
- Omarchy usa exactamente este patrón (`quiet splash`).

### 2.3 Bootloaders
```bash
bootmodes=('bios.syslinux' 'uefi.grub')
```
- **BIOS** → `syslinux/` (`archiso_head.cfg`, `archiso_sys-linux.cfg`, …). Menú **visible**, `TIMEOUT 50` = **5 s**
  (`DEFAULT core64`); syslinux no tiene equivalente a `timeout_style=hidden`. Fondo del menú:
  `MENU BACKGROUND splash.png` (`archiso_head.cfg`) → `syslinux/splash.png`, el `splash.png` stock del perfil
  `releng` de archiso con el color cambiado a `#16242d`.
- **UEFI** → `grub/grub.cfg` + `grub/loopback.cfg`. Menú **visible 5 s** (`timeout=5`, `timeout_style=menu`,
  `default=core`) en modo **texto**: el bloque de vídeo es el stock de archiso (`insmod all_video` +
  `terminal_output console`). **Sin tema**: no hay `grub/themes/` ni `gfxterm`.
- `efiboot/` (systemd-boot) **fue eliminado**: no se usa con estos bootmodes.

### 2.4 Lo que NO existe en la ISO
- No hay `plymouth-theme-archlinux` en los repos oficiales (el tema `archlinux` ya no existe; el default de Arch
  es `bgrt`).
- El paquete `plymouth` depende de `filesystem`, que es quien provee `/usr/share/pixmaps/archlinux-logo.png`
  que exige el hook de mkinitcpio → no hace falta paquete extra para ese logo.

---

## 3. Plymouth — implementado (tema `corelinux`)

### Estado
Activado. Tema propio llamado **`corelinux`** (paquete `plymouth-theme-corelinux`).

| Fichero | Contenido |
|---|---|
| `airootfs/etc/plymouth/plymouthd.conf` | `[Daemon]` / `Theme=corelinux` / `ShowDelay=0` |
| `airootfs/usr/share/plymouth/themes/corelinux/corelinux.plymouth` | `Name=Core Linux`, `ModuleName=script`, `ImageDir`/`ScriptFile` → `themes/corelinux`; sin `Font=` (usa `Sans` por defecto) |
| `airootfs/usr/share/plymouth/themes/corelinux/corelinux.script` | Animación de 145 frames, diálogo LUKS activo y mensajes; sin barra de progreso |
| `airootfs/usr/share/plymouth/themes/corelinux/*.png` | `frame-000.png` … `frame-144.png` (768x384, opacos, ~4,4 MB) + `entry.png` y `bullet.png` para LUKS |
| `packages.x86_64` | `plymouth` (y `cantarell-fonts`, que ya no usa el tema; se mantiene por el resto del perfil) |
| `airootfs/etc/mkinitcpio.conf.d/archiso.conf` | hook `plymouth` tras `kms` |

### Tema `corelinux`
- Reemplaza al tema anterior `core`. El paquete `plymouth-theme-corelinux` ya está publicado en
  `core_repo` (`r3.148c3ed-1`) y es el que instala Calamares en el sistema destino.
- **Animación**: 145 PNG (`frame-000.png` … `frame-144.png`) de 768x384, fondo negro opaco y el
  globo/wordmark "CORE LINUX" en tonos celestes. El script las precarga todas en un array y las
  cicla con `Plymouth.SetRefreshFunction`; no hay barra de progreso ni evento de progreso real.
- **RAM**: al decodificarse, los 145 frames ocupan ~163 MiB. En la ISO pesan ~4,4 MB. Si se
  optimiza, reducir resolución o cantidad de frames; el script deriva el centrado de
  `frames[0].GetWidth()/GetHeight()`, así que no hace falta tocar la geometría.
- **Fondo**: negro (`Window.SetBackgroundTopColor/BottomColor(0, 0, 0)`), coherente con los PNG.
- **Diálogo LUKS activo**: `entry.png`/`bullet.png` y `Plymouth.SetDisplayPasswordFunction` están
  activos (a diferencia del tema `core`, que los tenía comentados). En el live no hay cifrado, así
  que no se muestra; en el sistema instalado con LUKS sí.
- **Fuente**: `corelinux.plymouth` no define `Font=`; el hook usa `Sans`, que en el live resuelve
  a `ttf-liberation` (`/usr/share/fonts/liberation/LiberationSans-Regular.ttf`). `cantarell-fonts`
  ya no es necesario para el tema, pero se deja en `packages.x86_64`.
- **Fuente editable**: no meter `.xcf`/`.psd` ni originales dentro de `airootfs/.../themes/corelinux/`;
  el hook hace `add_full_dir` de todo el directorio y acabarían en el initramfs y en la ISO.

### Cómo Plymouth se resuelve en el build (verificado)
`/usr/lib/initcpio/install/plymouth`:
1. `plymouth-set-default-theme` lee `[Daemon] Theme` de `/etc/plymouth/plymouthd.conf` → `corelinux`, y valida que
   exista `/usr/share/plymouth/themes/corelinux/corelinux.plymouth` → si no existe, cae a `bgrt` y luego a `text`.
2. Exige: `plymouth` instalado en el chroot (si falta, mkinitcpio **aborta** → no hay initramfs → build fallido),
   `/usr/share/pixmaps/archlinux-logo.png` (lo da `filesystem`), `/etc/plymouth/plymouthd.conf` (lo da el airootfs).
3. Sin `Font=` en el `.plymouth`, el hook resuelve `Sans` con fontconfig (`plymouth-font-file`); en el live lo
   provee `ttf-liberation`. Si no hay fuente, el hook omite la copia y el texto puede no renderizarse.
4. Copia el tema entero con `add_full_dir "$PLYMOUTH_THEME_DIR"`.

---

## 4. Escritorio por defecto del live (`/etc/skel` + Firefox)

`mkarchiso` copia `/etc/skel/.` al home de cada usuario del airootfs con uid 1000–59999
(`_make_customize_airootfs`, líneas 397-411: `cp -dRT --update=none`, luego `chown -hR` y `chmod 0750`).
En este perfil el único es `liveuser` (uid 1000) → **todo lo que haya en el skel aparece en el escritorio**.

### Estado actual: 26 ficheros / 128 KB
Se partió de **94 MB** con una sesión real copiada dentro (cachés de Mesa, perfil de Firefox con
`logins.db`/`key4.db`/cookies/historial, `libaccounts-glib`, BD de actividades...). Todo eso se borró.
**No volver a copiar un `~` real dentro del skel.**

### Modo oscuro (Breeze Dark)
| Fichero | Clave |
|---|---|
| `.config/kdeglobals` | `[General] ColorScheme=BreezeDark`, `[Icons] Theme=breeze-dark`, `[KDE] LookAndFeelPackage=org.kde.breezedark.desktop` + `widgetStyle=Breeze` |
| `.config/kdedefaults/kdeglobals` | `[General] ColorScheme=BreezeDark` (fallback KDE6) |
| `.config/kdedefaults/package` | `org.kde.breezedark.desktop` |
| `.config/gtk-3.0/settings.ini`, `.config/gtk-4.0/settings.ini` | `gtk-application-prefer-dark-theme=true`, `gtk-icon-theme-name=breeze-dark`, `gtk-theme-name=Breeze-Dark` (necesita `breeze-gtk`, ya en `packages.x86_64`) |

`LookAndFeelPackage` lo lee `ShellCorona` de `kdeglobals [KDE]` (`shellcorona.cpp:1807`) y carga el tema
global, que aporta el esquema de color.

### Altura del panel: 40 px
`.config/plasmashellrc`:
```ini
[PlasmaViews][Panel 2]
floating=1
shell=org.kde.plasma.desktop

[PlasmaViews][Panel 2][Defaults]
thickness=40
```
**Verificado en el fuente de plasma-workspace 6.8.1** (la versión del repo):
- `PanelView::setThickness()` → `configDefaults().writeEntry("thickness", …)`; se lee en `panelview.cpp:844`.
- `configDefaults()` = grupo `PlasmaViews` → `Panel <id>` → `Defaults` (`panelview.cpp:160-170`).
- `ShellCorona::applicationConfig()` = `KSharedConfig::openConfig()` **sin nombre** (`shellcorona.cpp:1012`)
  → `KConfig::mainConfigName()` = `applicationName() + "rc"` = **`plasmashellrc`** (`kconfig.cpp:643`).
  Igual en v6.0.0 / 6.2.0 / 6.4.0 / 6.8.1 → el panel **no** se configura en `plasmarc` (en 6.8.1 `plasmarc` solo guarda el tema).
- `Panel 2` = `Containments[2]` de `plasma-org.kde.plasma.desktop-appletsrc` (`plugin=org.kde.panel`).

### Icono del menú Kickoff (`corelinux.png`)
`.config/plasma-org.kde.plasma.desktop-appletsrc`:

```ini
[Containments][2][Applets][3]
plugin=org.kde.plasma.kickoff

[Containments][2][Applets][3][Configuration][General]
favoritesPortedToKAstats=true
icon=/usr/share/icons/corelinux.png
```

- `Applets][3]` es el Kickoff del panel (`Applets][4]` pager, `Applets][5]` icontasks) → idéntico al
  `etc/skel` del paquete `core-skel-kde` del sistema instalado (`Applets][24]` allí, misma clave y misma ruta).
- **Por qué ruta absoluta y no `icon=corelinux`**: el paquete `core-icons` (en `packages.x86_64`) instala el PNG
  **plano** en `/usr/share/icons/corelinux.png`, sin subdirectorio `hicolor/` ni `index.theme`, así que no se
  resuelve por nombre en el tema de iconos. La ruta absoluta sí está soportada explícitamente (verificado en el
  fuente, no en documentación de terceros):
  - `applets/kickoff/main.xml` → `<entry name="icon" type="String">`, default `start-here-kde-symbolic`.
  - `applets/kickoff/main.qml` → `Plasmoid.icon: Plasmoid.configuration.icon`; y
    `Image { visible: nonSquareImage && status == Image.Ready; source: Plasmoid.icon.startsWith("/") ? "file:" + … }`.
  - `applets/kickoff/code/tools.js` → `iconOrDefault()` devuelve el valor tal cual (solo rellena el default en
    panel vertical vacío). `ConfigGeneral.qml` lo edita con `KIconThemes.IconDialog`, que guarda lo mismo.
- ⚠️ **La imagen tiene que ser NO cuadrada.** Ese `imageFallback` exige `sourceSize.width != sourceSize.height`;
  si se convierte en un cuadrado perfecto, el panel deja de dibujarla (y no hay fallback por nombre, por lo de
  `hicolor/`). Actual: 998x978 (ratio 1.02), 85 KB, sha256 `fd311a17…aaf607`; Kickoff la pinta a 48 px
  (`Kirigami.Units.iconSizes.huge`), así que es un máster holgado. Si se rediseña, mantener el ratio ≠ 1.00.
- `airootfs/etc/os-release` tiene `LOGO="corelinux"`, coherente con el nombre del fichero.
- **El PNG no se versiona en el perfil**: la fuente de verdad es `core-icons/usr/share/icons/corelinux.png`
  (repo del paquete). Si se deja una copia en `airootfs/usr/share/icons/` es solo un duplicado que
  `mkarchiso` sobrescribe con los mismos bytes tras `pacstrap` **y hay que mantener sincronizado** (mismo sha256);
  para cambiar el icono, se cambia en `core-icons` y se regenera el paquete, no aquí.

Verificar la clave (dos trampas, ninguna es un fallo del fichero):
```bash
kreadconfig6 --file "$PWD/airootfs/etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc" \
  --group Containments --group 2 --group Applets --group 3 \
  --group Configuration --group General --key icon
# → /usr/share/icons/corelinux.png
```
1. **Corchetes = grupos anidados**: `--group` se repite (`--group Containments --group 2 …`). Un
   `--group 'Containments][2][Applets][3][Configuration][General'` (el nombre literal) devuelve **vacío**.
2. **Ruta absoluta obligatoria**: un nombre relativo se resuelve dentro de `$XDG_CONFIG_HOME`, así que
   `--file airootfs/etc/skel/...` devuelve vacío aunque el fichero exista y esté bien.

### Borrado a propósito (y por qué)
- `.config/user-dirs.dirs`, `.config/user-dirs.locale`, `.config/plasma-localerc`: estado de locale/XDG del
  usuario. `xdg-user-dirs` (en `packages.x86_64`) las regenera en el login con el locale real
  (`etc/locale.conf` = `C.UTF-8`), y **Calamares** reescribe locale y directorios del usuario instalado.
  El `user-dirs.dirs` heredado tenía rutas sin expandir (`$HOME/Desktop`).
- `[Updates]` de `.config/plasmashellrc` y `.config/kconf_updaterc`: lista de migraciones `.upd` de la versión
  antigua de Plasma. Sin ellos, Plasma 6.8.1 aplica todas las migraciones desde cero (correcto en una ISO nueva).
- Basura de sesión: `.cache/`, `.config/mozilla/`, `.config/libaccounts-glib/`, `.config/dconf/`, `.config/pulse/`,
  `.config/xsettingsd/`, `.config/kwinoutputconfig.json` (monitores del host), `.local/state/`,
  `.local/share/{baloo,klipper,kactivitymanagerd,user-places.xbel*}`, `.config/gtk-3.0/assets/`,
  `.config/konsolesshconfig`, `.config/kactivitymanagerd*`, `.config/baloofilerc`, `.gtkrc-2.0`, `.screenrc`.

### Nota
`.config/kded5rc` se conserva porque **kded (KF6) sigue leyendo `kded5rc`** y ahí está
`[Module-device_automounter] autoload=false` (automontaje de dispositivos desactivado).
Si se quiere el comportamiento por defecto, borrarlo.

### Firefox: página de inicio por defecto
`airootfs/usr/lib/firefox/distribution/policies.json` (Enterprise Policies, horneadas en la ISO):

```json
{
  "policies": {
    "Homepage": { "URL": "https://archlatam.github.io/", "StartPage": "homepage" },
    "OverrideFirstRunPage": ""
  }
}
```

- **Ruta verificada en el código**, no adivinada: `XREAppDist` + `policies.json`
  (`EnterprisePoliciesParent.sys.mjs:527-534`), y `XREAppDist` = `<dir de instalación>/distribution`
  (`nsXREDirProvider.cpp:420-424`) → `/usr/lib/firefox/distribution/`. El paquete `firefox` de `extra`
  solo trae `distribution.ini` ahí, así que **no se pisa nada del paquete**.
  La alternativa documentada (`/etc/firefox/policies/policies.json`) depende de `MOZ_SYSTEM_POLICIES`/`SysConfD`:
  por eso se usa la de `distribution/`.
- `Homepage.URL` → `browser.startup.homepage`; `StartPage: "homepage"` → `browser.startup.page=1`
  (cargar la home al abrir). `OverrideFirstRunPage: ""` → `startup.homepage_welcome_url=""` +
  `browser.aboutwelcome.enabled=false`, es decir **sin pestaña de bienvenida** en el perfil nuevo
  (verificado en `Policies.sys.mjs:1630-1691` y `:1839-1845`).
- **Sin `"Locked": true`** a propósito: en un live el usuario debe poder cambiar la home
  (`"homepage-locked"` la bloquearía).
- **NO** se crea perfil en el skel: el directorio del perfil se genera con nombre aleatorio
  (`xxxxxxxx.default-release`), así que un `user.js` ahí sería frágil. Las policies cubren también el primer arranque.
- Comprobar en el live: abrir Firefox → carga `https://archlatam.github.io/`; `about:policies`
  debe listar `Homepage` y `OverrideFirstRunPage`.

---

## 5. Cambios aplicados (Plymouth + menú GRUB + Firefox)

```diff
# airootfs/usr/lib/firefox/distribution/policies.json   (nuevo)
+{"policies": {"Homepage": {"URL": "https://archlatam.github.io/", "StartPage": "homepage"},
+              "OverrideFirstRunPage": ""}}

# packages.x86_64
+cantarell-fonts        (entre btrfs-progs y clonezilla)
+plymouth               (entre plasma-workspace y polkit)

# airootfs/etc/mkinitcpio.conf.d/archiso.conf
-HOOKS=(base udev microcode modconf kms memdisk archiso ...)
+HOOKS=(base udev microcode modconf kms plymouth memdisk archiso ...)

# profiledef.sh
+kernel_params_x86_64="quiet splash"

# grub/grub.cfg y grub/loopback.cfg
-timeout=15 / timeout_style=menu      (stock de archiso)
+timeout=5  / timeout_style=menu      (menú visible 5 s)
+... %KERNEL_PARAMS% cow_spacesize=10G copytoram=n      (entrada normal)
+... accessibility=on cow_spacesize=10G copytoram=n    (entrada speakup, sin splash)
-id 'core' duplicado -> id 'core-accessibility'
-sin tema: fuera `set theme="${prefix}/themes/core/theme.txt"`, sin `insmod gfxterm` y sin `grub/themes/`

# syslinux/archiso_sys.cfg
-TIMEOUT 150 / +TIMEOUT 50            (5 s, igual que GRUB; 150 = 15 s)
... %KERNEL_PARAMS% cow_spacesize=10G copytoram=n      (core64)
... accessibility=on cow_spacesize=10G copytoram=n    (core64speech)
```

### Menú de arranque (resuelto)
Menú **visible 5 s** en ambos loaders: GRUB `timeout=5` + `timeout_style=menu` y syslinux `TIMEOUT 50`
(en décimas; antes 150 = 15 s). Pasados los 5 s arranca la entrada por defecto (`core` / `core64`) con
`quiet splash`; cualquier tecla detiene la cuenta atrás. Así las entradas extra (Memtest86+, UEFI Shell,
UEFI Firmware Settings, shutdown, restart) son alcanzables.

### Sin tema gráfico (GRUB en modo texto)
`grub/` contiene solo `grub.cfg` y `loopback.cfg`. El bloque de vídeo es el stock de archiso y el menú sale en
texto (80x25) con los colores por defecto de GRUB (`white/black`, selección `black/light-gray`).

- **Se quitó el tema**: no existe `grub/themes/` y `grub.cfg` no hace `insmod gfxterm` ni `set theme=…`.
  En particular se eliminó el `set theme="${prefix}/themes/core/theme.txt"` que arrastraba el perfil: en UEFI
  `${prefix}` es `(memdisk)/boot/grub`, así que ese fichero nunca existía y GRUB arrancaba con error
  «file not found».
- El fondo del live es el del **menú de syslinux**: `syslinux/splash.png` (`MENU BACKGROUND splash.png` en
  `syslinux/archiso_head.cfg`), el `splash.png` stock del perfil `releng` con el color cambiado a `#16242d`.
  `mkarchiso` lo copia a `/boot/syslinux/splash.png`; GRUB **no** usa esa imagen.
- El tema GRUB del **sistema instalado** no es cosa de la ISO: va en el paquete `coreos-grub-theme` (lo instala
  Calamares y `grubcfg.conf` lo apunta con `GRUB_THEME`).

---

## 6. Verificación (sin compilar)

```bash
# sintaxis del perfil
bash -n profiledef.sh

# los %KERNEL_PARAMS% se sustituyen (ficheros fuente)
grep -rn '%KERNEL_PARAMS%' grub/ syslinux/

# skel: estructura y claves del escritorio por defecto
du -sh airootfs/etc/skel
grep -E '^(ColorScheme|Theme)=|LookAndFeelPackage' airootfs/etc/skel/.config/kdeglobals
grep -A3 'Panel 2' airootfs/etc/skel/.config/plasmashellrc   # thickness=40
find airootfs/etc/skel -size +100k                           # no debe listar nada

# firefox: policies.json válido y con la home correcta
python3 -m json.tool airootfs/usr/lib/firefox/distribution/policies.json >/dev/null && echo OK
grep -A4 Homepage airootfs/usr/lib/firefox/distribution/policies.json

# el hook de plymouth y sus requisitos existen en el host
pacman -Ql plymouth | grep themes
ls /usr/lib/initcpio/install/plymouth
ls /usr/lib/plymouth/script.so

# tema corelinux: 145 frames de 768x384 y las imágenes de LUKS
find airootfs/usr/share/plymouth/themes/corelinux -maxdepth 1 -name 'frame-*.png' | wc -l   # 145
magick identify -format '%f %wx%h %[channels] opaque=%[opaque]\n' \
  airootfs/usr/share/plymouth/themes/corelinux/frame-000.png

# ficheros que usa el script
ls airootfs/usr/share/plymouth/themes/corelinux/{entry,bullet}.png
ls airootfs/usr/share/plymouth/themes/corelinux/corelinux.{plymouth,script}

# fondo negro y animación de 145 frames
grep -n 'SetBackground\|frame_count' airootfs/usr/share/plymouth/themes/corelinux/corelinux.script

# no debe quedar el tema viejo
test ! -e airootfs/usr/share/plymouth/themes/core && echo "core eliminado"

# la fuente editable NO debe estar dentro de airootfs/ (acabaría en el initramfs)
find airootfs/usr/share/plymouth/themes/corelinux -type f \( -name '*.xcf' -o -name '*.psd' \)

# GRUB: sin tema, bloque de video stock (no debe haber gfxterm ni set theme)
grub-script-check grub/grub.cfg && grub-script-check grub/loopback.cfg && echo "grub OK"
grep -rn 'theme\|gfxterm' grub/    # no debe mostrar nada

# diálogo LUKS activo: estas referencias deben existir (sin comentar)
grep -n 'SetDisplayPasswordFunction\|entry_sprite\|bullet_image' \
  airootfs/usr/share/plymouth/themes/corelinux/corelinux.script
```

Cuando el usuario compile (`sudo mkarchiso -m iso .`, **necesita root**):
```bash
lsinitcpio <work>/x86_64/boot/initramfs-linux.img | grep -i plymouth
# debe listar: hooks/plymouth, usr/lib/plymouth/, usr/share/plymouth/themes/corelinux/, usr/share/fonts/Plymouth.ttf

xorriso -indev out/Core-*.iso -osirrox on -cat /boot/grub/grub.cfg | grep -E 'timeout|theme|gfxterm'
# debe mostrar: timeout=5 / timeout_style=menu; ninguna línea con theme ni gfxterm

xorriso -indev out/Core-*.iso -find /boot/syslinux -name splash.png
# el fondo del menú de syslinux (no debe existir /boot/grub/themes)
```

Prueba de arranque: `run_archiso -b -i out/Core-*.iso` (BIOS) y `run_archiso -u -i out/Core-*.iso`
(UEFI, requiere `edk2-ovmf` instalado en el host).

---

## 7. Trampas del entorno (no perder tiempo)

| Trampa | Detalle |
|---|---|
| **Build sin root** | `mkarchiso` dentro de `unshare` falla con `failed to synchronize all databases (unable to lock database)`: pacman no puede tomar `/var/lib/pacman/db.lck` en el user namespace. Con `sudo` funciona. |
| **No hay `validate` standalone** | `mkarchiso` valida el perfil como primer paso del build ("Validating options... Done!") y luego compila. No hay modo sólo-validación. |
| **Aislamiento de la GUI** | Para lanzar/screenshot de apps (QEMU, Plasma) hay que usar el entorno `omabox` (Hyprland + Omarchy contenido), nunca el escritorio real del usuario. |
| **Repos del host** | El host es Omarchy/CachyOS: `pacman -Ss`/`-Fl` puede quejarse de "database file for 'extra' does not exist" en `-Fl`; las bases de sync sí existen en `/var/lib/pacman/sync/`. |
| **`pacman.conf` del perfil** | Usa `core`, `extra`, `multilib` con `/etc/pacman.d/mirrorlist`. No lo edites. |
| **Ficheros sin trackear** | Ya está todo en git (perfil Plymouth, `airootfs/etc/skel/`, `AGENTS.md`). `git status` antes de commitear; `src/plymouth/` (fuentes) también se versiona. |
| **Fuentes editables dentro del tema Plymouth** | No meter `.xcf`/`.psd`/etc. en `airootfs/usr/share/plymouth/themes/corelinux/`: el hook hace `add_full_dir` de todo el directorio y acabarían dentro del initramfs (y en la ISO). Las fuentes editables van fuera de `airootfs/`. |
| **`${prefix}` en el GRUB de archiso** | En UEFI `${prefix}` es `(memdisk)/boot/grub`, mientras que archiso hace `set root="${ARCHISO_HINT}"` (el dispositivo de la ISO) antes del `configfile`. Si algún día se vuelve a usar un tema o un fondo en `grub.cfg`, las rutas del ISO van relativas a `$root` (`/boot/grub/...`), nunca a `${prefix}`. |

---

## 8. Referencias externas

- Tema Plymouth de Omarchy (el que se adaptó): `/usr/share/plymouth/themes/omarchy/` (paquete `omarchy-settings`).
- Config Plymouth de Omarchy: https://github.com/omacom/omarchy-iso/blob/quattro/configs/airootfs/etc/plymouth/plymouthd.conf
- `grub.cfg` de Omarchy (referencia de `timeout=0` / `timeout_style=hidden` / `quiet splash`):
  https://raw.githubusercontent.com/omacom/omarchy-iso/quattro/configs/grub/grub.cfg
- Hook de mkinitcpio: `/usr/lib/initcpio/install/plymouth`
- ArchWiki Plymouth: https://wiki.archlinux.org/title/Plymouth
