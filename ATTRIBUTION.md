# Attribution and third-party notices

oakMOSS is a small layer of scripts, configuration and patches on top of other
people's work. This file says whose, what was taken, where it sits in this
repository, and under which terms. Files that are not listed here are oakMOSS's
own and covered by [LICENSE](LICENSE).

Two different questions run through this file, and they have different answers.
Nothing proprietary is *stored* in this repository. The images the build
*produces* are another matter: they carry the vendor kernel, U-Boot, the PowerVR
blobs, the radio driver and firmware, the prebuilt SDL2 libraries, and in some
lanes the board's own stock kernel modules and boot chain. Building one for your
device is ordinary use of a vendor SDK; publishing one redistributes those vendor
components. See the closing note in [LICENSE](LICENSE) for where this project
stands on that.

## Shaun Inman

The whole approach is Shaun Inman's. Three of his projects are used directly and
two more as references:

**[Moss-zero28](https://github.com/shauninman/Moss-zero28)** (MinUI OS Subsystem
for the MagicX Mini Zero 28; "notes and changes to apply to the default build" of
the Tina SDK; commit `021bb12`, 2025-01-18). It is the recipe this repository
automates. Taken from it, with only the changes noted:

| in oakMOSS | from Moss-zero28 | changes |
|---|---|---|
| `configs/phase1.config`, `configs/phase2.config` | `configs/phase1.config`, `configs/phase2.config` (the two-phase package/toolchain selection his `notes.txt` describes) | `CONFIG_PACKAGE_libmad=y` added (the SDL2_mixer blob needs it) |
| `configs/ext-armgnu13.config`, `configs/phase2-gcc750.config` | derived from the above | see docs/toolchain.md |
| `overlay/etc/rc.local` | `etc/rc.local` (the SDK's default audio mixer setup plus the hand-off call) | none |
| `overlay/etc/banner` | `etc/banner` | none |
| the `/usr/magicx` layout and the hand-off contract (`bin/runmagicx.sh` called from `rc.local`; wait for `/mnt/SDCARD`; run `magicx/init.sh`, else `.tmp_update/updater`, else power off) | `usr/magicx/bin/runmagicx.sh` | `overlay/usr/magicx/bin/runmagicx.sh` is a rewrite that keeps the contract (longer wait, power-off when the hand-off returns, a boot log). His original is not included |
| `overlay/usr/magicx/lib/libSDL2*.so*` | `usr/magicx/lib/` (his selection of the TrimUI Smart Pro SDL2 blobs, see TrimUI below) | none |
| the kernel config notes ("enabled iso8859-1 and utf8, disabled sunxi-vin"), the `add-rootfs-demo` and `tina_config.gz` steps, the OpenixCard conversion, and the warning that copying a config to `.config` re-enables packages | `notes.txt`, `install.sh` | encoded in `sdk-patches/tree/020-kernel-config-4.9.patch` and `scripts/build.sh`; the config warning turned out to be `build/toplevel.mk` copying the board defconfig over `.config` (docs/sdk-mods.md) |

Moss-zero28 carries no license file. Its README presents it as notes for the
community to build from, and that is how it is used here: attributed, not
relicensed. **His `bootlogo.bmp` is deliberately not included**; the image carries
oakMOSS's own logo (see spruceOS below) when `scripts/make-boot-resource.py` has
drawn it into `overlay/`, and the SDK's otherwise. If Shaun Inman objects to
any use here, it will be replaced.

**[main-zero40](https://github.com/dedicated-os/main-zero40)** ("a bare-bones
Tina Linux firmware for the MagicX Zero40"; release `v20260202-1`). Its release
image is downloaded at build time by `scripts/fetch-inputs.sh` and its boot
chain (boot0, U-Boot with the Zero 40 panel, DTB with the touch node, kernel)
becomes the first partitions of the **Zero 40 hybrid image**, with our rootfs in
place of his (`scripts/make-hybrid-zero40.sh`). Nothing from it is stored in this
repository. The repository has no license file; the image is redistributed only
inside builds you make yourself.

**[Dedicated OS for the Zero 40](https://github.com/dedicated-os/dedicated-zero40)**
(`LICENSE.md`: personal, educational and community non-commercial use; commercial
use prohibited; modified versions must be clearly identified and must not use the
project's name or assets). Used as a reference only: its button and axis tables
told us how the Zero 40's pad and stick are wired (docs/hardware-notes.md). No
code or asset from it is included. oakMOSS is not Dedicated OS, not Moss, and not
endorsed by Shaun Inman.

**[MinUI](https://github.com/shauninman/MinUI)** (commit `dbf8943`). Reference
only: the zero28 platform's joystick indices, volume path and hardware notes.
No code included; no license file at that commit.

## MagicX

MagicX provided the Allwinner Tina Linux SDK (`mplus_a133_tina_v1.0`,
`Linux_SDK.zip`) to community developers, and the Zero 40 `sunxi_encrypt` kernel
object (`Zero40-lichee.zip`). Both are proprietary and **not** in this repository;
you obtain them from MagicX and the scripts verify their checksums
(inputs/README.md). The board firmware (boot0, U-Boot 2018, kernel 4.9.191, the
PowerVR blobs, the pack tools) all come from that SDK. The kernel and U-Boot in
it are GPL-2.0; their source is the SDK itself.

MagicX also publishes the XU20 V32 and Zero 40 stock firmware as GitHub releases
(`Magicx-Breeze/XU20_V32`, `Magicx-Breeze/Zero40`). `scripts/unpack-*-stock.sh`
fetch and unpack those; the stock boot chains and vendor kernel modules they
contain are used directly in the hybrid and stock-chain images, and
`boards/xu20/board.dts` and `boards/zero40/board.dts` are **derived in part from
the device trees in that firmware** - decompiled, edited and recompiled, with the
nodes our kernel needs enabled (`scripts/make-board-dts.py`,
`scripts/fdt-enable-nodes.py`). Those two files are therefore not oakMOSS's own
work in the sense LICENSE describes; they carry MagicX's and Allwinner's
hardware description, and the kernel device trees they start from are GPL-2.0.
`boards/zero28/board.dts` is the SDK's own board tree
(`device/config/chips/a133/configs/aw3/board.dts`) with a few properties changed
(docs/sdk-mods.md), and the other two are generated from it. It is Allwinner's
hardware description as the SDK ships it, and not oakMOSS's own work in that
sense either.

## Allwinner

Tina Linux is Allwinner's OpenWrt-derived SDK (OpenWrt build system: GPL-2.0;
Allwinner additions under their own terms). The prebuilt `aarch64-openwrt-linux-gnu`
GCC 6.4 (Linaro) inside it still builds the GE8300 kernel module, and its binutils link the
kernel.
The XR829 WiFi/Bluetooth driver and firmware and the `sunxi_encrypt` object are
Allwinner/XRadio proprietary components shipped inside the SDK.

## TrimUI

`overlay/usr/magicx/lib/` holds four prebuilt shared libraries, taken as
Moss-zero28 ships them: `libSDL2-2.0.so.0.2600.1`, `libSDL2_image-2.0.so.0.2.3`,
`libSDL2_mixer-2.0.so.0.0.1`, `libSDL2_ttf-2.0.so.0.14.1`. SDL2, SDL2_image,
SDL2_mixer and SDL2_ttf are under the zlib license, which permits binary
redistribution; TrimUI published the patched SDL2 2.26.1 source (GE8300 support)
in its Smart Pro SDK. `libSDL2_mixer` is linked against libmad (GPL-2.0), which
the image builds from source (`dl/libmad-0.15.1b.tar.gz` in the SDK).

On the Zero 28 and Zero 40 `libSDL2_mixer` is not the borrowed one: `scripts/build-sdl2-mixer.sh` builds
SDL2_mixer 2.8.0 (zlib licence; its stb_vorbis, dr_flac and minimp3 keep their own terms) from source and installs
it over it, because 2.0.1 cannot load Ogg.

They do not all come from one build. `libSDL2_image`, `libSDL2_mixer` and
`libSDL2_ttf` carry a `RUNPATH` and toolchain strings from a TrimUI Smart Pro SDK
build tree (`tina_smartpro_4.0.0`, `a133-aw3`, GCC 7.4.1 OpenWrt); `libSDL2`
itself carries no `RUNPATH` and its build-root strings name a different tree
(`SDL2-2.26.1.mali-zero`), so it is not from the same build as the other three
and its exact origin is not established here. All four are shipped **unmodified**
and are meant to stay that way: they are somebody else's binaries, the embedded
build paths are theirs and already present in the upstream firmware, and
rewriting them would make these files no longer the artifacts being attributed.
Replacing them with an SDL2 built from source in this tree is a TODO.md item.

The TrimUI Brick image (`boards/brick`) carries two more sets of TrimUI's binaries, unmodified, from
TrimUI's public 1.1.1 firmware for the Brick (`scripts/unpack-trimui-stock.sh`): its boot0, BL31, SCP
and device tree (the U-Boot item in that package is ours, `scripts/make-brick-own-uboot.py`), and the
closed input daemon `trimui_inputd`, which reads the Brick's buttons. They are TrimUI's, redistributed
on the footing the LICENSE note describes; a free replacement for the daemon is an open item
(`docs/trimui.md`).

## Powkiddy

The Powkiddy V90S and V20 images (`boards/v90s`, `boards/v20`, `scripts/make-own-kernel-stock.sh`) boot
on each board's own stock boot chain, taken from its stock firmware (`scripts/unpack-powkiddy-stock.sh`):
Powkiddy's boot0, the U-Boot package with its U-Boot and SCP, and the stock boot-resource. They are
unmodified but for the package's device tree, which is ours (its checksum redone), and oakMOSS's pictures
in the boot-resource. The V90S's come from its stock firmware as Knulli ships it; the V20's were read off
a V20's own stock card. They are Powkiddy's, redistributed on the footing the LICENSE note describes. The
update packages (`oakmoss-<board>-own-<version>.omupd`) carry none of them.

`boards/v90s/board.dts` and `boards/v20/board.dts` are each board's stock device tree, decompiled and
edited (`scripts/make-board-dts-powkiddy.py`). Like the MagicX trees above, they are not oakMOSS's own
work in the sense LICENSE describes: they carry Powkiddy's and Allwinner's hardware description, and the
kernel device trees they start from are GPL-2.0.

## Hynitron, via Radxa

The GPL-2.0 text this section refers to is in `LICENSES/GPL-2.0.txt`.

`sdk-patches/tree/080-touch-hynitron-axs15205.patch` carries Hynitron's own
capacitive touch driver for the XU20's CST340 (`hynitron_core.[ch]`,
`hynitron_i2c.c`, `hynitron_common.h`, `hynitron_config.h`,
`hynitron_update_firmware.[ch]`, `hynitron_gesture.c`, `hynitron_proximity.c`,
`hynitron_esd_check.c`). It is Hynitron's work, carrying their author string
(`zxzz`) and `MODULE_LICENSE("GPL v2")`, and it is redistributed here under
GPL-2.0 with those notices intact. It was taken from Radxa's `allwinner-bsp`
tree (`drivers/input/ctp/hynitron`), which is where it exists in the Allwinner
`ctp`/`init-input` framework flavour this kernel needs.

oakMOSS's changes to it are three, each marked in place: the I2C address is
taken from the device tree node's `reg` rather than the driver's compile-time
default, the axis flags come from the `ctp` node, and an `-EBUSY` on the reset
and interrupt lines is accepted because the `ctp` framework requests them
first. Hynitron's ~1.3 MB of built-in firmware images are **not** carried: the
table that reads them is guarded behind the auto-update switches, which are
off, so the panel keeps the firmware it shipped with. The vendor's
`hynitron_tool_debug.c`, which nothing builds, is also left out.

The same patch adds `axs15205/axs15205.c` for the Zero 40's AXS15205. That file
is oakMOSS's own work under GPL-2.0, written from the behaviour of the board's
stock kernel rather than from vendor source: the frame format, the read
protocol and the probe timing were read out of that kernel's own driver by
disassembly (`docs/hardware-notes.md`, "Touch"). The AiXieSheng `axs_ts`
sources circulating publicly are a different, command-prefixed protocol and are
not used here.

## Imagination Technologies

PowerVR GE8300: the kernel module source (`rogue_km`, dual MIT/GPL-2.0) is built
by the SDK; the userland `libEGL`, `libGLESv2`, `libIMGegl`, `libsrv_um`, `libusc`,
`libglslcompiler` and the `rgx.fw.*` firmware are proprietary blobs from the SDK.

## Ithamar Adema: awutils

[awutils](https://github.com/Ithamar/awutils) (`awimage`) unpacks the Allwinner
PhoenixSuit image the XU20's stock firmware ships as. Built from source at a
pinned commit (`3f1cbb2`) by `scripts/build-awutils.sh`; not included. The
repository carries no license file. `tools-patches/awutils-imagewty-0x415.patch`
is oakMOSS's own one-line change, teaching `decrypt_image()` to accept the
`0x0415` IMAGEWTY header version the XU20 firmware uses alongside the `0x0300`
it already knew; it is offered under the same terms as the project it patches.

## unix3dgforce: lpunpack

[lpunpack](https://github.com/unix3dgforce/lpunpack) splits the Android dynamic
`super` partition into `vendor.img` so the XU20's vendor kernel modules can be
read out of its stock firmware. Cloned at a pinned commit (`c59b8f3`) by
`scripts/unpack-xu20-stock.sh`; not included. The sparse-image reader in that
script is oakMOSS's own forty-line implementation of the Android sparse format,
not a copy of `simg2img`.

## YuzukiTsuru: OpenixCard

[OpenixCard](https://github.com/YuzukiTsuru/OpenixCard) (GPL-2.0) converts
Allwinner's PhoenixSuit image into a raw GPT image. Built from source at a pinned
commit by `scripts/build-openixcard.sh`; not included.

## Arm: GNU Toolchain 13.3.Rel1

[Arm GNU Toolchain](https://developer.arm.com/Tools%20and%20Software/GNU%20Toolchain)
13.3.Rel1 `aarch64-none-linux-gnu` (GCC: GPL-3.0 with the GCC Runtime Library
Exception; glibc: LGPL-2.1; binutils: GPL-3.0). Downloaded and checksum-verified
by `scripts/fetch-inputs.sh`; not included. The image ships its runtime
libraries: glibc 2.38 (`ld-linux-aarch64.so.1`, `libc.so.6`, ...), `libstdc++.so.6`
(GLIBCXX_3.4.32), `libgcc_s.so.1`, `libatomic.so.1`, `libgomp.so.1`. `sdk-patches/toolchain/arm-gnu-wrapper.sh`
and the `tina-sysroot` shim are oakMOSS's.

## OpenWrt

- `sdk-patches/ncurses-6.2/`: the ncurses 6.2 package from OpenWrt v21.02.7
  (`package/libs/ncurses`, GPL-2.0), adapted to the Tina tree (`$(INCLUDE_DIR)` to
  `$(BUILD_DIR)`, `--with-termlib=tinfo`, libtinfo installed).
- `sdk-patches/openssl-1.1.1w/`: the SDK's OpenSSL package brought to 1.1.1w with the
  configure and compile steps and patches 100, 110, 120 and 130 of OpenWrt 22.03's
  (`package/libs/openssl` on `openwrt-22.03`, GPL-2.0); its `include/crypto/cryptodev.h` is
  cryptodev-linux's public-domain header, carried as the SDK has it.
- `sdk-patches/gcc-7.5.0-patches/`: OpenWrt v19.07.10's GCC 7.5.0 patch set
  (`toolchain/gcc/patches/7.5.0`, GPL-2.0), for the fallback from-source toolchain.

## GNU and other upstream sources fetched at build time

ncurses 6.2 (MIT-style ncurses license), bluez-alsa 4.0.0 (Arkadiusz Bokowy, MIT;
github.com/arkq/bluez-alsa tag v4.0.0, replacing the SDK's 2018 snapshot through tree patch
133), zlib 1.3.1 (Jean-loup Gailly and Mark Adler, zlib license; zlib.net, replacing the
SDK's 1.2.8 through tree patch 135), OpenSSL 1.1.1w (OpenSSL and SSLeay licenses; openssl.org,
replacing the SDK's 1.1.0i through `sdk-patches/openssl-1.1.1w`), GCC 7.5.0 and binutils 2.28 (GPL-3.0,
fallback toolchain only), and glibc 2.29 from sourceware git (LGPL-2.1, fallback
only). libmad 0.15.1b (Underbit, GPL-2.0), BusyBox 1.27.2 (GPL-2.0), BlueZ 5.54
(GPL-2.0 / LGPL-2.1), e2fsprogs 1.42.12 (GPL-2.0 / LGPL-2.0), libubox (ISC),
util-linux 2.25.2 (GPL-2.0 / LGPL-2.1), libffi (MIT) and the other packages the
SDK builds come from its `dl/` directory under their own licenses. The small
patches under `sdk-patches/package-patches/` and `sdk-patches/tree/` that touch
those packages are offered under the license of the package they modify.

## The oakMOSS libraries (`/usr/lib/oakmoss`)

Every image carries 130 shared libraries in `/usr/lib/oakmoss` ([docs/flip-set.md](docs/flip-set.md)):
the Zero 28, Zero 40 and XU20 images from v0.6.0-beta.1 on, and the V90S, V20 and Brick images from
their first release, v0.7.0-beta.1. None of them is stored in this repository.
`scripts/build-ports-userland.sh` (`PORTS_SET=flip`) builds each one from its upstream source release,
with the options and the few source edits written in that script. `inputs/userland/urls.txt` names
every source archive and `inputs/userland/SHA256SUMS` its checksum, and each archive carries its own
licence text. In an image, `/usr/lib/oakmoss/BUILD-INFO` names the oakMOSS commit the set was built
from and `/usr/lib/oakmoss/SHA256SUMS` lists its files.

An image that carries the set carries these libraries under their own licences. Three are
GPL-2.0-or-later: a52dec, libmpeg2 and FAAD2. The LGPL ones are separate shared objects in one
folder, so each can be rebuilt and replaced. For every library the source is the archive named in
`urls.txt`, built by the recipe in that script.

| Source | Licence | Libraries |
|---|---|---|
| FFmpeg 4.4.5 | LGPL-2.1-or-later (configured without `--enable-gpl`, `--enable-version3` and `--enable-nonfree`) | `libavcodec.so.58`, `libavformat.so.58`, `libavutil.so.56`, `libswresample.so.3`, `libswscale.so.5` |
| a52dec 0.7.4 | GPL-2.0-or-later | `liba52-0.7.4.so` |
| libmpeg2 0.5.1 (mpeg2dec) | GPL-2.0-or-later | `libmpeg2.so.0` |
| FAAD2 2.10.1 | GPL-2.0-or-later | `libfaad.so.2` |
| LAME 3.100 | LGPL-2.0-or-later | `libmp3lame.so.0` |
| mpg123 1.32.9 | LGPL-2.1 | `libmpg123.so.0` |
| OpenAL Soft 1.23.1 | LGPL-2.0-or-later | `libopenal.so.1` |
| PulseAudio 13.99.1 (the client libraries) | LGPL-2.1-or-later; built with D-Bus, which is AFL-2.1 or GPL-2.0-or-later | `libpulse.so.0`, `libpulse-simple.so.0`, `libpulsecommon-13.99.so` |
| AppArmor 3.0.13 (libapparmor) | LGPL-2.1 | `libapparmor.so.1` |
| libasyncns 0.8 | LGPL-2.1-or-later | `libasyncns.so.0` |
| systemd 249.17 (libsystemd alone) | LGPL-2.1-or-later | `libsystemd.so.0` |
| keyutils 1.6.1 (the library) | LGPL-2.1-or-later | `libkeyutils.so.1` |
| libtasn1 4.16.0 | LGPL-2.1-or-later | `libtasn1.so.6` |
| GnuTLS 3.6.16 | LGPL-2.1-or-later | `libgnutls.so.30` |
| libgcrypt 1.8.11, libgpg-error 1.47 | LGPL-2.1-or-later | `libgcrypt.so.20`, `libgpg-error.so.0` |
| libxcrypt 4.4.36 | LGPL-2.1-or-later, with permissively licensed parts | `libcrypt.so.1` |
| cairo 1.16.0 | LGPL-2.1 or MPL-1.1 | `libcairo.so.2` |
| FriBidi 1.0.8 | LGPL-2.1-or-later | `libfribidi.so.0` |
| Game_Music_Emu 0.6.3 | LGPL-2.1-or-later | `libgme.so.0` |
| libmikmod 3.3.11.1 | LGPL-2.0-or-later | `libmikmod.so.3` |
| libxmp 4.6.0 | LGPL-2.1-or-later | `libxmp.so.4` |
| Speech Dispatcher 0.11.5 (the client library) | LGPL-2.1-or-later | `libspeechd.so.2` |
| Nettle 3.5.1 and 3.7.3 | LGPL-3.0-or-later or GPL-2.0-or-later | `libnettle.so.7`, `libhogweed.so.5`, `libnettle.so.8`, `libhogweed.so.6` |
| GMP 6.2.1 | LGPL-3.0-or-later or GPL-2.0-or-later | `libgmp.so.10` |
| libidn2 2.3.0 | LGPL-3.0-or-later or GPL-2.0-or-later | `libidn2.so.0` |
| libunistring 0.9.10 | LGPL-3.0-or-later or GPL-2.0-or-later | `libunistring.so.2` |
| OpenSSL 1.1.1w | OpenSSL and SSLeay licences | `libssl.so.1.1`, `libcrypto.so.1.1` |
| OpenLDAP 2.4.59 | OpenLDAP Public License 2.8 | `liblber-2.4.so.2`, `libldap_r-2.4.so.2` |
| Cyrus SASL 2.1.28 | Carnegie Mellon's BSD-style licence, with its attribution clause | `libsasl2.so.2` |
| MIT Kerberos 1.17.2 | MIT (the krb5 `NOTICE`) | `libgssapi_krb5.so.2`, `libkrb5.so.3`, `libk5crypto.so.3`, `libkrb5support.so.0` |
| Heimdal 7.7.1 | BSD-3-Clause | `libasn1.so.8`, `libgssapi.so.3`, `libhcrypto.so.4`, `libheimbase.so.1`, `libheimntlm.so.0`, `libhx509.so.5`, `libkrb5.so.26`, `libroken.so.18`, `libwind.so.0` |
| e2fsprogs 1.47.0 (com_err alone) | MIT-style | `libcom_err.so.2` |
| ICU 63.2 | Unicode licence (ICU's `LICENSE`, with its third-party notices) | `libicudata.so.63`, `libicuuc.so.63`, `libicui18n.so.63` |
| Python 3.10.19 | Python Software Foundation License 2.0 | `libpython3.10.so.1.0`, `libpython3.so` |
| Tcl 8.6.14, Tk 8.6.14 | Tcl/Tk licence (BSD-style) | `libtcl8.6.so`, `libtk8.6.so` |
| Boost 1.71.0 | Boost Software License 1.0 | `libboost_filesystem.so.1.71.0` |
| libjpeg-turbo 2.1.5 | IJG, BSD-3-Clause and zlib | `libjpeg.so.8` |
| libpng 1.6.43 | libpng licence | `libpng16.so.16` |
| LibTIFF 4.2.0 | libtiff licence (BSD-style) | `libtiff.so.5` |
| giflib 5.2.1 | MIT | `libgif.so.7` |
| libwebp 1.0.3 | BSD-3-Clause, with Google's patent grant | `libwebp.so.7`, `libwebpdemux.so.2` |
| libavif 1.0.4 | BSD-2-Clause | `libavif.so.16` |
| dav1d 1.2.1 | BSD-2-Clause | `libdav1d.so.6` |
| libvpx 1.6.1, 1.8.2, 1.11.0 and 1.13.1 | BSD-3-Clause, with Google's patent grant | `libvpx.so.4`, `libvpx.so.6`, `libvpx.so.7`, `libvpx.so.8` |
| libogg 1.3.5, libvorbis 1.3.7, libtheora 1.1.1 | BSD-3-Clause | `libogg.so.0`, `libvorbis.so.0`, `libvorbisfile.so.3`, `libvorbisenc.so.2`, `libtheoradec.so.1`, `libtheoraenc.so.1` |
| Tremor (libvorbisidec) 1.2.1+git20180316 | BSD-3-Clause | `libvorbisidec.so.1` |
| Opus 1.4, opusfile 0.12 | BSD-3-Clause (Opus with its patent licences) | `libopus.so.0`, `libopusfile.so.0` |
| Speex 1.2.1 | BSD-3-Clause | `libspeex.so.1` |
| WavPack 5.6.0 | BSD-3-Clause | `libwavpack.so.1` |
| libopenmpt 0.4.11 | BSD-3-Clause | `libopenmpt.so.0` |
| libmodplug 0.8.9.0 | public domain | `libmodplug.so.1` |
| XZ Utils 5.4.7 (liblzma) | public domain | `liblzma.so.5` |
| Zstandard 1.5.6 | BSD-3-Clause or GPL-2.0 | `libzstd.so.1` |
| LZ4 1.9.4 (the library) | BSD-2-Clause | `liblz4.so.1` |
| Brotli 1.0.9 | MIT | `libbrotlicommon.so.1`, `libbrotlidec.so.1` |
| libzip 1.5.2 | BSD-3-Clause | `libzip.so.5` |
| nghttp2 1.40.0 | MIT | `libnghttp2.so.14` |
| libpsl 0.21.0 | MIT | `libpsl.so.5` |
| p11-kit 0.23.22 | BSD-3-Clause | `libp11-kit.so.0` |
| libffi 3.3 | MIT | `libffi.so.7` |
| libbsd 0.10.0 | BSD-3-Clause and the other permissive licences in its `COPYING` | `libbsd.so.0` |
| libcap 2.69 | BSD-3-Clause or GPL-2.0 | `libcap.so.2` |
| tcp_wrappers 7.6, with Debian's 7.6.q-31 patches | Wietse Venema's BSD-style licence | `libwrap.so.0` |
| liblcf 0.8 | MIT | `liblcf.so.0` |
| SDL2_image 2.8.2, SDL2_mixer 2.8.0, SDL2_ttf 2.22.0 | zlib; the decoders and font code bundled in them (stb, dr_flac, minimp3, Timidity, FreeType, HarfBuzz) keep their own terms | `libSDL2_image-2.0.so.0`, `libSDL2_mixer-2.0.so.0`, `libSDL2_ttf-2.0.so.0` |
| SDL2_gfx 1.0.4, SDL2_net 2.2.0 | zlib | `libSDL2_gfx-1.0.so.0`, `libSDL2_net-2.0.so.0` |
| pixman 0.42.2 | MIT | `libpixman-1.so.0` |
| fontconfig 2.12.6 | MIT-style | `libfontconfig.so.1` |
| X.Org: libX11 1.8.7, libXext 1.3.5, libXfixes 6.0.1, libXrender 0.9.11, libXcursor 1.2.1, libXi 1.8.1, libXrandr 1.5.4, libXScrnSaver 1.2.4, libXau 1.0.11, libXdmcp 1.1.4, libICE 1.1.1, libSM 1.2.4, libxcb 1.16 | MIT and the X.Org family's other permissive licences (each archive's `COPYING`) | `libX11.so.6`, `libXext.so.6`, `libXfixes.so.3`, `libXrender.so.1`, `libXcursor.so.1`, `libXi.so.6`, `libXrandr.so.2`, `libXss.so.1`, `libXau.so.6`, `libXdmcp.so.6`, `libICE.so.6`, `libSM.so.6`, `libxcb.so.1`, `libxcb-render.so.0`, `libxcb-shm.so.0` |
| Wayland 1.22.0 | MIT | `libwayland-client.so.0`, `libwayland-cursor.so.0`, `libwayland-egl.so.1` |
| waylandpp 1.0.0 | BSD-2-Clause | `libwayland-egl++.so.1` |
| libxkbcommon 1.6.0 | MIT and X.Org-style | `libxkbcommon.so.0` |
| libdecor 0.2.2 | MIT | `libdecor-0.so.0` |

The other archives in `urls.txt` are build-time inputs (headers, protocol descriptions and link-time
copies of libraries the image already has, such as zlib, expat, SQLite, FreeType, SDL2, ALSA and
D-Bus) or belong to the card lanes. No library of theirs is in `/usr/lib/oakmoss`.

## Realtek USB WiFi drivers

The V90S and V20 have no radio of their own, so their images carry two kernel modules for USB WiFi
dongles in `/usr/lib/oakmoss/modules/usb-wifi`, with a `PROVENANCE.txt` beside them: `8188eu.ko` from
[lwfinger/rtl8188eu](https://github.com/lwfinger/rtl8188eu) (commit `f42fc9c`) and `8812au.ko` from
[aircrack-ng/rtl8812au](https://github.com/aircrack-ng/rtl8812au) (commit `7344855`). Both are Realtek's
drivers under GPL-2.0. `scripts/fetch-inputs.sh` fetches the two sources at those commits (sha256 in
`scripts/lib.sh`) and `scripts/build-usb-wifi.sh` builds them against this kernel; neither is stored
here. `sdk-patches/usb-wifi/8188eu-0001-build-on-4.9-random-guard-typo-and-timer-shim.patch` is oakMOSS's
build fix for kernel 4.9, offered under the driver's licence. An image that carries the modules carries
GPL-2.0 code; its source is those two commits and that patch.

## Mikhailzrick: BatteryPlus

**[knubat.components](https://github.com/Mikhailzrick/knubat.components)**
`BatteryPlus/batteryplus.cpp`, the battery daemon Knulli ships (commit `1c31e89`,
2026-07-31; GPL-2.0). `scripts/fetch-inputs.sh` fetches it (sha256 in `scripts/lib.sh`) and
`build.sh` compiles it unmodified into the image's `/usr/magicx/bin/batteryplus`. Its
configuration and init script in `overlay/etc/` are oakMOSS's own
([docs/batteryplus.md](docs/batteryplus.md)). An image that carries the binary carries a
GPL-2.0 program; its source is that commit.

## Knulli: panel drivers

`sdk-patches/tree/150-lcd-panel-rgp35-nv3051.patch` (the Powkiddy V90S and V20 panel, RGP35_NV3051):
its power sequence and 27-entry init table are [Knulli](https://github.com/knulli-cfw/knulli-linux)'s
reconstruction from the stock V90S kernel (GPL-2.0). It sits on the 4.9 disp2 calls that patch 070 uses.
A kernel patch: the kernel built with it is GPL-2.0, as always.

`sdk-patches/tree/160-lcd-panel-trimui-a133p.patch` (the TrimUI Brick, Brick Pro and Smart Pro panel,
`otm1289a`) ports Knulli's `board/allwinner/a133/panels/trimui_brick.c` and its generated
`trimui_brick_panels.h` (branch `development`, commit `f727825f`, 2026-10-18; GPL-2.0): the init tables
Knulli recovered from the stock firmware, unchanged; the driver is adapted to the 4.9 disp2 calls and
takes the stock U-Boot's `lcd=` first. A kernel patch, GPL-2.0.

## ROCKNIX: the Powkiddy joypad's axis handling

`sdk-patches/tree/151-input-adc-joypad-powkiddy.patch` is a new driver for the stock tree's
`adc-joypad` binding. The stock kernel's driver is a port of [ROCKNIX](https://github.com/ROCKNIX)'s
`rocknix-singleadc-joypad` (GPL-2.0). This one's axis maths and defaults follow that driver: the mux
channel table, calibration at open, the scaled radial deadzone, and tuning in percent. So the stock
tree's tuning values mean the same thing. Kernel code, GPL-2.0.

## spruceOS

[spruceOS](https://github.com/spruceUI/spruceOS) (CC BY-NC 4.0) is the launcher
these images exist to boot; it lives on the user card. One file comes from it:
`assets/spruce-tree.png` is spruceOS's tree mark (`spruce/imgs/tree_sm_close_crop.png`),
which `scripts/make-boot-resource.py` turns into the oakMOSS boot logo. Both are
spruceUI projects under the same license.
The `docs/DEPENDENCIES.md` study was written against its tree to size the base
image's userland.

## Other references

[Knulli](https://github.com/knulli-cfw/knulli-linux) (in-tree a133 boards for
these devices) and the TrimUI Smart Pro SDK were read while researching the
platform (docs/DEPENDENCIES.md, docs/toolchain.md). Nothing from them is included beyond the panel
drivers above (150, 160). The V90S's stock boot chain is fetched from Knulli's board files at a pinned commit
(`scripts/lib.sh`) and is not redistributed; so is the TrimUI Brick's, from TrimUI's public firmware release.
