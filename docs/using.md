# Flashing and using an image

## Before you flash

Flashing replaces the firmware the board starts from. Writing an image made for another
board, or interrupting the write, leaves a device that does not start. **Make a raw backup
of the board's stock internal card (SD1) first and keep it:** for these boards it is the
only way back.

- Write the image **raw to the whole card**: `dd`, Rufus in DD mode, Etcher or Raspberry Pi
  Imager.
- **Never open a written card in a partition tool.** A partition-table "repair" zeroes
  boot0, and the card stops booting.
- **On Windows**, the system rewrites the partition table of an XU20 or Zero 40 card every
  time it detects the card again (`docs/hardware-notes.md`). Write the card with Raspberry
  Pi Imager, verification on. When Imager ejects it, take it straight to the device, and
  do not plug it back into the PC before it has booted once. `scripts/verify-card.ps1`
  compares a written card with its image without going through Windows storage
  management.

## Flashing

1. Write `oakmoss-<board>-<stamp>-sd1.img` to the internal microSD (SD1), the whole card.
   It goes back into the slot the board's own system card came from.
2. Put a launcher card in the second slot (SD2): a **FAT32** card with
   [spruceOS](https://github.com/spruceUI/spruceOS) for the MagicX boards, or any card
   with `magicx/init.sh`. spruce tells the boards apart by `/usr/magicx/device`. exFAT does
   not work: kernel 4.9 has no exFAT driver.
3. Power on.

## What the board does

- **Boot:** oakMOSS mounts the second card at `/mnt/SDCARD` and hands off to its launcher
  (`.tmp_update/updater`, or `magicx/init.sh`). With no card, or when the launcher exits,
  the board powers off (`overlay/usr/magicx/bin/runmagicx.sh`).
- **Plugged in while off:** the board comes up in charge mode. U-Boot shows a charging
  picture, then a screen with the battery level. The screen goes dark after 30 seconds, and
  any button brings it back. Power while it is lit starts the launcher. Unplugging the
  charger switches the board off.
- **Battery too low:** plugged in, the board charges up to a safe level before it goes on;
  without a charger it shows a low-battery picture and switches off.
- **Sleep:** spruceOS puts the board into real suspend-to-RAM on a short press of the
  power key, and the power key wakes it. spruce's own idle timer switches a sleeping board
  off after a while.
