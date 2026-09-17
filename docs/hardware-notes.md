# Hardware notes: what the boards turned out to be

Measured on one Zero 28 and one Zero 40 with spruceOS on the user card (September
2026), mostly through the diagnostic image's boot snapshot
(`scripts/make-diag-image.sh`, `diag/decode-input-bitmap.py`). Facts about the
launcher side (spruceOS platform files, PyUI classes, RetroArch bindings) live in
spruceOS; this page keeps what the base image and anyone porting another launcher
need.

## Boards

| | Zero 28 | Zero 40 |
|---|---|---|
| SoC / board | Allwinner A133P, Tina board `a133-aw3`, DTB says `allwinner,a100` | same |
| Panel | `h028b23`, 480x640 portrait-native, the launcher draws it rotated (640x480) | `RTP40WV101B`, 480x800 portrait-native, drawn unrotated; `axs15205` touch on twi |
| Panel/touch drivers in the SDK drop | yes | **no**: our DTB/U-Boot/kernel drive the Zero 28 panel (white screen); hence the hybrid image on main-zero40's chain |
| PMIC / gauge | AXP2202; `axp2202-battery` reads fine (94 % at 4.18 V) | AXP2202; reads low on the same code with a low cell; neither DTB carries battery parameters (`pmu_battery_cap`, OCV table), so both boards run the driver's default 2600 mAh model and the Zero 40's larger cell reads skewed until a learned cycle |
| Pad | UART MCU pad (`simplepad` driver on `/dev/ttyS3`), registers as **`magicx-input`**; was `event2` (also `js0`); no `event3` | same driver and name; was `event3`; touch `axs_ts` = `event0` |
| Other input nodes | `axp2202-pek` (power key) = event0, `audiocodec sunxi Audio Jack` = event1 | power key and jack likewise, shifted by the touch node |
| Radio | **Realtek RTL8189ES-class SDIO**, id `024c:8179`, driven by the in-kernel `rtl8189es` (`wlan0` up at ~11 s; confirmed live over SSH) | **XR829**, SDIO id `0a9e:2282` (the kernel's xr829 driver table; 2026-09-16 diag log). The card enumerates under the known-good DTB; it only needs `xradio_wlan` loaded by name (no autoload on either board) |
| Storage | SD1 internal (`mmcblk0`), user card `mmcblk1p1`, mounted at `/mnt/SDCARD` by the SDK's block hotplug | same |

## Pad key codes (`magicx-input`, from the sysfs key bitmaps)

Not TrimUI's layout. A/B/X/Y = 304/305/307/308 (`BTN_SOUTH/EAST/NORTH/WEST`),
L1/R1 = 310/311, L2/R2 are **buttons** 312/313, L3/R3 = 317/318 (the Zero 40 has
no R3), the d-pad is KEY_UP/LEFT/RIGHT/DOWN = 103/105/106/108, SELECT/START =
314/315, volume keys 114/115 (gpio children of the pad node), and **MENU = 353**
on both boards (MinUI's zero28 platform expected KEY_BACK 158; 158 is declared
in the bitmap but the button sends 353). Left stick: Zero 28 as expected; Zero 40
reports AXIS_Y as 0 and AXIS_X as 1 negated (Dedicated OS's table agrees), so a
launcher must swap and invert there.

Emulators take the pad through SDL_GameController; SDL's automatic mapping drops
the arrow-key d-pad and the 353 MENU, so a launcher has to export
`SDL_GAMECONTROLLERCONFIG` for GUID `1900000012b400006666000000010000` (bus
0x0019, vendor 0xb412, product 0x6666, version 0x0100).

## Audio, display, misc

- Volume: `amixer -D hw:audiocodec cset name='DAC volume' N` (0, or 96..160 for
  5..100 %) after opening `Headphone`, `digital volume`, `Soft Volume Master`
  (MinUI's zero28 libmsettings does the same). `overlay/etc/rc.local` sets the
  SDK's mixer defaults at boot.
- `fb0` is 480x800 on both DTBs with no display-engine rotation. A screenshot of
  the framebuffer is portrait; rotate it for the Zero 28.
- No `/sys/class/led_anim` (TrimUI RGB), no `/usr/trimui` daemons.
- `/usr/magicx/lib` must be first on `LD_LIBRARY_PATH` for the SDL2 blobs; the
  `libSDL2_mixer` blob needs `libmad.so.0`, `libSDL2_image` needs libpng12 and
  libjpeg9, all of which the image builds.

## Boot and hand-off

`/etc/rc.local` runs `/usr/magicx/bin/runmagicx.sh` at the end of boot. It waits
up to 10 s for `/mnt/SDCARD`, runs `magicx/init.sh` if the card has one, else
`.tmp_update/updater`, else powers off; it also powers off if the hand-off
returns. Under our own chain the Zero 40 once looked like it "never saw the
card": it was the launcher's low-battery shutdown (cell at 1 %), not the base.

`/usr/magicx/device` holds `zero28` or `zero40` (`boards/<board>/board.conf`).
Any `/usr/magicx` directory identifies a MagicX Tina base; the marker is what
tells the two boards apart, since `/proc/cpuinfo` says `0xd03` (Cortex-A53) on
both, the same as the Anbernic H700 boards.

main-zero40's own image looks for `main.sh` at the root of the user card instead;
a card can carry both `main.sh` and `.tmp_update/updater` to boot under either base.

## Diagnostic image

`scripts/make-diag-image.sh <sd1.img> <rootfs.fex> <out.img> [src:dest ...]`
swaps the hand-off for `diag/runmagicx-diag.sh`: green screen = rc.local reached,
blue = card mounted, red = no card after 30 s (then poweroff), yellow = the
hand-off returned (then poweroff after 10 s). It writes
`/mnt/UDISK/spruce-base-boot.log` on SD1 (persists across boots) and, once the
card is up, `Saves/spruce/base-boot.log` and `base-handoff.log` on the card:
mounts, partitions, every `power_supply` uevent, `/proc/bus/input/devices`, each
input node's key/abs bitmaps, SDIO ids, loaded modules, interfaces, rfkill and
the full dmesg. `diag/decode-input-bitmap.py <base-boot.log>` prints each node's
key codes and the SDL-order button labels.

## XU20 V32 (XU RETRO / MagicX), 2026-09-16

The third board in the family and the first that runs our rootfs under the
**device's own Android boot chain and kernel** (4.9.170, TrimUI lineage, MODVERSIONS,
IKCONFIG). Everything below is read out of the stock firmware; no unit has run this
code yet.

- **Panel** RTP32HD016A 1024x768, landscape-native DSI, built into the kernel;
  **touch** Hynitron `hyn_ts` on TWI1 at 0x5a, five points, 1024x768, no axis swap
  (kernel names it `hyn_ts`, `cst1xx_ts` or `cst8xx_ts`); **pad** the same `simplepad`
  driver as the Zero boards (`magicx-input`, ids 0x19/0xb412/0x6666/0x0100) with **no
  analog sticks** (`joysticks = <0x0>`); AXP2202 battery (`axp2202-battery`), 2800 mAh
  in the tree; vibrator through `sunxi-vibrator` off a regulator, not a GPIO.
- **Second key codes.** The tree gives three buttons a `linux,code2` the driver emits
  alongside the first (proven on the Zero 28): A 304+353, B 305+158, MENU 158+256.
  So 158 cannot mean MENU here - it arrives with every B press. MENU is 256, and 158
  is ignored. A `switch-key` node with code 0 also takes an SDL button slot and shifts
  the d-pad and the hotkey up by one.
- **Storage.** No internal flash: the system ships on a card. Four SD controllers;
  the stock tree enables only sdc0 (TF slot, card detect PF6) and sdc1 (SDIO, the
  radio). sdc2 (eMMC-shaped pinout, `non-removable`, SD UHS caps, a regulator) and
  sdc3 (SD only, PI9-PI14) are `disabled`; U-Boot enables only the one it booted from
  and the three dtbo overlays are empty stubs. The image enables sdc2 and sdc3 itself
  (`scripts/fdt-enable-nodes.py`, in place) after checking that every function sharing
  those pins is disabled and nothing claims them as GPIOs. Which physical slot is which
  is still unknown; a booted unit's `/proc/partitions` settles it.
- **Boot chain facts.** boot0 for a card is the image item `12345678_1234567890BOOT_0`
  (`boot0_sdcard.fex`; `BOOT    _BOOT0_0000000000` is the NAND one). Verified boot is
  not enforced (the gate sits in a secure-mode branch and TOC0/TOC1 are placeholders).
  `CONFIG_VT` and `CONFIG_LOGO` are off, so no kernel text ever reaches the panel;
  U-Boot's logo is the only visual before our own code. U-Boot's built-in fallback
  environment cannot boot our layout, so "logo, then frozen" means the environment
  was not read. `init=` failing to exec is a panic with no fallback. Root is given as
  `PARTUUID` because the mmc block index follows probe order. **UART0 = PB9 (TX) /
  PB10 (RX), 115200 8N1**: the diagnostic that settles anything.
- **Radio** not identified by the image (it ships 8189es, xr829, aic8800 and uwe5622
  drivers and no radio firmware, which points at the Realtek); read the SDIO id.
- **Gaps** the stock kernel imposes: no squashfs (hence ext4 root), no UTF-8 NLS, no
  exFAT.

## Zero 40 hybrid: whose modules

The hybrid runs MagicX's kernel (main-zero40, 4.9.191) with our root filesystem.
The kernel modules in that filesystem must be MagicX's own, not ours
(`scripts/adapt-zero40-rootfs.sh`, run by `make-hybrid-zero40.sh`). Found the
hard way on 2026-09-16: a pre-round-8 rootfs of ours booted under that kernel,
three round-8 ones did not, with a boot chain the packer proves byte-identical
to the booting card. The kernel configuration MagicX ships (extracted from its
kernel with `extract-ikconfig`) has `CONFIG_BUG=n` and `CONFIG_KALLSYMS=n`
where ours has both on, so every `WARN_ON` in a module of ours is a `brk` trap
their kernel reports as a fatal BUG (`report_bug()` without `GENERIC_BUG`), and
round 8 turned our netfilter core into modules (`ip_tables`, `x_tables`) that
the base's `nf-ipt` autoload pushed into their kernel at every boot. The
vermagic is identical and MODVERSIONS is off on both sides, so nothing at load
time objects. MagicX's rootfs ships exactly the modules its kernel needs
(`pvrsrvkm`, `dc_sunxi`, `simplepad`, `fuse`, the iptables set) built from the
same PowerVR DDK as our userland (`1.19@6345021`); the adapter takes them out of
the main-zero40 image's rootfs partition, checks vermagic and DDK, and leaves
our `8189es`/`xradio_*` on disk for the diagnostic radio experiment, which
loads them itself. Under that kernel there is no `ZRAM`, `BLK_DEV_LOOP`,
`POSIX_MQUEUE` or `NTFS`; `GPIO_SYSFS` is on (ours is not).

## Zero 40 stock firmware (MagicX release Zero40_V1), 2026-09-16

MagicX's public developer image for the Zero 40 (`adb.img.xz`, an 8 GB raw card
image of the board's native Android with adb) turns out to be the same
Allwinner Android BSP as the XU20's developer release: kernel 4.9.170 with
MODVERSIONS (`#18 SMP PREEMPT Mon Jun 16 2025`, Linaro GCC 5.3), PowerVR DDK
`1.11@5516664`, the identical set of 48 vendor modules, and a device tree
that differs from the XU20's in 174 lines. So the XU20 recipe (stock boot
chain + stock kernel + our rootfs as ext4 + vendor modules + TrimUI's DDK 1.11
userland) serves both boards: `scripts/make-hybrid-stock.sh <board>`.

What the tree says about the Zero 40, beyond the panel (`RTP40WV101B`, 480x800,
dclk 36 MHz) and the `axs15205` touch at twi address 0x3b it shares with
main-zero40's tree:

- **Radio is XR829**, per the vendor init (`persist.vendor.wlan_vendor=xradio`,
  Bluetooth on `/dev/ttyS1`), and the vendor partition carries its firmware
  (`fw_xr829.bin`, `sdd_xr829.bin`, `boot_xr829.bin`, `etf_xr829.bin`,
  `fw_xr829_bt.bin`, `bt_sdd.bin`). The stock card autoloads `xr829` and ships
  those files at `/lib/firmware` and `/vendor/etc/firmware` (the boot image's
  header command line names the latter through `firmware_class.path=`).
- **Sticks are read over UART3** (`uart_path = "/dev/ttyS3"`, `joysticks = <1>`,
  `joystick1_invert_x`, `joystick1_swap`, ADC baselines 0x834, range 0x20d): a
  pad MCU, not the SoC's ADC. `uart@05000c00` is `okay` for that reason.
- **Slot rule, confirmed on hardware 2026-09-16 (XU20):** the system card MUST sit in the sdc2 slot and the user card in the sdc0 slot. The boot ROM tries card0 (sdc0) before card2, so a system card in the sdc0 slot boots too, but then U-Boot enables only sdc0 and the user card in the sdc2 slot stays invisible: colours to red, power-off. Swapping the two cards took the same image to blue.
- **Slots**, corrected 2026-09-16 13:15: the SYSTEM card sits on sdc2 (the
  eMMC-class controller, `non-removable`, described by `card2_boot_para`),
  which U-Boot enables at run time because it booted from it; the USER card
  sits on sdc0, `okay` with card detect on PF6 in the stock tree. sdc1 is the
  SDIO radio; sdc3 (PI9-14) is unused. Both cards are visible in a stock tree
  (the Zero 28 boots our images with sdc2 and sdc3 disabled in its file and
  mounts the user card). Enabling sdc2 and sdc3 statically (`SECOND_SLOT=1`)
  was never needed and left the XU20 behind its boot logo; it is off by default.
- GPT: entries at LBA 2, first partition (`bootloader`) at sector 73728; boot0
  at sector 16, boot package (`u-boot`, `monitor`, `scp`, `dtb` items) at
  sector 32800; the dtb inside the package and the one in `boot.img` (header
  v2) are byte-identical, 150775 bytes. boot0 and the package are NOT the
  main-zero40 ones (dedicated-os rebuilt U-Boot for its Tina chain).
- **GPU firmware**: the Android `pvrsrvkm` 1.11 loads `rgx.fw.22.102.54.38` from
  `/vendor/firmware`; that file is identical on the XU20 and the Zero 40 and
  differs from both TrimUI's 1.11 build and the 1.19 one our SDK ships under
  the same name (the name is the core's BVNC). Every stock-chain image before
  2026-09-16 12:30 carried the 1.19 file; the recipe now installs the vendor's.
- Battery model in the tree: `pmu_battery_cap` 0xaf0 (2800 mAh), `rdc` 0xaa;
  the XU20's says 0xa28 / 0xcb.

Why this lane exists: every round-8 rootfs of ours failed to come up on the
main-zero40 chain, including one carrying MagicX's own 4.9.191 modules
(`builds/20260916-1148-zero40-hybrid`), while the pre-round-8 2042 image
boots and the packer reproduces that image byte for byte. The stock chain
removes the dedicated-os boot chain from the question entirely.

**Solved the same afternoon: boot0 checksums the boot package.** The first
stock-chain Zero 40 image (1228, second slot enabled) showed no LED at all;
the same build with `SECOND_SLOT=0` (1240, boot package and boot image byte-
identical to stock) booted, and so did the bisect image on the main-zero40
chain. The second-slot patch (`fdt-enable-nodes.py`) changes bytes inside the
`sunxi-package` at sector 32800, and boot0 sums every word of that package
against the `add_sum` in its header (stamp `0x5F0A6C39`, `private_toc.h`)
before it runs U-Boot. A mismatch stops the device in boot0: no U-Boot, no
logo, no LED. Every two-slot image before 2026-09-16 12:50 shipped such a
package, the XU20's since 0724 included. `scripts/toc1-checksum.py --fix`
now follows the patch and `--check` gates the finished image. (The boot
image's copy of the tree needs no such repair: U-Boot checks only its magic.)
With the checksum right, the two-slot image reached the logo and stopped; the
slot model above is the correction, and the stock U-Boot's habit of recomputing
`mmc_root` as `/dev/mmcblk0p<n>` (`"set root to %s"` in its binary) is why the
recipe now writes `root=PARTUUID=` literally into `setargs_mmc`.
The "no LED" reports on the main-zero40 chain that same day (2042, 1148)
had untouched packages and were not reproducible; three cards rotate between
three units there.

## Stock-chain bring-up log, 2026-09-16 afternoon

- 1255/1228 (two-slot patch): no LED, boot0 refused the package (checksum, fixed).
- 1240 Zero 40, one-slot: boots. 1155 bisect (main-zero40 + 2042 root): boots.
- 1308 both boards (stock tree, package valid, `root=PARTUUID` literal): stop
  behind the boot logo with two cards; the Zero 40 boots with the user card
  out. The sdc0 node is identical between the Tina tree (two cards work) and
  the Android tree, so the tree is not it. Root goes back through
  `${mmc_root}`, the form 1240 used.
- The host's mke2fs wrote 1.47-era ext4 features (`metadata_csum`, `64bit`,
  `orphan_file`, `metadata_csum_seed`) and files owned by uid 1000; the recipe
  now writes the vendor's own feature set (`uninit_bg`, none of those) and
  root-owned files.
- `EARLY_PROBE=1` (default with `DIAG=1`): `init=/sbin/init-probe` paints
  magenta the moment the kernel executes it, writes `oakmoss-early-probe.log`
  (cmdline, block devices, mmc hosts, mounts, dmesg) to the user card's FAT
  root and to UDISK, paints teal, then execs `/sbin/init`. Colour ladder:
  magenta, teal, green (rc.local), blue (user card mounted), yellow/red.

## Our kernel on the stock chain (route 1, 2026-09-16 evening)

The Android-kernel lane cannot give a Linux GL stack (above), so both boards now
get OUR 4.9.191 kernel behind the stock boot0 and U-Boot:

- **Panel drivers** `rtp32hd016a` (XU20, 1024x768) and `rtp40wv101b` (Zero 40,
  480x800), two-lane DSI, in `sdk-patches/tree/070-*`. Recovered from the
  XU20 stock kernel binary (it carries both): `vmlinux-to-elf` for symbols,
  the panel structs' function tables read through the kernel's own relocation
  records, then `lcd_open_flow` / `lcd_power_on` / `lcd_panel_init` /
  `lcd_panel_exit` / `lcd_power_off` decoded call for call. The XU20 init is
  a 31-row DCS table (56-byte rows, count at +4, 0xfd end, 0xfe delay) whose
  two delay rows are malformed in the stock driver (the delay sits in the
  count field), so the panel actually receives DCS 0xfe with 120 / 20 bytes;
  reproduced exactly. The Zero 40 needs only sleep-out and display-on, with
  a second reset line (PB7) pulsed after the first.
- **Board trees** `boards/xu20/board.dts`, `boards/zero40/board.dts`,
  generated by `scripts/make-board-dts.py` from the Zero 28 tree plus each
  stock tree: lcd0 block, simplepad map, wlan node, battery model. Touch
  nodes are not carried yet (drivers not ported: Hynitron 0x5a on the XU20,
  axs15205 0x3b on the Zero 40).
- **Card** `scripts/make-own-kernel-stock.sh`: stock boot0 (at 16 and 256),
  stock package with its dtb item replaced by ours (`toc1-item.py`, checksum
  redone), our kernel in a header-v2 boot image that also carries our tree
  and no header command line, env with root=PARTUUID through mmc_root and
  rootfstype=squashfs, our rootfs squashfs in p6, rootfs_data/UDISK ext4.
  Whichever tree U-Boot hands the kernel, it is ours; U-Boot itself now reads
  our tree for its own panel init, which carries the stock timings.
- The XU20 kernel object is the SDK's (no XU20 Linux object exists); it is an
  identity misc device, not a boot gate.

## Cards on a PC: what zeroes boot0

Three "no LED" cards in one evening, each with sector 16 zeroed and the boot
package at 32800 intact, one of them freshly written by Raspberry Pi Imager.
Sector 16 lies inside the standard GPT entry area (sectors 2..33). Our images,
like MagicX's, keep the entry array at sector 2048 so boot0 survives, but any
PC tool that "repairs", saves or rebuilds the table lays the entries back at
sector 2 and boot0 becomes zeros; inspecting a card in DiskGenius can be that
moment. Rules: write the image raw (Rufus DD, Etcher, Win32DiskImager, Pi
Imager all do), eject, boot; answer No to every fix/format prompt; a card
inspected in a partition tool is a card to rewrite. Since 2026-09-16 the
stock-chain images also carry boot0 at sector 256 (128 KiB), the second
place the sun50i boot ROM looks, which no table rewrite reaches.

## Known gaps

- Zero 40 panel and touch drivers, and the "newer board revision" fixes in
  main-zero40 v20260202-1, are not in the SDK drop.
- No exFAT in kernel 4.9 and no FUSE exfat package in the Tina tree: user cards
  over 32 GB must be FAT32.
- busybox 1.27.2 has no `bc`.
- XR829 26 MHz vs 40 MHz crystal unverified (26 assumed, as Knulli ships); moot
  on boards with the Realtek radio.
- No `harbourmaster` (PortMaster) device profile for either board yet.
