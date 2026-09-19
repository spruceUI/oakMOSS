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
| Panel/touch drivers in the SDK drop | yes | **no**: our DTB/U-Boot/kernel drive the Zero 28 panel (white screen); hence the hybrid image on main-zero40's chain. Since 2026-09-17 both are in our kernel: panels in `070-*`, touch controllers in `080-*` (see "Own kernel on the stock chain") |
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

## Kernel console on the panel (2026-09-17)

The colour ladder above only reports what userland reaches. Anything that fails
before `/sbin/init` - a panic, a failed `init=`, a driver that hangs an initcall -
leaves U-Boot's logo on the screen and says nothing, because the stock kernel
config has `# CONFIG_FRAMEBUFFER_CONSOLE is not set`: `console=tty0` binds the
dummy console, and these boards expose no serial header on the lab units. The
XU20's reboot loop and the two diagnostic cards that never painted a colour all
present identically under that blind spot, which is why neither could be read.

`scripts/build.sh` with `KDEBUG_FBCON=1` builds a kernel whose console is the
display. It rewrites five symbols in
`device/config/chips/a133/configs/aw3/linux/config-4.9` (the board kernel config,
which is `$(LINUX_KCONFIG_LIST)` in `build/kernel-build.mk`, so editing it
invalidates the kernel's configure stamp and the kernel reconfigures itself -
`arch/arm64/configs/sun50iw10p1smp_defconfig` is *not* the source of truth and is
only consulted when the kernel tree has no `.config` at all):

    CONFIG_FRAMEBUFFER_CONSOLE=y
    CONFIG_FRAMEBUFFER_CONSOLE_DETECT_PRIMARY=y
    CONFIG_FRAMEBUFFER_CONSOLE_ROTATION=y
    # CONFIG_FONTS is not set
    CONFIG_FONT_8x16=y

All five are required. The kernel is configured through `silentoldconfig` with
stdin redirected, so a single unanswered NEW prompt aborts the build; fbcon pulls
in `ROTATION`, and it selects `FONT_SUPPORT`, which opens the "select compiled-in
fonts" prompt that the stock config answers nowhere because it ships no console
font. `ROTATION` is not decoration: the XU20's panel is mounted upside down, so
without `fbcon=rotate:2` the log prints inverted.

Pair it with the card builder:

    KDEBUG_FBCON=1 scripts/build.sh image xu20
    DIAG=0 EARLY_PROBE=0 CONSOLE="tty0" EXTRA_BOOTARGS="fbcon=rotate:2" \
        scripts/make-own-kernel-stock.sh xu20 builds/<stamp>-xu20 builds/kdebug-xu20

`CONSOLE` replaces the stock console list (`ttyS0,115200`); `EXTRA_BOOTARGS` is
appended to the bootargs verbatim, for arguments with no env variable of their own.
A build without `KDEBUG_FBCON` puts the config back, so the next shipped image is
unaffected - debug cards only, since fbcon replaces the boot logo with scrolling
kernel text.

## Touch drivers stalled the boot (2026-09-18)

The cause of the XU20's intermittent stuck-at-logo boots, and very likely of the Zero
40's "picky" ones. Both touch drivers were built in, so their `late_initcall` probes
ran on the kernel's init thread. A marker kernel (`sdk-patches/debug/kdebug-mark.patch`,
`build.sh` `KDEBUG_MARK=1`) writes each initcall's address, then driver step codes, to
RTC general-purpose register 5 when booted with `oakmoss_mark=0x07000114`; U-Boot
copies the register into the saved env on the next power-on
(`make-own-kernel-stock.sh KMARK=1`), and `scripts/analyze-card-readback.py` names
it from `System.map`. It named `hynitron_driver_init` on 6 of 6 hung XU20 boots, and
every good boot read "exec of init". The same built-in probe also cost every boot a
5 s PMIC-bus stall (the `[i2c6] xfer timeout` in `regulator_init_complete`): with touch
out of the boot it is gone on both boards, and init starts at 2.1 s instead of 7.4 s.

The fix has two parts:

