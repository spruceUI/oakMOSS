# oakMOSS on the TrimUI A133P boards

Written for oakMOSS maintainers. Status 2026-10-25: the TrimUI Brick is in progress on branch
`feat/trimui-a133p`; the Brick Pro and Smart Pro follow. Desk-checked only: nothing here has been
built with the SDK's compiler or booted on a unit yet. The Smart Pro S is an A523 on a 5.15 kernel
and out of scope.

## What a card carries

The card boots our kernel and rootfs on TrimUI's own boot chain, from the TF slot, beside the stock
firmware on the eMMC. Take the card out and the unit boots stock.

| Card region | Content |
|---|---|
| boot0 (sectors 16 and 256), U-Boot package (32800) | TrimUI's, byte-identical, device tree included (`OWN_STOCK_DT=1`) |
| `bootloader` (boot-resource) | TrimUI's, byte-identical (boot logo, charge pictures) |
| `env`, `env-redund` | TrimUI's env, redundant format, with our boot scripts |
| `boot`, `rootfs` (+ `boot_b`, `rootfs_b`) | our kernel in TrimUI's v0 boot-image header, our squashfs |
| `rootfs_data`, `UDISK`, SPRUCEOS | ours (SPRUCEOS is made on the first boot) |

`scripts/make-own-kernel-stock.sh brick` builds it from TrimUI's public 1.1.1 firmware
(`scripts/unpack-trimui-stock.sh brick`; release zip and every item pinned in `scripts/lib.sh`) and
checks that boot0, the package and the boot-resource on the image are the stock items, byte for byte.

## Why the stock chain stays whole

TrimUI's recovery lives in its U-Boot: the volume-key awimg updater, `reboot recovery`, and USB
efex; the rescue card and boot-ROM FEL need nothing on the eMMC at all
(`CFW/Spruce/docs/research/oakmoss-to-trimui-a133p/emmc-awimg-sd-install-viability-20261012.md`).
Keeping the chain byte-identical on the card keeps all of them, and keeps the later eMMC install
honest. So a card marked `/usr/magicx/keep-boot-chain` refuses update packages that would write
boot0, the U-Boot package or the boot-resource (`oakmoss-update.sh`, `tests/test-update.sh`).

## The kernel on TrimUI's device tree

All three stock trees are complete 4.9 Tina trees. Besides what the V90S tree (which our kernel
already boots) enables, they enable only the TCS4838 CPU regulator, the LED controller, the XR829
WiFi and Bluetooth nodes (all in our kernel) and `addr_mgt`, which our kernel lacks (harmless).
They carry no board compatible: `model = "sun50iw10"` on all three.

The panel driver all three name, `otm1289a`, is tree patch 160 (round 33): Knulli's TrimUI driver
ported to 4.9 disp2. The stock U-Boot reads the panel module's DCS ID registers and appends
`lcd=<controller>` to the command line (lab units: Brick `jd9168`, Brick Pro `gh7003`, Smart Pro
`er68576`); the driver follows it, and reads the IDs itself only without it. `trimui_lcd=` forces a
table.

## Booting from the card past the eMMC

The eMMC is always `mmcblk0` and the card `mmcblk1`. Two consequences, both handled:

- **root.** TrimUI's U-Boot rewrites `mmc_root` from `root_partition` as `/dev/mmcblk0pN`
  (`board_helper.c`), which names the eMMC. With `OWN_EMMC=1` the env roots by PARTUUID through its
  own variable: `bootcmd=run oakroot_${root_partition} setargs_mmc boot_normal`, with
  `oakroot_rootfs` and `oakroot_rootfs_b` setting `oak_root`. The A/B switch (`root_partition`)
  works unchanged. U-Boot also rewrites `partitions` with `mmcblk0` names; the own lane's
  `/etc/init.d/boot` patch points `/dev/by-name` at the root's disk.
- **nothing mounts the eMMC.** `oakmoss-cards.sh`, the early probe and the diagnostic hand-off skip
  MMC devices whose sysfs `device/type` is `MMC` (SD cards read `SD`); the stock eMMC's `p1` is its
  boot-resource. `tests/test-cards-emmc.sh`. The base fstab mounts only `/dev/by-name` entries
  (`anon_mount` 0).

## Input

The Brick's buttons are GPIOs that TrimUI's closed userspace daemon `trimui_inputd` reads through
`/dev/mem` and turns into a uinput pad (the Brick Pro's sticks come over `/dev/i2c-3`, the Smart
Pro's from two MCUs on `ttyS3`/`ttyS4`). Our kernel has everything it needs. With
`OWN_TRIMUI_INPUTD=1` the image carries the board's own copy from the stock rootfs, started by
`/etc/init.d/trimui-inputd` after the GPIO lines stock sets first (`OWN_TRIMUI_GPIO`; Brick: PD11
high for VCC-5V, PH3 rumble low, PH19 DIP switch in). **Such an image is local only** (user,
2026-10-25): `/usr/magicx/local-only` and `publish=NO` in BUILD-INFO say so. Open alternatives: a
GPL kernel driver for the Brick's buttons in TortOS (under review), and `Jpe230/Trimui_Inputd`
(GPL-3.0; Smart Pro, Smart Pro S, Brick).

## Building a Brick card

```bash
scripts/fetch-inputs.sh                       # includes TrimUI's Brick 1.1.1 zip
scripts/unpack-trimui-stock.sh brick          # -> inputs/trimui-brick-stock (needs debugfs)
scripts/apply-sdk-mods.sh                     # round 33: tree patches 160-161, stamp 28
scripts/build.sh image brick
scripts/make-own-kernel-stock.sh brick builds/<stamp>-brick
```

The first cards were diagnostic (`OWN_DIAG` unset): the early probe turns the panel magenta when our
root runs and writes its report to the card's UDISK; the hand-off shows the colour ladder. Since the
Brick boots spruce (2026-10-26), `OWN_DIAG=0` gives it the stock hand-off, as the V90S and V20 have;
`DIAG=1` still builds the diagnostic card.

## Not done yet

- spruce: a platform for the `brick` marker on oakMOSS (an unknown marker boots as a Zero 28).
- The Brick Pro and Smart Pro: pins, board files, their `trimui_inputd` prerequisites (the Smart
  Pro's stick MCU power on PD14/PD18), and their release formats (the Brick Pro's is a 7z).
- Boot screens, charge screens of our own (the stock boot-resource stays for now).
- The eMMC install (a per-model awimg), only after the card works.
