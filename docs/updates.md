# Updates

From the first image with two slots on, a board updates itself from a file on the launcher
card. Cards flashed before that have one slot and need one last full flash.

## The card

| partition | |
|---|---|
| `boot`, `rootfs` | slot A: kernel image and root filesystem (512 MiB) |
| `boot_b`, `rootfs_b` | slot B, empty on a new card |
| `bootloader` | boot-resource: logo and charge pictures |
| `env`, `env-redund` | U-Boot environment, written by `fw_setenv` |

boot0 sits at sector 16 with a copy at 256, the U-Boot package at sector 32800 with a copy
at 24576 (`scripts/add-boot-backups.py`). `rootfs_data` and `UDISK` are shared by both
slots.

## Which slot boots

U-Boot boots `boot_partition` with `root_partition` as root. `build.sh` adds `ab_check` to
the env and runs it first in `boot_normal`:

- `ab_try=1`: an update has just been installed. U-Boot sets `ab_try=2` and boots it.
- `ab_try=2`: that slot never confirmed. U-Boot switches back to `ab_fallback_boot` and
  `ab_fallback_root`, sets `ab_reverted=1` and resets.
- no `ab_try`: a normal boot.

`runmagicx.sh` confirms the slot as soon as userland runs, before the charge screen or the
launcher, by clearing `ab_try` and the fallback.

## The update file

`build.sh image` writes `oakmoss-<board>-<version>.omupd` next to the image
(`scripts/make-update.py`). It holds the kernel slot, the squashfs, boot0, the U-Boot package
and boot-resource, each with the sha256 of what goes on the card. The first 4 KiB are a text
manifest (`FORMAT=omupd1`, `BOARD`, `VERSION`, `PARTS` and per part `_OFFSET`, `_LENGTH`,
`_GZIP`, `_SIZE`, `_SHA256`). Each part follows at a 4 KiB-aligned offset. `/usr/magicx/version`
in the image carries the same version.

## Installing

The launcher downloads the file for its board to the root of the card and reboots. On the next
boot `runmagicx.sh` finds `/mnt/SDCARD/oakmoss-<board>-*.omupd`, shows the loading picture and
runs `oakmoss-update.sh`, which:

1. checks the board and every part's sha256;
2. writes the kernel and the squashfs into the slot that is not running, and reads them back;
3. writes boot0, the U-Boot package and boot-resource when they differ from the card's, copy
   first and main last, each read back;
4. sets `boot_partition`, `root_partition`, the fallback, `ab_try=1` and
   `parts_clean=rootfs_data` in one `fw_setenv -s` write. Tina's preinit wipes the overlay
   on the next boot, so no file from the old slot hides one in the new.

On success the file is deleted and the board reboots. On any failure the file is renamed
`.failed` and the board boots the launcher as usual. Everything is logged to
`/mnt/UDISK/oakmoss-boot.log`.

## Releasing

Upload the `.omupd` of each board with the images, and list it in `SHA256SUMS`.

## Still to prove on hardware

- `saveenv` and `reset` work from `ab_check` (`CONFIG_CMD_SAVEENV`, the hush parser in
  `sun50iw10p1_tina_defconfig`). Without them the board still boots the new slot, but never
  falls back.
- U-Boot rewrites `root=` from `root_partition` for `rootfs_b` as it does for `rootfs`.
- The boot ROM falls back to boot0 at sector 256, and boot0 to the package at 24576, when the
  main copy is damaged. Without that, the copies change nothing and an interrupted
  bootloader write still needs a reflash.
- A fallback after a slot that does not boot: break `boot_b` on a test card and see the board
  return to slot A with `ab_reverted=1`.