- Both drivers are modules nothing autoloads. Tree patch 080 declares them tristate,
  020 sets them `=m`, and 090 packages `kmod-touchscreen-{hynitron,axs15205}` with no
  `AUTOLOAD`. The launcher loads the board's module once the board has settled
  (spruce `magicx_load_touch`: backgrounded, with a bounded wait for the input node).
  A diagnostic card built with `LATE_TOUCH=1` does the same from the hand-off when
  there is no user card. Loaded late, touch registers after the pad, so the pad is
  event2 and touch event3.
- The Hynitron probe no longer pulses the controller's reset a second time after
  requesting its IRQ. Loaded late, that reset froze the whole XU20 on 10 of 11 loads
  (step marker "resetting the controller", no I2C after it), while the probe's first
  reset, before the IRQ, never did. `cst3xx_firmware_info` already leaves the
  controller in normal mode (`0xD1 0x09`) and nothing is flashed.

Result, SD2 out: Zero 40 7/7 and XU20 8/8 (boot, late probe, power-off). Still open:
`hyn_resume` and the report path's I2C-error recovery pulse reset with the IRQ
installed, so sleep and wake need a test. Every reset pulse is marked (`0x4859030N`).

Never write RTC general-purpose register 4 (`0x07000110`) from U-Boot. A `bootcmd`
that read and cleared it alongside register 5 stopped both boards in U-Boot, before
`saveenv`, on the first pass. Everything else U-Boot reads was byte-identical to a card
that stamped.

## The CPU was powered from a phantom regulator (2026-09-18)

**Not the cause of the stalls (2026-09-18 night):** those were the built-in touch
drivers (section above). The `cpu-supply` fix stands on configuration evidence.

Taken on the day for the cause of the XU20's (and the Zero 40's "picky")
intermittent, trace-less boot stalls. Our board trees descend from the SDK's a133-aw3 reference tree, whose
`cpu-supply` is a TCS4838 buck converter at twi6 0x41 (`tcs0`). MagicX's own
XU20 and Zero 40 trees point `cpu-supply` at the PMIC's `axp2202-dcdc1`, and on
those boards the TCS4838 does not answer: the first boot to reach a shell showed
`[i2c6] xfer timeout (dev addr:0x41)` five seconds into the regulator sweep,
followed by `START can't sendout` (the PMIC bus wedged), while `axp2202-dcdc1`
sat at a fixed 0.94 V with no consumer and cpufreq happily offered 408-1800 MHz
against `tcs4838-dcdc0`. A CPU scaled to 1.8 GHz on U-Boot's 0.94 V browns out
under early-boot load: intermittent, before the first mount, nothing on the
card. That was the theory; the marker kernel later named the touch probes instead.

Fix: `cpu-supply = <&reg_dcdc1>` and `tcs@41` disabled in `boards/xu20` and
`boards/zero40`; `scripts/make-board-dts.py` step 7 now takes the CPU supply from
the board's stock tree and disables the TCS node when the stock rail is not it.
The Zero 28 keeps the reference tree (it has
run for days; whether it carries a real TCS4838 is unverified). Lesson: when a
stock tree exists, diff *every* consumer phandle against ours, not just the nodes
we knowingly changed.

## XU20 "stuck at the boot logo" (2026-09-17/18)

