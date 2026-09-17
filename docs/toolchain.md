# Toolchain

## Why the userland is built with Arm GNU 13.3 and not the SDK's toolchain

Moss-zero28 builds the rootfs twice: phase 1 with the SDK's prebuilt Linaro
GCC 6.4 / glibc 2.23, then phase 2 with a from-source Linaro GCC 7.4 / glibc 2.29
/ binutils 2.28 toolchain. That gives a libstdc++ capped at `GLIBCXX_3.4.24`.

`docs/DEPENDENCIES.md` (an ELF-closure survey of everything the spruceOS card
runs) shows that is not enough for the launcher's payload: RetroArch
(`ra64.universal`) needs `GLIBCXX_3.4.26`, flycast, yabasanshiro and the GLideN64
plugins need newer symbols still, four `bin64` tools want `GLIBC_2.34`, and
PortMaster's Godot/FRT and Solarus runtimes need `GLIBCXX_3.4.26`. spruceOS ships
no aarch64 libstdc++ of its own: on the TrimUI Smart Pro the vendor rootfs
provides it (its `LD_LIBRARY_PATH` starts with `/usr/trimui/lib`). So the base
image has to.

Two more facts closed the door on the Moss toolchain: Linaro's site no longer
serves `gcc-linaro-7.4-2019.02.tar.xz` (the SDK's `dl/` has no copy and no mirror
was found), and even the GNU GCC 7.5.0 stand-in added for it
(`sdk-patches/tree/030-*`, `configs/phase2-gcc750.config`) would still cap
libstdc++ too low.

## What the build does instead

Tina's OpenWrt build system supports an external toolchain. The override in
`sdk-patches/tree/010-rules-mk-external-toolchain-override.patch` is driven by
environment variables (`TINA_EXT_TOOLCHAIN_ROOT`, `_PREFIX`, `_TARGET_NAME`,
`_SYSROOT`, `TINA_EXT_KERNEL_CROSS`) so that the SDK is untouched unless
`scripts/run-in-sdk.sh` sets them (`TOOLCHAIN=armgnu13`, the default):

- Userland: Arm GNU Toolchain 13.3.Rel1 `aarch64-none-linux-gnu` (glibc 2.38,
  `GLIBCXX_3.4.32`, glibc's minimum kernel 3.7.0, so fine on 4.9.191).
- Kernel and the PowerVR GE8300 kernel module: the SDK's own GCC 6.4 through
  `KERNEL_CROSS` (`sdk-patches/tree/040-gpu-km-kernel-cross.patch` makes the
  module use it too; the rogue_km build keys its compiler config on the prefix).
- `tina-sysroot/`: the SDK's `CONFIG_LIBC_FILE_SPEC` globs expect glibc under
  `./lib` and libstdc++/libgcc_s/libatomic under `./usr/lib`; Arm keeps them in
  `lib64/`. `scripts/prepare-toolchain.sh` copies them into that shape. The
  override sets the file specs twice because `rules.mk` reassigns
  `CONFIG_LIBC_FILE_SPEC` late (the second block is marked `TINA_EXT_LIBC_SPEC_LATE`).
  `./lib/libc.so -> libc.so.6` is there for Allwinner's prebuilt
  `libresamplerate_64.so`, which NEEDs the unversioned name.
- `wrap/`: Allwinner's prebuilt toolchain has a sysroot pre-populated with
  package headers and libraries, so several Tina packages (libsocket_db,
  ustream-ssl, jsonfilter, usign, ubus) compile without any CPPFLAGS/LDFLAGS. A
  clean toolchain needs the OpenWrt staging paths injected: the wrapper appends
  `-idirafter $STAGING_DIR/{usr/include,include,usr/include/libxml2}` and
  trailing `-L`/`-rpath-link`. `CONFIG_TOOLCHAIN_BIN_PATH="./wrap ./bin"` puts it first.

GCC 13 against 2017-era packages needed the fixes listed in `docs/sdk-mods.md`
(`-fcommon`, a set of `-Wno-error=` flags for packages that build with `-Werror`,
uClibc++ replaced by libstdc++, ncurses 5.9 replaced by 6.2, libffi's multi-os
directory, and one-line patches to busybox, bluez, e2fsprogs, libubox).

## Fallbacks

- `scripts/build.sh phase1` / `phase2` with `TOOLCHAIN=vendor` run Moss's recipe
  as published (`configs/phase1.config`, then `configs/phase2-gcc750.config`;
  `configs/phase2.config` if the Linaro 7.4 tarball ever reappears in `dl/`).
  The result boots but cannot run spruce's RetroArch.
- Bootlin's `aarch64--glibc--stable-2022.08-1` (GCC 11.3, glibc 2.35, kernel
  headers 4.9) is the next candidate if GCC 13 ever breaks too many SDK packages.
  It has not been needed.

## Iterating on the SDK

- `scripts/build.sh cont` resumes the current build without wiping.
- After changing a package Makefile: `rm -rf sdk/lichee/out/a133-aw3/compile_dir/target/<pkg>-*`.
- After changing the libc file spec: `rm -rf sdk/lichee/out/a133-aw3/compile_dir/target/toolchain`.
- The kernel's non-interactive `silentoldconfig` aborts on NEW symbols: resolve
  them with `make olddefconfig` in `lichee/linux-4.9` and append the result to
  `config-4.9` (that is where the XRADIO block in `020-kernel-config-4.9.patch` came from).
- `build/toplevel.mk` copies `target/allwinner/a133-aw3/defconfig` over `.config`
  on every `make`, so a config only sticks when installed there (`build.sh` does).
