# Cards: SD1 and SD2

spruce can live on the oakMOSS card itself (SD1) or on a second card (SD2). An oakMOSS image is
smaller than any card it goes on. On the first boot the base adds a FAT32 partition named
`SPRUCEOS` in the free space of SD1. A PC sees it as an ordinary drive, so spruce can be
copied onto it.

## Mounts

The base mounts the cards itself at every boot (`overlay/usr/magicx/bin/oakmoss-cards.sh`), each
card once, under a name for the physical card:

| path | what |
|---|---|
| `/mnt/sd1` | SD1's `SPRUCEOS` partition |
| `/mnt/sd2` | SD2 |
| `/mnt/SDCARD` | a bind mount of the host card, the one whose launcher runs |
| `/media/sdcard1` | a bind mount of the other card, while both are in |

A bind mount shows the real device in `/proc/mounts`, so the device behind `/mnt/SDCARD` can be
read from there. spruce's power-off already unmounts "other mounts of the same device" (it was
written for the Flip's `/userdata`). `/media/sdcard1` is where spruce's PyUI looks for a second
`Roms` folder (the Miyoo Flip's layout; the MagicX device classes inherit it). Games on the
other card are listed next to the host's without a spruce change.

## Which card hosts

Only a card with a frontend (`magicx/init.sh` or `.tmp_update/updater`) can host. Between two
such cards, the newer spruce wins: the version in `spruce/spruce` (x.y.z) first, then
`BUILD_UNIX` from `spruce/build` where a card has one. A card without either counts as oldest.
A tie goes to SD1. Older spruce versions are never turned away.

| cards | `/mnt/SDCARD` | `/media/sdcard1` | what runs |
|---|---|---|---|
| no SD2, no spruce on SD1 | SD1 | - | the no-frontend screen |
| no SD2, spruce on SD1 | SD1 | - | spruce from SD1 |
| spruce on SD1, SD2 without spruce | SD1 | SD2 | spruce from SD1 |
| no spruce on SD1, spruce on SD2 | SD2 | SD1 | spruce from SD2 |
| spruce on both | the newer (SD1 on a tie) | the other one | the newer spruce |
| SD2 in, no spruce on either | SD2 | SD1 | the no-frontend screen |

The outcome is in `/tmp/oakmoss-cards` (`HOST`, `SD1_DEV`, `SD1_ROOT`, `SD2_DEV`, `SD2_ROOT`) and
in `/mnt/UDISK/oakmoss-boot.log`.

## Finding SD2

SD2 can take a moment to appear after power-on. The base reads the slot's card-detect switch
from the kernel's GPIO list (debugfs, mounted if needed): one line labelled `cd`, `hi` with no
card. That is PF6 on these boards, pulled up, and a card pulls it low. An empty slot ends the
wait at once. Otherwise the base waits for the card up to 10 s, or 3 s when SD1 already has a
frontend. The same wait applies where the kernel shows no single `cd` line.

The SDK's `fstab` entries that mounted SD2 at `/mnt/SDCARD` are dropped at build time. A card
inserted after the election is handled by `/etc/hotplug.d/block/20-oakmoss-cards`:
- It is mounted at `/mnt/sd2`, and at `/media/sdcard1` when SD1 hosts. It never lands on
  `/mnt/SDCARD`.
- Pulling it out unmounts both.
- Pulling the host card is left alone: the launcher runs from it.

## No frontend

When no card has a launcher, the base looks for updates first, then:

- **with the charger in**, it shows "No frontend detected, charging" with the battery level,
  as in charge mode. The screen dims after 30 s, and any button wakes it. The power key checks
  the cards again; unplugging the charger switches the board off.
- **without a charger**, it shows "No frontend, power off in 10s", then switches off.

## Updates

`oakmoss-<board>-*.omupd` files are read from the root of both cards (`/mnt/sd1`, `/mnt/sd2`).
This happens before any frontend or the no-frontend screen, so a base update works even with
no spruce on either card (`docs/updates.md`).

## The SPRUCEOS partition

`oakmoss-sd1part` (`src/sd1part.c`, built static by `build.sh`) handles the partition. The
image has no GPT tool: the SDK's util-linux 2.25 `sfdisk` handles MBR tables only.

- It starts at a fixed 2 GiB. That keeps it clear of the image (about 1.07 GiB with both
  slots) and leaves the image room to grow. It runs to the end of the card, rounded down to
  1 MiB.
- Cards with less than 512 MiB past 2 GiB get no partition, and neither do cards whose
  partitions already reach 2 GiB (the stock-chain layouts).
- The backup GPT moves to the end of the card, and the old backup header is cleared. Windows
  "repairs" a GPT whose backup is not at the end, and that repair wrote over boot0
  (`docs/hardware-notes.md`).
- The partition gets the Microsoft basic data type, and an entry in the image's hybrid MBR
  as well, so a PC mounts it.
- The running kernel learns about it through `BLKPG`, so no reboot is needed. On later boots
  it comes from the table.
- **New partition:** formatted FAT32 with busybox `mkfs.vfat`, label `SPRUCEOS`.
- **Re-flash:** writing an image again leaves everything past its end alone. If a FAT32 volume
  is already at 2 GiB, the partition is reattached with that volume's size and never
  formatted.
- A partition that holds no filesystem at all is formatted. This is the case when power was
  lost between adding the partition and formatting it. A partition that cannot be read is left
  alone for that boot.

**Before putting SD1 in a PC, boot it once in the device.** Until that first boot the backup
GPT is not at the end of the card, so Windows may rewrite the table over boot0.

## Debug records

The debug records and kernel marks (`docs/building.md`) follow a flag on SD1's partition. They
stay on unless that partition can be read and holds no `oakmoss-debug` file at its root, so
on a card with SD1 installs they are off until that file is created. `runmagicx.sh` writes the
answer to the env as `oakmoss_debug`. The records follow at once, and the kernel marks from
the next boot.

## What spruce has to handle

spruce owns these; the base does not change them. Both matter only when SD1 hosts.

- **`SD_DEV`.** `Zero28.cfg`, `Zero40.cfg` and `XU20.cfg` set `SD_DEV="/dev/mmcblk1p1" # need to
  verify this`. That is SD2.
  - **Power-off:** `save_poweroff_stage2.sh` finds the card it must unmount cleanly from
    `SD_DEV`. With SD2 in, it unmounts SD2 and leaves the host to the base's final `umount -a`.
  - **Read-only check:** `read_only_check` logs SD2's mount line; that is only a log.
  - **The fix:** one line per file, as `dArkMossCommon.cfg` already does it:
    `export SD_DEV="$(awk '$2=="/mnt/SDCARD"{print $1; exit}' /proc/mounts 2>/dev/null)"`.
- **USB storage mode** (`App/USBStorageMode/usb_gadget.sh`) exports a fixed `/dev/mmcblk1p1`
  on these boards. When SD1 hosts, it would hand SD2 to the PC while the base still has it
  mounted at `/mnt/sd2`, and a card mounted on both sides can be corrupted.
  - **The fix:** take `STORAGE_DEVICE` from the `/mnt/SDCARD` mount.
  - **Until then:** do not use USB storage mode while SD1 hosts.
- `repairSD.sh` already takes the device from the mount.

## Tested on hardware

On the Zero 28, 2026-10-09, with a 31.3 GB card:
- **First boot:** the partition was added and formatted (27,801 MiB, about 3 s).
- **macOS:** with the card in a Mac after that boot, SPRUCEOS mounted, and the card booted
  afterwards.
- **Re-flash:** the partition was reattached with its files.
- **Election:** SD2 hosted when SD1 had no spruce, and SD1 hosted on a tie.
- **No frontend:** the charging screen appeared after the charge-mode power key, and the board
  powered off when the charger was pulled. Without the charger it showed the 10 s power-off.
- **Debug flag:** both ways.

Still to prove: the card in Windows after its first boot, and the other boards.
