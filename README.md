# oakMOSS

Base-OS ("SD1") image for the **MagicX Mini Zero 28**, **MagicX Zero 40** and
**XU RETRO / MagicX XU20 V32** (Allwinner A133P). A pared-down Tina Linux whose only job is to boot, mount the
user card in the second slot at `/mnt/SDCARD` and hand off to the launcher on
it: spruceOS's `.tmp_update/updater`, or `magicx/init.sh` if a card carries one.
It follows the shape of Shaun Inman's [Moss-zero28](https://github.com/shauninman/Moss-zero28)
and [main-zero40](https://github.com/dedicated-os/main-zero40); see
[ATTRIBUTION.md](ATTRIBUTION.md).

What comes out, per board, as raw GPT images (686 MB, mostly empty) that are
written to the internal microSD with `dd` or Etcher:

| image | board | what it is |
|---|---|---|
| `oakmoss-zero28-<stamp>-sd1.img` | Zero 28 | our full chain: boot0, U-Boot, DTB, kernel, rootfs |
| `oakmoss-zero40-<stamp>-sd1.img` | Zero 40 | same chain with the Zero 40 kernel object; **white screen on the real board** (the SDK drop lacks its panel and touch drivers) |
| `oakmoss-zero40-hybrid-<stamp>-sd1.img` | Zero 40 | **the one to flash**: main-zero40's boot chain (panel, touch, kernel) with our rootfs in its rootfs partition, carrying MagicX's own kernel modules (`scripts/adapt-zero40-rootfs.sh`) |
| `oakmoss-<board>-own-<stamp>-sd1.img` | XU20 V32, Zero 40 | **the newest lane**: the board's stock boot0 and U-Boot with OUR kernel, device tree and rootfs (`scripts/make-own-kernel-stock.sh`); the panels come from `sdk-patches/tree/070-*`, the trees from `boards/<board>/board.dts` |
| `oakmoss-zero40-stock-<stamp>-sd1.img` | Zero 40 | **new lane (2026-09-16)**: the Zero 40's own stock firmware chain (MagicX release Zero40_V1 `adb.img`: boot0, U-Boot, DTB, Android kernel 4.9.170) with the Zero 40 rootfs as ext4 and the vendor's modules, the same recipe as the XU20 image; built because no round-8 rootfs ever came up on the main-zero40 chain |
| `oakmoss-xu20-hybrid-<stamp>-sd1.img` | XU20 V32 | the stock firmware's own boot chain and Android kernel (its panel and touch driver are in neither our SDK nor main-zero40) with the Zero 40 rootfs as ext4; both extra SD controllers enabled so the second card is visible. **Not yet booted on a unit.** |

Rootfs: glibc 2.38 / libstdc++ 13 userland (Arm GNU Toolchain 13.3) on the
vendor 4.9.191 kernel, ncurses 6, libmad, bluez, busybox with unzip/losetup/stat,
loop + uinput + joydev in the kernel, XR829 and Realtek 8189es radio support,
PowerVR GE8300 blobs, and the TrimUI SDL2 blobs under `/usr/magicx/lib` that the
launcher expects. Why the userland is newer than Moss's: see [docs/toolchain.md](docs/toolchain.md).

## Inputs you have to bring

Some of what the build needs is proprietary and is **never** in this repository.
`scripts/fetch-inputs.sh` downloads and checksum-verifies everything that is
publicly available, then tells you what is still missing and where it goes. The
XU20's and the Zero 40's stock firmwares are public GitHub releases and are
fetched automatically.

## Build

Host: Linux with Docker (the SDK needs an Ubuntu 18.04 userland; the container
is built for you) and these packages:
`git curl unzip xz-utils squashfs-tools util-linux cmake build-essential libconfuse-dev pkg-config automake autoconf`.

Disk: budget about 45 GB for the inputs plus one board's build. The unpacked SDK
alone is ~18 GB clean and ~30 GB once built, `inputs/` holds ~13 GB of SDK and
stock-firmware archives, and every extra image lane (hybrid, stock, own, XU20)
adds its own `builds/<stamp>-<board>` tree on top.

```sh
scripts/fetch-inputs.sh            # public inputs; checks the private ones
scripts/prepare-toolchain.sh       # Arm GNU 13.3 + the Tina sysroot/wrapper shims
scripts/build-openixcard.sh        # OpenixCard from source (Allwinner image -> raw image)
scripts/unpack-sdk.sh --remove-zip # streams the SDK out of the zip, verifies its md5
scripts/apply-sdk-mods.sh          # every SDK change (docs/sdk-mods.md), idempotent
scripts/build.sh all               # userland build (~20-40 min on 8 cores) + both images
scripts/make-hybrid-zero40.sh builds/<stamp>-zero40     # the image a Zero 40 boots
scripts/build-awutils.sh           # XU20 only: the unpacker for its PhoenixSuit image (patched for its header)
scripts/unpack-xu20-stock.sh       # XU20 only: image items + vendor modules out of the stock firmware
scripts/make-hybrid-xu20.sh builds/<stamp>-zero40       # the XU20 image (from the Zero 40 rootfs)
scripts/unpack-zero40-stock.sh     # Zero 40 stock lane: items + vendor modules out of MagicX's adb.img
scripts/make-hybrid-zero40-stock.sh builds/<stamp>-zero40   # the Zero 40 image on its own stock chain (Android kernel; no GL)
scripts/build.sh image xu20                                  # our kernel + rootfs for the XU20 (boards/xu20/board.dts, panel in 070-*)
scripts/make-own-kernel-stock.sh xu20 builds/<stamp>-xu20    # stock boot0/U-Boot + our kernel, tree and rootfs (same for zero40)
#   (both wrappers run scripts/make-hybrid-stock.sh <board>: one recipe, two boards)
```

Outputs land in `builds/<stamp>-<board>/` with a `BUILD-INFO.txt` (SDK md5,
toolchain, kernel object, overlay hash, libc). `COMPRESS=1` also writes `.img.xz`.
Everything is overridable through the environment (`OAKMOSS_WORK` moves the big
trees to another disk; see `scripts/lib.sh`).

Iterating: `scripts/build.sh cont` resumes without wiping; after changing a
package Makefile remove `sdk/lichee/out/a133-aw3/compile_dir/target/<pkg>*`;
`scripts/build.sh image <board>` re-packs without a full rebuild.
`scripts/make-diag-image.sh` turns any image into a colour-staged diagnostic
boot with a full hardware snapshot on the card (docs/hardware-notes.md).
`EXPERIMENTS="zero40-radio"` adds a bench experiment from `diag/experiments/` to
that image; a normal diagnostic image carries none.

The writers (`replace-rootfs.sh` and the XU20 builder) verify their output the
hard way: everything outside the partition they wrote must match the source
image byte for byte, and the flush is bounded and reported rather than a bare
`sync` (one wedged mount on the build host once left two dozen `sync`
processes blocked behind it, and a build hung with nothing left to write).

## Using the image

> **This replaces the firmware your device boots from.** Writing the wrong image
> to the wrong board, or interrupting the write, leaves a device that will not
> start. Image the stock SD1 card first and keep that backup: for these boards it
> is the only way back. Write the image **raw** (`dd`, Rufus in DD mode, Etcher,
> Win32DiskImager, Raspberry Pi Imager) to the whole card, then eject. Do **not**
> open a written card in a partition tool - a table "repair" zeroes boot0 and the
> card stops booting.

1. Write the image to the **internal** microSD (SD1, the whole card). The system
   card goes back in the slot the board's own system card came from.
2. Put a launcher card in the second slot: a FAT32 card carrying
   [spruceOS](https://github.com/spruceUI/spruceOS) with MagicX support (its
   `.tmp_update/updater` reads `/usr/magicx/device` to tell `zero28` from
   `zero40`), or any card with `magicx/init.sh`. exFAT is not supported: kernel
   4.9 here has no exFAT driver, so the user card must be FAT32.
3. Boot. With no card, or if the launcher exits, the device powers off
   (`overlay/usr/magicx/bin/runmagicx.sh`).

## Layout

| path | what |
|---|---|
| `scripts/` | the build, in order: `fetch-inputs`, `prepare-toolchain`, `build-openixcard`, `unpack-sdk`, `apply-sdk-mods`, `build`, `make-hybrid-zero40` (which runs `adapt-zero40-rootfs`), `make-diag-image`; the stock-chain lane: `unpack-xu20-stock` / `unpack-zero40-stock`, then `make-hybrid-stock <board>` (wrappers `make-hybrid-xu20`, `make-hybrid-zero40-stock`); for the XU20 `build-awutils`, `unpack-xu20-stock`, `make-hybrid-xu20`; `run-in-sdk.sh` runs a command in the container; `replace-rootfs.sh` writes a squashfs into an image's rootfs partition and proves the rest untouched; `fdt-enable-nodes.py` enables device-tree nodes in place; `lib.sh` holds paths, pinned checksums and `flush_file` |
| `tools-patches/` | patches to tools built from source: awutils' image-format check for the XU20 firmware's header |
| `configs/` | Tina configs: `ext-armgnu13.config` (the build), `phase1.config` / `phase2.config` (Moss-zero28's originals, plus libmad) and `phase2-gcc750.config` (the from-source fallback toolchain) |
| `sdk-patches/` | every change to the SDK tree: `tree/` (unified diffs applied with `patch -p1`), `package-patches/` (dropped into `package/<pkg>/patches/`), `ncurses-6.2/` (OpenWrt 21.02 package port), `gcc-7.5.0-patches/` (OpenWrt 19.07 set), `toolchain/` (compiler wrapper) |
| `overlay/` | rootfs additions: `etc/rc.local` (audio defaults + the hand-off), `etc/banner`, `etc/modules.d/net-xr829` (empty: no xradio autoload), `etc/init.d/wpa_supplicant` (no-op: the launcher owns the radio, the SDK's service ran a second supplicant on wlan0), `usr/magicx/bin/runmagicx.sh`, `usr/magicx/lib/` (TrimUI SDL2 blobs). Drop a `bootlogo.bmp` here to replace the SDK's |
| `TODO.md` | wishlist for the kernel (config, per-board drivers and DTB) and the rootfs overlay, with what is done and what still needs identifying |
| `boards/<board>/board.conf` | device marker and kernel-object source per board; `boards/<board>/overlay/` (optional) is layered on top of `overlay/` |
| `docker/` | the Ubuntu 18.04 build container |
| `diag/` | diagnostic hand-off, `fbfill.c`, the input-bitmap decoder, and `experiments/`: opt-in bench scripts (`zero40-radio`) the hand-off runs only when an image was built with them |
| `docs/` | `sdk-mods.md` (ledger of SDK changes, with reasons), `toolchain.md`, `hardware-notes.md` (what the boards turned out to be), `DEPENDENCIES.md` (what spruce and PortMaster need from the base) |
| `inputs/`, `sdk/`, `toolchains/`, `tools/`, `builds/` | untracked working trees (`.gitignore`) |

## Status

Bench-tested on a Zero 28 and a Zero 40 with spruceOS on the user card
(September 2026): launcher, pad, touch (Zero 40), audio, WiFi and the hand-off
all exercised; not a release. Known gaps: the Zero 40's own panel and touch
drivers are absent from the SDK drop (hence the hybrid), the newer-board-revision
fixes in main-zero40 v20260202-1 are not in our inputs, kernel 4.9 has no exFAT
(large SD2 cards need FAT32), busybox 1.27 has no `bc`, and the XR829 crystal
variant is assumed 26 MHz. The tested boards' radio is a Realtek 8189es, driven
by the in-kernel driver.

The **XU20 V32 has never booted** with any image in this repository: two attempts
failed and the cause is unresolved (TODO.md). Its images are built and checksummed
but untested, and a USB-TTL UART adapter on PB9 (TX) / PB10 (RX) at 115200 8N1 is
the only diagnostic that has told us anything on these boards. Treat every image
here marked untested as exactly that.

The spruceOS side (platform files, PyUI device classes, the card builder) lives in
spruceOS, not here.

oakMOSS is an independent community project. It is not affiliated with, endorsed
by, or supported by MagicX, XU RETRO, TrimUI, Allwinner or Imagination
Technologies, and it is not Moss or Dedicated OS. Device, product and company
names are used only to say which hardware and which sources are involved.
Flashing a device is at your own risk; see [LICENSE](LICENSE).

License: [LICENSE](LICENSE) for oakMOSS's own files; third-party terms in [ATTRIBUTION.md](ATTRIBUTION.md).
