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
relicensed. **His `bootlogo.bmp` is deliberately not included**; the image keeps
the SDK's own logo unless you drop one into `overlay/`. If Shaun Inman objects to
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

## Allwinner

Tina Linux is Allwinner's OpenWrt-derived SDK (OpenWrt build system: GPL-2.0;
Allwinner additions under their own terms). The prebuilt `aarch64-openwrt-linux-gnu`
GCC 6.4 (Linaro) inside it still builds the kernel and the GE8300 kernel module.
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
(GLIBCXX_3.4.32), `libgcc_s.so.1`, `libatomic.so.1`. `sdk-patches/toolchain/arm-gnu-wrapper.sh`
and the `tina-sysroot` shim are oakMOSS's.

## OpenWrt

- `sdk-patches/ncurses-6.2/`: the ncurses 6.2 package from OpenWrt v21.02.7
  (`package/libs/ncurses`, GPL-2.0), adapted to the Tina tree (`$(INCLUDE_DIR)` to
  `$(BUILD_DIR)`, `--with-termlib=tinfo`, libtinfo installed).
- `sdk-patches/gcc-7.5.0-patches/`: OpenWrt v19.07.10's GCC 7.5.0 patch set
  (`toolchain/gcc/patches/7.5.0`, GPL-2.0), for the fallback from-source toolchain.

## GNU and other upstream sources fetched at build time

ncurses 6.2 (MIT-style ncurses license), GCC 7.5.0 and binutils 2.28 (GPL-3.0,
fallback toolchain only), and glibc 2.29 from sourceware git (LGPL-2.1, fallback
only). libmad 0.15.1b (Underbit, GPL-2.0), BusyBox 1.27.2 (GPL-2.0), BlueZ 5.54
(GPL-2.0 / LGPL-2.1), e2fsprogs 1.42.12 (GPL-2.0 / LGPL-2.0), libubox (ISC),
util-linux 2.25.2 (GPL-2.0 / LGPL-2.1), libffi (MIT) and the other packages the
SDK builds come from its `dl/` directory under their own licenses. The small
patches under `sdk-patches/package-patches/` and `sdk-patches/tree/` that touch
those packages are offered under the license of the package they modify.

## spruceOS

[spruceOS](https://github.com/spruceUI/spruceOS) (CC BY-NC 4.0) is the launcher
these images exist to boot. Nothing from it is included; it lives on the user card.
The `docs/DEPENDENCIES.md` study was written against its tree to size the base
image's userland.

## Other references

[Knulli](https://github.com/knulli-cfw/knulli-linux) (in-tree a133 boards for
these devices) and the TrimUI Smart Pro SDK were read while researching the
platform (docs/DEPENDENCIES.md, docs/toolchain.md); nothing from them is included.
