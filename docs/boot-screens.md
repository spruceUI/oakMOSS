# Boot screens

On the Powkiddy V90S and V20, the panel shows an oakMOSS screen at every step of a boot and a
shutdown, and never goes blank between U-Boot and spruce. This is the oakMOSS form of what
dArkMoss does for the XU Mini M and the G350 (`bootlogo.service` and its siblings there). The
other boards opt in the same way, by shipping the frames (below). Until one does, nothing
changes for it.

## What the panel shows

| When | Screen | Drawn by |
|---|---|---|
| U-Boot | the spruce tree and "oakMOSS" | U-Boot: `bootlogo.bmp` in the boot-resource partition |
| init starts | the same, with "Loading..." | `/etc/init.d/bootframe` (START 02) |
| the launcher starts | "Loading frontend" | `runmagicx.sh` |
| an update installs | "Updating, do not power off" | `oakmoss-update.sh` (already there) |
| reboot | "Rebooting" | `/etc/init.d/shutdownframe` (STOP 00, the first K script) |
| power-off | "Shutting down" | `/etc/init.d/shutdownframe` |
| plugged in while off | U-Boot's charge picture, then the charge screen | U-Boot `bat/battery_charge.bmp`, then `/etc/init.d/chargeframe` and `charge-screen.sh` |
| debug boot | the kernel log and the boot log, as text | `/etc/init.d/debugtext` (START 01), `oakmoss-fbtext` |

Every screen uses one layout, the one the charge screen already used. The tree and "oakMOSS" stay
in place, and only the status line under them changes. U-Boot's logo has the same layout with
an empty status line, so the first Linux frame only adds "Loading...".

The gap that was blank before: the GPU driver's fbdev setup clears U-Boot's picture before init
runs, and nothing drew again until spruce started. `bootframe` draws right after that clear.
`chargeframe` did the same for charger boots.

## The pieces

- `scripts/make-charge-screens.py <board>` renders every frame. The boards in its
  `BOOT_FRAMES` (v90s, v20) also get:
  - `boot-loading`, `reboot` and `poweroff` in `boards/<board>/overlay/usr/magicx/share/charge/`;
  - full-screen U-Boot pictures in `boards/<board>/boot-resource/`: `bootlogo.bmp` (32-bit, like
    the stock logo), `bat/battery_charge.bmp`, `bat/bat0.bmp`, `bat/bempty.bmp` and
    `bat/low_pwr.bmp`. The Powkiddy U-Boot reads `bat0`, `battery_charge` and `bempty` (strings
    in its binary).

  Run it in the Lima VM, which has the DejaVu fonts: `lima bash -lc 'cd <worktree> &&
  python3 -I scripts/make-charge-screens.py v90s'`. Its output is deterministic.
- `charge-screen.sh boot | frontend | reboot | poweroff` draws one frame and exits. It draws
  only when the board ships `boot-loading.rgba.gz`, which is the opt-in, and never during a
  debug-text boot. `tests/test-screens.sh` covers both rules.
- The three init scripts are enabled by their links in `overlay/etc/rc.d` (`S01debugtext`,
  `S02bootframe`, `K00shutdownframe`), as `chargeframe` is: the image build creates no links.
- The `shutdownframe` script tells a reboot from a power-off by `OAKMOSS_SHUTDOWN`, which procd
  patch 901 passes to the K scripts. Without that variable it draws nothing.
- U-Boot's pictures: for a stock-chain board with `OWN_BOOTRES_FILES=1` in its `board.conf`,
  `make-own-kernel-stock.sh` copies the stock boot-resource partition (`BOOTRES=`) and replaces
  the board's files in the copy with mtools, reading each one back. The rest of the partition
  stays as it was: the fonts, the wavefiles and `lcd_compatible_index.txt`, which this U-Boot
  reads and writes. The copy is still vendor data, so it stays local, like the image around it.
  The board's SDK image (never flashed) gets the logo alone: the full set overflows its 4 MiB
  boot-resource partition, and a bigger partition would change the boot package's tree.
  An own-lane `.omupd` carries no boot-resource (`docs/updates.md`), so the U-Boot pictures reach
  a card by flashing an image. The Linux frames come with the rootfs, so an update brings them.

## Debug text

dArkMoss shows kernel text instead of its logos when `darkmoss-debug` is on BOOT. In oakMOSS
the switch is the file that already turns debug mode on: `oakmoss-debug` at the root of SD1's
`SPRUCEOS` partition (`docs/debugging.md`).

- `/etc/init.d/debugtext` runs first in the boot. It mounts SPRUCEOS read-only just to look for
  the file. If the file is there, it starts `oakmoss-fbtext`, which shows:
  - the kernel log (`/dev/kmsg`, from the start of the boot);
  - the lines `/mnt/UDISK/oakmoss-boot.log` gains, which come from the card election, the
    update check and the charge screen.

  The title row names the board, the oakMOSS version and the kernel.
- The boot screens stay off for that boot. `runmagicx.sh` stops the text screen before an
  update, a no-frontend screen or the launcher takes the panel, so the last lines stay up
  until the launcher draws.
- At a reboot or power-off, `shutdownframe` starts the text screen again, with the kernel log
  from that moment on. It leaves out the boot log, because an open file would keep UDISK from
  unmounting.
- The kernel console stays off the panel: `fbcon` is only in `KDEBUG_FBCON=1` debug kernels
  (`scripts/build.sh`), so this needs no kernel change. `oakmoss-fbtext` (`src/fbtext.c`) is a static tool built by `build.sh`. It
  draws DejaVu Sans Mono in 8x16 cells, 80 columns by 30 rows at 640x480, from
  `src/fbtext-font.h`, which `scripts/make-fbtext-font.py` writes (run it in Lima too).
  `tests/test-fbtext.sh` renders into files on any Linux host.

## Charge mode on the Powkiddy boards

Plugged in while off, the stock U-Boot already enters charge mode. It shows
`bat/battery_charge.bmp` and boots the kernel with `androidboot.mode=charger`, and the base's
charge screen takes over (V90S, 2026-10-25: "battery icon, then oakMOSS charging screen").
Before this change the battery icon was the stock one. With the boards' own boot-resource it
is oakMOSS's charge picture, in the same layout as the charge screen that follows.

The charge screen used to wait for the MagicX pad (`magicx-input`), so on these boards only the
power key woke it, after a 10 s wait. It now also takes the joypads `Powkiddy V90S Gamepad` and
`Powkiddy V20 Gamepad`.

## Adding a board

1. Add the board to `BOOT_FRAMES` in `make-charge-screens.py` and render it.
2. For a stock-chain board, set `OWN_BOOTRES_FILES=1` in its `board.conf`. On the board's own
   chain, `build.sh` already packs `boards/<board>/boot-resource`.
3. Check the U-Boot's picture names against its binary (`strings u-boot.bin | grep -i bmp`),
   and the charge screen's input names against the board's input nodes.
