# Building oakMOSS

The build turns the vendor's Tina SDK into one SD1 image per board. Each result lands in
`builds/<stamp>-<board>/`, beside a `BUILD-INFO.txt` that records what went into it: the
SDK checksum, toolchain, kernel object, U-Boot and overlay hashes, and the C library.

## What the image contains

A glibc 2.38 / libstdc++ 13 userland (Arm GNU Toolchain 13.3; why newer than Moss's:
`docs/toolchain.md`) on the vendor's 4.9.191 kernel, with ncurses 6, libmad, bluez with
bluez-alsa 4.0.0, and a BusyBox that has unzip, losetup and stat. The kernel has loop
devices, uinput and joydev built in, squashfs that reads XZ, LZO, LZ4, gzip and zstd
images, and drivers for both radios (XR829, Realtek 8189es). The PowerVR GE8300 blobs are
included, and the TrimUI SDL2 libraries the launcher expects are under `/usr/magicx/lib`.

## What you need

**A Linux host with Docker.** The SDK only builds in an Ubuntu 18.04 userland, and the
scripts build that container for you. Host packages:
`git curl unzip xz-utils squashfs-tools util-linux cmake build-essential libconfuse-dev pkg-config automake autoconf`,
plus `python3-pil fonts-dejavu-core` for the pictures the scripts draw (boot logo,
bootloader and charge screens).

**About 45 GB of disk** for the inputs and one board's build. The unpacked SDK takes ~18 GB,
~30 GB once built; `inputs/` holds ~13 GB of archives; every extra image lane adds its own
build tree. `OAKMOSS_WORK` moves the large trees to another disk (`scripts/lib.sh`).

**The inputs.** Part of what the build needs is proprietary and never stored in this
repository. `scripts/fetch-inputs.sh` downloads and verifies everything that is public
(including the XU20's and Zero 40's stock firmwares, which are public releases), then
reports what is still missing and where it goes.

## Steps

```sh
scripts/fetch-inputs.sh             # public inputs, and a check for the private ones
scripts/prepare-toolchain.sh        # Arm GNU 13.3 plus the Tina sysroot and wrapper shims
scripts/build-openixcard.sh         # OpenixCard from source (Allwinner image -> raw image)
scripts/unpack-sdk.sh --remove-zip  # stream the SDK out of its zip and verify it
scripts/apply-sdk-mods.sh           # every SDK change (docs/sdk-mods.md); safe to rerun
scripts/build.sh uboot              # our U-Boot with the Zero 40 and XU20 panels (after every SDK unpack)
scripts/make-boot-resource.py --logo zero28 overlay/bootlogo.bmp   # optional: the oakMOSS boot logo
scripts/build.sh all zero28 zero40 xu20   # the userland (~20-40 min on 8 cores), then one image per board
```

`scripts/build.sh image <board>` rebuilds one board's image without the userland step. The
image to flash is `builds/<stamp>-<board>/oakmoss-<board>-<stamp>-sd1.img`; `COMPRESS=1` also
writes an `.img.xz`. Beside it, `oakmoss-<board>-<version>.omupd` updates a card that already
has two slots (`docs/updates.md`). `build.sh image` refuses a U-Boot binary that lacks the panels, or an
Android one: after a fresh SDK unpack, run `build.sh uboot` first.

### The image lanes

Only the first row is what a board should run today. The others are how the boards were
brought up, and stay in the repository for reference.

| image | boards | what it is |
|---|---|---|
| `oakmoss-<board>-<stamp>-sd1.img` | Zero 28, Zero 40, XU20 V32 | **The one to flash.** The whole chain is ours or the SDK's: SDK boot0 and ATF/SCP, our U-Boot with the boards' panels (`sdk-patches/tree/103`), our device tree, kernel and root filesystem. It is the only chain that reaches charge mode. |
| `oakmoss-<board>-own-<stamp>-sd1.img` | XU20 V32, Zero 40 | The board's stock boot0 and U-Boot in front of our kernel, device tree and root filesystem (`scripts/make-own-kernel-stock.sh`). Used until 2026-09-28; a board plugged in while off stays off. |
| `oakmoss-zero40-stock-<stamp>-sd1.img` | Zero 40 | The Zero 40's stock firmware chain and Android kernel with our root filesystem (`scripts/make-hybrid-zero40-stock.sh`). |
| `oakmoss-xu20-hybrid-<stamp>-sd1.img` | XU20 V32 | The XU20's stock boot chain and Android kernel with the Zero 40 root filesystem (`scripts/make-hybrid-xu20.sh`). Never booted on a unit. |
| `oakmoss-zero40-hybrid-<stamp>-sd1.img` | Zero 40 | main-zero40's boot chain with our root filesystem and MagicX's kernel modules (`scripts/make-hybrid-zero40.sh`). |