**Resolved (2026-09-18 night): the built-in touch drivers** ("Touch drivers stalled
the boot", above). What follows is the hunt, kept for the record: its findings about
partition tables, Windows and the bootloader screens stand on their own, its guesses
at the stall do not.

**Retracted: "a poweroff is a reboot on the charger."** On 2026-09-17 this section
blamed the charger-mode branch of an AXP `pm_power_off`
(`drivers/power/supply/axp/axp2101/axp2101.c`: VBUS present and charging ->
`machine_restart()`) and added `power_start = <1>` to every MagicX charger node to
switch it off. That driver is not compiled into this kernel, and nothing that is
compiled reads `power_start` from an AXP2202 node (`axp803_battery.c` is built but
binds only AXP803 nodes). The power-off this kernel installs is PSCI's:
`psci_0_2_set_functions()` sets `pm_power_off = psci_sys_poweroff` and
`arm_pm_restart = psci_sys_reset` early in boot, and the AXP MFD
(`drivers/mfd/axp2101.c`) installs its own `axp20x_power_off` only
`if (!pm_power_off)`, which never holds. So power-off and reboot are carried out
by the firmware in the (stock) boot package - the ATF monitor and the SCP - and no
kernel AXP code runs on either path. The property, its generator step and its
contracts were removed on 2026-09-18. Rule: before calling a device-tree property
a fix, confirm the driver that reads it is built (`ls <dir>/<file>.o`) and binds
this node's `compatible`.

**Still open (2026-09-18).** With a clean SD2, a freshly flashed SD1 boots to
spruce once; after a power-off from spruce the next power-on stops at the boot
logo - the tagged logo (so our p1 was read) and no bootloader screen (so U-Boot
took none of its pause, shutdown or low-battery paths). U-Boot's other
diversions cannot hold across consecutive boots: a bootloader message in misc
and a boot-mode flag in the RTC are both cleared after one read
(`sunxi_get_bootcmd_from_misc`, `sunxi_get_bootcmd_from_rtc`), and a recovery
request is ignored when there is no recovery partition. So the persistent state
is on SD1 (the `rootfs_data` overlay, UDISK) or in the always-on domain the
firmware's power-off leaves behind. The base starts `adbd` (`S80adbd`, a
standard `18d1:D002` gadget) before the hand-off (`S95done`), so `adb devices`
against a stuck board separates "base userspace up, stall in the hand-off or
spruce" from "stall in the kernel or early init".

