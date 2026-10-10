# Debug mode

oakMOSS can keep a record of every boot and every orderly shutdown, and its kernel leaves
progress marks that survive a hang or a reset. Together they show how a boot started, how the
one before it ended, and where a hang stopped. They are meant for problem reports.

## On and off

The switch is a file named `oakmoss-debug` at the root of SD1's `SPRUCEOS` partition, the drive
a PC shows for the system card once the card has booted in the device:

- **With the file:** debug mode is on.
- **Without it:** debug mode is off.
- **A card without that partition** keeps it on.

On the device, the partition is `/media/sdcard1` while SD2 hosts and `/mnt/SDCARD` while SD1
hosts (`docs/cards.md`), so `touch /media/sdcard1/oakmoss-debug` over SSH turns it on there.
The records follow at once. The kernel marks follow from the next boot, because U-Boot reads
the setting from the env (`oakmoss_debug`), where `runmagicx.sh` writes it at every boot.

## What it records

Each boot gets a record, `oakmoss-debug-records/boot-NNNN/`, on the card spruce runs from (the
last 30 are kept). v0.5.0-beta.1 wrote them to `oakmoss-debug/`, which is the switch file itself
when SD1 hosts, so it wrote no records there:

- **`boot.txt`:** how this boot started (the PMIC's power-on source and U-Boot's decision), how
  the boot before ended (its last kernel mark and whether it wrote a shutdown record), the kernel
  command line, the PMIC registers and the power supplies.
- **`dmesg.txt`:** the kernel log, about a minute after the boot.
- **`shutdown.txt`:** written at an orderly power-off or reboot: the PMIC and supplies, the
  mounts, the running programs (names only) and the last 300 lines of the kernel log.

A short copy of the last 6 records stays on SD1's data partition (`/mnt/UDISK/oakmoss-debug`)
for boots where no card is there. `Saves/spruce/oakmoss-debug.log` on the card gets a summary
line per boot; spruce's Bug report task packs and sends that file.

The records carry no serial number, no MAC address, and no line naming a network, a key or a
password: those are masked or dropped before anything is written.

## Kernel marks

The kernel writes each step it reaches to an RTC register, which survives a reset. The next
boot's U-Boot passes the last one on, and `boot.txt` names it under "How the boot before
ended": an ordinary reboot, a power-off, or the step a hang stopped at.

Every mark also goes into a 1 MB ring in RAM at `0x7f000000`, with a timestamp, the CPU and
whether it came from an interrupt. Dump it on the device and decode it on a PC with
`scripts/kmark-ring.py`; the command for the dump is at the top of that script. Read it while
the board is up: across a reset only the RTC mark is sure to survive.

The display has marks of its own (`0x71`): framebuffer open, blank and pan, every layer change,
the steps of U-Boot's display being taken over, skipped display updates, the IOMMU, brightness
and GPU power. The marks sent at every frame stop 120 s after boot. These marks found the
Zero 40's startup blank (`docs/sdk-mods.md` round 24).

## Kernel switches for debugging

The kernel command line comes from `setargs_mmc` in the U-Boot env. To add a switch, write a
file holding one line, `setargs_mmc <the current value> <the switch>`, and load it with
`fw_setenv -s <file>`; `fw_printenv setargs_mmc` prints the current value. Put the original
back the same way afterwards. An update does not touch the env.

- **`oakmoss.disp_smooth=0`:** the kernel powers the panel up itself instead of taking over
  the picture U-Boot left on it. The screen blinks once at kernel start.
