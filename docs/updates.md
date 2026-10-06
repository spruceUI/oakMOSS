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

U-Boot loads the kernel from `boot_partition` (`boot_normal`). While it starts, it sets
`mmc_root` from `root_partition` by exact partition name (`board/sunxi/board_helper.c`), so
the kernel's `root=` follows the env. The device tree is U-Boot's own, from the U-Boot
package: the boot image is header version 0 and carries none.

This U-Boot has no hush parser, so there is no `if`. `build.sh` puts `run ab_${ab_try}` at the
front of `boot_normal` and adds three scripts:

- `ab_` (no `ab_try`): a normal boot.
- `ab_1`: an update has just been installed. Sets `ab_try=2`, saves and boots it.
- `ab_2`: that slot never confirmed. Switches back to `ab_fallback_boot` and
  `ab_fallback_root`, sets `ab_reverted=1`, saves and resets. `root=` is worked out before
  `bootcmd`, which is why it resets rather than booting on.

`bootcmd` stays `run setargs_nand boot_normal`: U-Boot compares it word for word to tell a
normal boot from a charger boot (`board/sunxi/sunxi_bootargs.c`). `setargs_mmc` is not
touched either, because `check_user_data` parses it.

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

- The fallback copies: Allwinner's own writer puts boot0 at 256 and the package at 24576
  (`drivers/sunxi_flash/mmc/sdmmc.c`, `UBOOT_BACKUP_START_SECTOR_IN_SDMMC`), but boot0 is a
  prebuilt binary, so that it reads them is not visible in the SDK. Zero the main package on
  a test card and see it still boot.
- A whole update, and a fallback: install one, then break `boot_b` on a test card and see the
  board return to slot A with `ab_reverted=1`.