**Leading candidate (2026-09-18, read back off a stuck card): something rewrites
our partition table in place at LBA 2.** Who is not established. The SDK's
boot-time `sunxi_update_gpt` would, but its one unique message ("update gpt
fail") is absent from both stock U-Boots and from ours; "write primary GPT
success" / "write Backup GPT success" also belong to the card-flashing paths
(`download_standard_gpt`, `sunxi_sprite_download_mbr`) and prove nothing. The
candidates are the XU20's stock U-Boot (some other routine) and the DiskGenius
session that card went through; the rewrite follows Allwinner's convention
(the first-usable rule below, as on MagicX's real Zero 40 card), which leans
towards the device. The rewrite expects the layout of MagicX's own table (stock XU20 GPT item: 17 entries at LBA 2, first usable LBA
32768). Our cards used the SDK card packer's layout (128 entries at LBA 2048),
so the rewrite laid a 32-sector array over LBA 2-33 - erasing boot0 at sector 16
on the very first boot - and left a primary header pointing its entries at LBA
34848, with a valid backup moved to the card's physical end. Its header `reserved1` is 0 on the card. U-Boot then reads the
backup ("Using Backup GPT") and the kernel copes because U-Boot passes `gpt=1`
(force_gpt), so the table state alone does not explain the stall - but every
boot after the first starts from the boot0 mirror at sector 256, a path never
proven on this board, and that is the one card-side difference every stuck boot
shares. The 09-16 "no-LED cards, sector 16 zeroed" blamed on Windows/DiskGenius
fit the same mechanism before the mirror existed. `make-own-kernel-stock.sh`
now writes the table in the stock shape: 16 entries at LBA 2 (a 4-sector array
ending at LBA 5) and first usable LBA 6. The last value matters: the rewrite
writes the array at LBA 2 but sets the header's entry pointer to
first_usable - array sectors (the old cards: 34880 - 32 = the 34848 read back;
MagicX's real Zero 40 card: 20 entries, first usable 7 = 2 + 5), so the primary
table survives only when first_usable = 2 + array sectors. Partitions, order and
PARTUUIDs are unchanged. The Zero 40 is "picky" (sometimes boots, sometimes sticks). Our Zero 28 U-Boot
cannot rewrite at boot: `CONFIG_SUNXI_UPDATE_GPT` is off (Kconfig default n, not
set in our build) and the routine's unique string is absent from the binary. Unverified on hardware until fresh
cards boot repeatedly. Reading a card
back: a DiskGenius `.pmfx` is a card-ordered index of 1 MiB zlib chunks at file
offset 0x1000 (16-byte entries: u64 offset, u32 stored size, u32 compressed size;
compressed size 0x100000 = stored raw), but DiskGenius regenerates the partition
table in its image; read the card raw instead.

**Resolved for the XU20 (2026-09-18): Windows re-detecting a flashed card breaks
it.** Raspberry Pi Imager's own read-back verified a card, yet re-seating it in
the PC and checking again showed the table rewrite (sectors 1-4, 16-17, 21-33).
Windows rewrites our table whenever it detects the card, because the table's
backup sits before the card's end. Win32DiskImager leaves the card attached, so
every card flashed with it reached the XU20 already rewritten. A card flashed
with Pi Imager and taken straight to the XU20, never re-detected by Windows,
booted and survived repeated power cycles. Lab rule: flash with Raspberry Pi
Imager, keep its verification on, and move the card to the device straight after
it ejects. Never re-insert a card into Windows between flashing and booting, and
treat any card that has been re-inserted as rewritten; reflash it before testing.
How the rewritten state lets boot 1 succeed but stalls later boots is not
explained; the new-layout (`GPT_LAYOUT=stock`) card, which Windows leaves
structurally intact, was never tested unrewritten.

**The table rewrite is done on the PC, not the XU20 (2026-09-18).** A card
written with Win32DiskImager and checked straight away, never booted, came back
with the rewrite: backup moved to the card's end, header entry pointer =
first_usable - 32 (34848), 128 entries written at LBA 2-33 over boot0 at 16.
Flashing alone does not do it (Zero 28 cards have the same layout and no boot0
copy at 256, and survive flashing), and every rewrite seen followed DiskGenius or
a `Get-Disk`/`Get-Partition` query, so the writer is almost certainly Windows
storage management "repairing" a GPT whose backup is not at the end of the
disk. Nothing in the XU20's boot path is shown to write the table; the "boots
once, then sticks" stall happens with the table intact. Card tooling must find
disks with `Get-CimInstance Win32_DiskDrive` only (`scripts/verify-card.ps1`
compares a written card with its image that way, read-only), never Disk
Management, DiskGenius or `Get-Disk`, and the 09-16 "sector 16 zeroed" cards
were this too.

**Result (2026-09-18 morning): the stock-shaped table is worse.** A card built with
it (`xu20-gptfix`: 16 entries at LBA 2, first usable 6) never reached userspace,
not even on its first boot: read back raw, its `rootfs_data` and UDISK had never
been mounted (mount count 0, no last-mount time), no boot-log line, pstore empty,
while the old layout (128 entries at LBA 2048) booted the first time on two
cards. On that card the table had only its backup moved to the card's end
(primary valid, boot0 intact at 16), so the stall is not the rewrite's damage.
Two explanations were checked and ruled out: U-Boot's root rewrite ("set root
to /dev/mmcblk0p<n>") needs a `root_partition` env variable we do not set, and a
failed boot-image verification shows `red_warning.bmp` and powers off rather
than holding the logo. `make-own-kernel-stock.sh` therefore defaults to the old
layout again (`GPT_LAYOUT=sdk`); `GPT_LAYOUT=stock` stays as a diagnostic. The
same read showed 8 sectors of `orange_warning.bmp` zeroed on the card although
the flashed image (md5 checked) had data there: the flashing step can silently
zero nearly-empty sectors. Next diagnostic: the fbcon kernel on the old layout
(`xu20-fbcon`), to see whether a stuck boot ever starts the kernel.

**What the afternoon's failures actually were (resolved 2026-09-17 evening).**
The SD2 card. The base paints nothing until spruce starts: `rc.local` runs the
hand-off, which waits 10 s for `/mnt/SDCARD` and then, with nothing to run, calls
`poweroff`. The base mounts SD2 only from `/dev/mmcblk1` or `/dev/mmcblk1p1`
(`/etc/config/fstab`, `anon_mount 0`) and only as FAT32 (the kernel has no
exFAT). An SD2 that does not mount therefore looks, on every SD1 image alike,
like a board stuck at the boot logo. Reformatting SD2 (FAT32) and recopying the payload ended it; the first
card to boot afterwards was `fix-xu20-pol0` (`lcd_pwm_pol 0`, touch flag 1), confirmed live by its rootfs PARTUUID.

Read this first next time, not the boot chain: every boot appends its decision
to `/mnt/UDISK/oakmoss-boot.log` on the SD1 card (p8, ext4, readable on a PC
with `mount -o ro /dev/sdX8`): `running /mnt/SDCARD/.tmp_update/updater` means
the base booted and SD2 mounted; `no card or nothing to run after 20 x 0.5 s;
powering off` means SD2 never mounted; no `=== boot` line means the kernel never
got that far. The kernel command line also carries the stock U-Boot's own
verdicts, worth reading on any live board: `bootreason=button|charger|usb`
(the PMIC power-on source), `androidboot.vbmeta.device_state=locked`,
`androidboot.secure_os_exist=0`, `androidboot.mode=normal|charger`, and
`disp_reserve=<size>,<addr>` (U-Boot's framebuffer, inherited for the smooth
boot).

**The stock bootloader's own screens are invisible on this panel.** Its
verified-boot warnings (`orange_warning.bmp`, `yellow_pause_warning.bmp`,
`yellow_continue_warning.bmp`, `red_warning.bmp`) are 800x1280 and its
low-battery screen (`bat/low_pwr.bmp`) is 480x800, sized for a reference board;
the XU20 framebuffer is 1024x768 and the stock U-Boot refuses anything larger
("no support big size bmp[%dx%d] on fb[%dx%d]", in its binary). So the ORANGE
five-second window (a power-key press there = shutdown), the YELLOW pause
(a press = wait for a second press; the second press = continue) and a
low-battery shutdown all show the boot logo and nothing else. A tap that turns
the board off is the orange window; a board that sits at the logo until tapped
is the yellow pause. `scripts/make-boot-resource.py <stock> <out> <board>` writes
board-sized replacements (each naming its state, pre-rotated like the stock
logo) plus a tagged boot logo into a copy of the stock partition, and
`make-own-kernel-stock.sh BOOTRES=<out>` ships it in p1. A logo with the tag
proves that partition was read; a warning on screen names the U-Boot path.
(Zero 40 fb 480x800 and Zero 28 480x640 refuse the same bitmaps.)

Two diagnostic lanes came out of the hunt. `KDEBUG_FBCON=1` (above) put the kernel
log on the panel but the disp framebuffer went blank under fbcon on the XU20, so it
is unproven there. `PSTORE=1` in `make-own-kernel-stock.sh` adds a 2 MB pstore
partition and points the built-in `pstore_blk` at it: a panic or a restart writes
the kernel log to the card, where it survives the cold power-off (`max_reason=6`:
panic, oops, emergency, restart, halt and power-off). Read it after
the next good boot with `mount -t pstore pstore /sys/fs/pstore`.

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
  stock tree: lcd0 block, simplepad map, wlan node, battery model, and
  (2026-09-17) twi1 on the stock PB4/PB5 pins with the stock touch node.
- **Touch** `sdk-patches/tree/080-touch-hynitron-axs15205.patch`. XU20:
  Hynitron **CST340** at 0x5a (the stock kernel's `hyn_ts_data_init` says chip
  3340, main address 0x5a, five points, no axis flips), served by Radxa's
  Allwinner-flavoured `hyn_ts` driver with three changes: the I2C address is
  the node's `reg` (the driver's default is 0x1a), the axis flags are the ctp
  node's `ctp_revert_*`, and a `-EBUSY` on the reset/irq lines is accepted
  because the ctp framework (`init-input.c`, node `ctp`) has already requested
  `ctp_wakeup` = PB7 and `ctp_int_port` = PB6. Its 1.3 MB of embedded firmware
  images are guarded out (auto-update is off). Zero 40: **AXS15205** at 0x3b,
  `axs15205.c` written from the stock kernel's `axs_ts_probe` /
  `axs_ts_interrupt` (disassembled): no command prefix, no checksum, one
  32-byte `i2c_master_recv` per interrupt, frame = status, count nibble,
  then six bytes per contact (event|x_hi, x_lo, id|y_hi, y_lo, weight, area);
  five type-B slots on 480x800, INT PB6, 120 ms after probe for the panel
  (whose reset line resets the chip; no reset gpio of its own). The axs_ts
  sources circulating publicly are the newer command-prefixed protocol and do
  not apply. Touch coordinates are raw panel coordinates on both boards:
  PyUI's touch watcher undoes DISPLAY_ROTATION (180 on the XU20) itself. Both
  drivers are modules loaded after boot since 2026-09-18 ("Touch drivers
  stalled the boot").
- **Touch orientation, measured 2026-09-17.** The controllers publish the right
  ranges (the XU20's Hynitron reports 0..1024 by 0..768, matching its panel), so
  scaling was never the issue; how the digitizer is mounted is. On the XU20 the
  digitizer's X axis runs opposite the display: a touch at the top left landed at
  the top right, and at the bottom left landed bottom right, so X is mirrored and
  Y is already correct. `ctp_revert_x_flag = <1>` on that board puts the driver's
  output back in the panel's own frame, which is the frame PyUI's rotation inverse
  expects; Y must stay 0 or the 180 rotation is undone. The Zero 40 needs neither
  flip and was correct as built. This supersedes the earlier note that both flags
  stay 0 and PyUI does all the work: PyUI undoes the *display* rotation, and the
  tree describes the *mounting*, which is a different fact.
- **The touch rail (found on the first Zero 40 touch card, 2026-09-17).** The
  AXS15205 probed and PyUI attached to `axs_ts`, but every frame read failed
  with the sunxi TWI's "START can't sendout" for the first minutes, decaying to
  none after ~15 min. Not CPU speed (rate unchanged under a 1.4 GHz load) and
  not the driver (the stock kernel polls START the same 255 times): the boot
  log had `6000000.disp supply cldo2 not found, using dummy regulator` at
  1.58 s and `axp2202-cldo2: disabling` at 3.79 s, the first failure at 3.90 s.
  The disp driver enables each `lcd_powerN` name with `regulator_get()` on the
  disp device, which needs a `<name>-supply` phandle on the disp node; the
  Zero 28 tree only carries `cldo4-supply`, the stock trees name **cldo2** as
  `lcd_power`, so nothing held cldo2 and the kernel's unused-regulator sweep
  switched it off. The panel kept working (its own rails are elsewhere) but the
  touch controller's I2C side sits on cldo2, and the dead rail floated up
  through leakage over a quarter of an hour, which is the decay. The generator
  now adds a disp supply for every `lcd_powerN` rail the stock tree names
  (`cldo2-supply = <&reg_cldo2>` on both boards). The XU20 shares the same
  `lcd_power = "cldo2"`, so its Hynitron sat on the same dead rail.
- **XU20 after a menu reboot (2026-09-17, card 2311).** Touch worked on the
  first boot; a menu reboot (`save_poweroff.sh --reboot`) left the board at the
  boot logo on every following start. The stock U-Boot passed `bootreason=button`
  on the good boot; nothing in our chain writes the RTC boot flag or the misc
  partition. That boot's log also shows the simplepad oops (fixed by `085-*`, not
  a boot stopper).
  The remaining suspect is the `sunxi_encrypt` object (the Zero 40's,
  `ENCRYPT_OBJ=zero40`): a failed check restarts the kernel before the display is
  taken over, which looks like a logo that never moves. Test card:
  `ENCRYPT_OBJ=stub`.
  Superseded (2026-09-18): the reboot powered off because the hand-off raced
  spruce's own shutdown (fixed in `overlay/usr/magicx/bin/runmagicx.sh`), and the
  stops at the logo were the built-in touch probes ("Touch drivers stalled the
  boot"); the object authenticates on this board.
- **Card** `scripts/make-own-kernel-stock.sh`: stock boot0 (at 16 and 256),
  stock package with its dtb item replaced by ours (`toc1-item.py`, checksum
  redone), our kernel in a header-v2 boot image that also carries our tree
  and no header command line, env with root=PARTUUID through mmc_root and
  rootfstype=squashfs, our rootfs squashfs in p6, rootfs_data/UDISK ext4.
  Whichever tree U-Boot hands the kernel, it is ours; U-Boot itself now reads
  our tree for its own panel init, which carries the stock timings.
- The XU20 kernel object is the Zero 40's (`ENCRYPT_OBJ=zero40`); see "The
  sunxi_encrypt object is a boot gate" below.

## The sunxi_encrypt object is a boot gate (2026-09-17)

MagicX's prebuilt `drivers/char/sunxi_encrypt/encrypt` (one object per board) is
an authentication driver, not a passive identity device: it checks the board it
is running on and, when the answer does not match what was compiled into it,
restarts the kernel. A kernel linked with another board's object therefore
reboots forever at the boot logo and leaves no log anywhere; that was every
own-kernel XU20 stop until the object was changed. Which object a board needs is
the per-board `ENCRYPT_OBJ` setting: the XU20 takes the Zero 40's, and with it
boots, runs spruce on the 1.19 GPU stack and brings WiFi up through the Realtek
driver (verified on the unit, reachable over SSH). `ENCRYPT_OBJ=stub` builds
`sdk-patches/sunxi_encrypt/encrypt_stub.c` instead, a misc device that touches no
chip, for any board without a matching object.

How the check works is deliberately not documented here.

The XU20 panel scans upside down relative to the case: the vendor's Android
sets `ro.surface_flinger.primary_display_orientation=ORIENTATION_180` (the
Zero 40's says 0) and rotates in the compositor. Our display driver has no
whole-output flip, so spruce rotates by 180 on this board the way it rotates
the Zero 28 by 90.



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

- The "newer board revision" fixes in main-zero40 v20260202-1 are not in the
  SDK drop (the Zero 40 and XU20 panel and touch drivers are ours since
  2026-09-17: `070-*`, `080-*`; touch works on both, loaded after boot as a module).
- No exFAT in kernel 4.9 and no FUSE exfat package in the Tina tree: user cards
  over 32 GB must be FAT32.
- busybox 1.27.2 has no `bc`.
- XR829 26 MHz vs 40 MHz crystal unverified (26 assumed, as Knulli ships); moot
  on boards with the Realtek radio.
- No `harbourmaster` (PortMaster) device profile for either board yet.

## Backlight polarity (2026-09-17/18)

All three MagicX boards ran their backlight curve inverted at once: a higher
brightness setting made the screen darker. The cause is not in spruce and not in
the display driver. Measured across four A133P boards, brightness reaches the
panel identically everywhere: `set_backlight` maps 1..10 to 1..255 and
`disp_lcd_set_bright` turns that into a duty that rises with it. Setting 2 and
then 9 and reading the driver back through `/sys/class/disp/disp/attr/sys` gives
29 and 226 on every board, the TrimUI Smart Pro included, whose backlight is
correct. The direction of the curve is therefore decided entirely by
`lcd_pwm_pol` against each panel's LED driver.

| board | polarity | where it comes from |
|---|---|---|
| Zero 28 | 0 | the SDK's aw3 default is 1 and runs inverted, so this board has its own tree (`boards/zero28/board.dts`), identical to the SDK's but for this one property |
| Zero 40 | 1 | the stock tree's value |
| XU20 | 1 | the stock tree's value |
| TrimUI Smart Pro | 0 | vendor firmware, correct as shipped; recorded as the control |

This project briefly forced 0 on the Zero 40 and the XU20 (2026-09-16) after a dim
backlight was read as inversion. That was wrong: MagicX's own firmware ships 1 on
both panels, and 0 inverted them. `make-board-dts.py` no longer overrides the
value.

**Not settled (2026-09-18).** With the stock 1 in place, spruce's brightness still
ran inverted on the XU20 and the Zero 40 (a higher setting was darker), while the
Zero 28 at 0 is right. The trees keep the stock value and spruceOS mirrors the level
on those two boards instead: its MagicX device class maps setting N to 256 minus the
usual duty (`BACKLIGHT_REVERSED`), and the platform files' `MAGICX_BACKLIGHT_REVERSED`
tells pseudo-sleep which end is dark. This reading and the 0-is-inverted one above
cannot both describe the same hardware; which polarity is physically right is open.