The older lanes, from a finished build:

```sh
scripts/make-hybrid-zero40.sh builds/<stamp>-zero40          # main-zero40 chain
scripts/build-awutils.sh                                     # XU20: the unpacker for its PhoenixSuit image
scripts/unpack-xu20-stock.sh                                 # XU20: image items and vendor modules
scripts/make-hybrid-xu20.sh builds/<stamp>-zero40            # XU20 on its stock chain, Android kernel
scripts/unpack-zero40-stock.sh                               # Zero 40: items and modules from MagicX's adb.img
scripts/make-hybrid-zero40-stock.sh builds/<stamp>-zero40    # Zero 40 on its stock chain, Android kernel
scripts/make-boot-resource.py inputs/xu20-stock/user.img.dump/RFSFAT16_BOOT-RESOURCE_FE \
    builds/bootres-xu20.fex xu20                             # bootloader screens sized for the panel
DIAG=0 EARLY_PROBE=0 CONSOLE=tty0 BOOTRES=builds/bootres-xu20.fex \
    scripts/make-own-kernel-stock.sh xu20 builds/<stamp>-xu20   # stock boot0/U-Boot + our kernel
```

(The Zero 40 takes the same `make-own-kernel-stock.sh` route from `inputs/zero40-stock/adb.img.dump`.
Without `DIAG=0` those images carry the diagnostic hand-off; the script's header lists its options.)

## Iterating

- `scripts/build.sh cont` resumes a build without wiping it.
- After changing a package Makefile, remove `sdk/lichee/out/a133-aw3/compile_dir/target/<pkg>*`.
- `scripts/build.sh image <board>` repacks without a full rebuild.
- Kernel options go in `config-4.9` through `sdk-patches/tree/020`. The build then appends the
  top config's `CONFIG_KERNEL_*` lines, and the later line wins: that is how the rootfs
  compressor choice once switched squashfs decompressors off (`134`, `docs/sdk-mods.md`,
  Round 17). Check what the kernel really got in `sdk/lichee/lichee/linux-4.9/.config`, or in
  the image's `System.map`; `build.sh image` reconfigures the kernel only when that merged
  configuration changes.

## Diagnostic and debug images

- `scripts/make-diag-image.sh` turns any image into a colour-staged diagnostic boot that
  leaves a full hardware snapshot on the card (`docs/hardware-notes.md`).
  `EXPERIMENTS="zero40-radio"` adds a bench experiment from `diag/experiments/`; a normal
  diagnostic image carries none.
- Debug kernels (`sdk-patches/debug/`) are built with `scripts/kdebug.sh build <board>`,
  which checks that the debug patch matches the tree first. Before a file's first debug edit
  run `scripts/kdebug.sh stash <file>`; after editing, `scripts/kdebug.sh regen` rebuilds the
  patch. `scripts/kmark-env.py`, `scripts/kmark-pm-decode.py` and `scripts/kmark-ring.py`
  read what such a kernel leaves behind; `docs/hardware-notes.md` ("Sleep on the SDK chain")
  shows them in use.
- `scripts/build.sh debug [board ...]` builds the public debug images (`*-debug-sd1.img`, all
  three boards by default):
  - a U-Boot (`sdk-patches/debug/uboot-debug.patch`, built by `build.sh uboot-debug` and
    swapped in for the pack only) that passes Linux the PMIC registers behind the boot-mode
    decision and the last mark of the boot before as `oakmoss.*` arguments, and turns the
    kernel marks on without changing `bootcmd`;
  - the KDEBUG_MARK and KDEBUG_FTRACE kernel, plus KDEBUG_HANG (`kdebug-hang.config`: lockup and
    hung-task detectors, a 5 s panic timeout);
  - `overlay-debug/`, which records every boot and every orderly shutdown in
    `/mnt/UDISK/oakmoss-debug` and copies the records to the SD card's `oakmoss-debug/`.

  RAM cannot carry a log across a reset here (boot0 overwrites DRAM), and the SD controller has
  no panic-safe writer, so the RTC mark and these records stand in for pstore.

The scripts never force a patch onto the SDK tree: when a patch and the tree disagree they
stop and change nothing.

## How the writers check their output

The scripts that write into an image (`replace-rootfs.sh`, the XU20 builder) check that
everything outside the partition they wrote still matches the source byte for byte. They
flush with a bounded, reported `sync` of the one file, because a wedged mount on the build
host once left two dozen `sync` processes blocked and a build hung with nothing to write.

## Repository layout

| path | what |
|---|---|
| `scripts/` | The build, in order: `fetch-inputs`, `prepare-toolchain`, `build-openixcard`, `unpack-sdk`, `apply-sdk-mods`, `build.sh` (`uboot`, `all`, `image`, `cont`, ...). Pictures: `make-boot-resource.py` (bootloader screens, boot logo), `make-charge-screens.py` (charge and low-battery screens). Board trees: `make-board-dts.py`. Debug: `kdebug.sh`, `kmark-env.py`, `kmark-pm-decode.py`, `kmark-ring.py`. Cards: `analyze-card-readback.py`, `verify-card.ps1`. Older lanes: `make-own-kernel-stock.sh`, `make-hybrid-stock.sh` and its wrappers, `make-hybrid-zero40.sh`, `adapt-zero40-rootfs.sh`, `unpack-*-stock.sh`, `build-awutils.sh`. Helpers: `run-in-sdk.sh`, `replace-rootfs.sh`, `fdt-enable-nodes.py`, `make-diag-image.sh`, and `lib.sh` (paths, pinned checksums). |
| `sdk-patches/` | Every change to the SDK tree: `tree/` (unified diffs), `package-patches/`, `ncurses-6.2/`, `gcc-7.5.0-patches/`, `toolchain/`, `sunxi_encrypt/` (`ENCRYPT_OBJ=stub`), and `debug/` (applied only for debug kernels). Each is recorded in `docs/sdk-mods.md`. |
| `boards/<board>/` | Per board: `board.conf` (device marker, kernel object), `board.dts`, `sys_config.fex` (charge mode), `sys_partition.fex`, `boot-resource/` (U-Boot's charge and low-battery pictures, and the Zero 40's and XU20's boot logo) and `overlay/` (the charge screen frames), layered over the shared `overlay/`. |
| `overlay/` | Root filesystem additions: `etc/rc.local` (audio defaults, the hand-off), `etc/init.d/chargeframe` (the first charge frame), `usr/magicx/bin/runmagicx.sh` and `charge-screen.sh`, the TrimUI SDL2 libraries under `usr/magicx/lib/`, and small fixes (`wpa_supplicant` no-op, empty `modules.d/net-xr829`). A `bootlogo.bmp` here (gitignored) replaces the SDK's logo. |
| `configs/` | Tina configs: `ext-armgnu13.config` (the build), Moss's `phase1`/`phase2` and the from-source fallback `phase2-gcc750`. |
| `tools-patches/` | Patches to tools built from source (awutils, for the XU20 image header). |
| `docker/` | The Ubuntu 18.04 build container. |
| `diag/` | The diagnostic hand-off, `fbfill.c`, the input-bitmap decoder, and opt-in `experiments/`. |
| `assets/` | spruceOS's tree mark, for the boot logo. |
| `docs/` | This guide, `using.md`, `status.md`, `sdk-mods.md` (ledger of SDK changes), `hardware-notes.md`, `toolchain.md`, `DEPENDENCIES.md`. |
| `LICENSES/` | License texts for third-party code carried here. |
| `inputs/`, `sdk/`, `toolchains/`, `tools/`, `builds/` | Working trees, not tracked. |
