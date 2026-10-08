# Cards: SD1 and SD2

spruce can live on the oakMOSS card itself (SD1) or on a second card (SD2). An oakMOSS image is
smaller than any card it goes on. On the first boot the base adds a FAT32 partition named
`SPRUCEOS` in the free space of SD1. A PC sees it as an ordinary drive, so spruce can be
copied onto it.

## Which card runs

The base mounts the cards itself at every boot (`overlay/usr/magicx/bin/oakmoss-cards.sh`):

- `/mnt/SDCARD` is always the host, the card whose launcher runs.
- `/mnt/SDCARD_INT` is SD1's `SPRUCEOS` partition, mounted only while SD2 is in and hosting.
- `/mnt/SDCARD_EXT` is SD2, mounted only while SD1 hosts and SD2 is in.

Only a card with a frontend (`magicx/init.sh` or `.tmp_update/updater`) can host. Between two
such cards, the newer spruce wins: the version in `spruce/spruce` (x.y.z) first, then
`BUILD_UNIX` from `spruce/build` where a card has one. A card without either counts as oldest.
A tie goes to SD1. Older spruce versions are never turned away.

| cards | `/mnt/SDCARD` | other card | what runs |
|---|---|---|---|
| no SD2, no spruce on SD1 | SD1 | - | the no-frontend screen |
| no SD2, spruce on SD1 | SD1 | - | spruce from SD1 |
| spruce on SD1, SD2 without spruce | SD1 | SD2 at `SDCARD_EXT` | spruce from SD1 |
| no spruce on SD1, spruce on SD2 | SD2 | SD1 at `SDCARD_INT` | spruce from SD2 |
| spruce on both | the newer (SD1 on a tie) | the other one | the newer spruce |
| SD2 in, no spruce on either | SD2 | SD1 at `SDCARD_INT` | the no-frontend screen |

The outcome is in `/tmp/oakmoss-cards` (`HOST`, `SD1_DEV`, `SD1_ROOT`, `SD2_DEV`, `SD2_ROOT`) and
in `/mnt/UDISK/oakmoss-boot.log`.

SD2 can take a moment to appear after power-on. The base waits for it up to 10 s, or 3 s
when SD1 already has a frontend. The SDK's `fstab` entries that mounted SD2 at `/mnt/SDCARD`
are dropped at build time, so a card inserted later is never mounted on top of the host.

## No frontend

When no card has a launcher, the base looks for updates first, then:

- **with the charger in**, it shows "No frontend detected, charging" with the battery level,
  as in charge mode. The screen dims after 30 s, and any button wakes it. The power key checks
  the cards again; unplugging the charger switches the board off.
- **without a charger**, it shows "No frontend, power off in 10s", then switches off.

## Updates

`oakmoss-<board>-*.omupd` files are read from the root of `/mnt/SDCARD` and of whichever of
`SDCARD_INT` and `SDCARD_EXT` is mounted. This happens before any frontend or the no-frontend
screen, so a base update works even with no spruce on either card (`docs/updates.md`).

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

spruce owns these; the base does not change them.

- The MagicX platform files set `SD_DEV=/dev/mmcblk1p1`. When SD1 hosts, that is SD2 (or
  nothing), so anything spruce does with `SD_DEV` touches the wrong card: card repair and USB
  storage mode among them. spruce should take the host device from `/proc/mounts` (the device
  at `/mnt/SDCARD`), or from `SD1_DEV`/`SD2_DEV` and `HOST` in `/tmp/oakmoss-cards`.
- `SDCARD_INT` and `SDCARD_EXT` are new mount points. spruce does not use them yet.

## Still to prove on hardware

- A first boot on a card larger than the image: the partition added, formatted and mounted.
- After that first boot, the card in Windows and macOS: the partition visible, and the card
  still booting afterwards.
- A re-flash of a set-up card: the partition reattached and its files kept.
- The election with spruce on both cards, and the no-frontend screens with and without the
  charger.
