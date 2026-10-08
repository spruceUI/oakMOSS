oakMOSS debug records: what this folder holds

Each boot writes a record here (boot-NNNN), and each orderly shutdown or reboot adds
shutdown.txt to it. To report a problem: make it happen, start the device once more,
wait a minute, then send this whole folder. The records are kept while a file named
oakmoss-debug is at the root of SD1's spruce partition, and always on cards without one.

  boot.txt      how the boot started (power-on source, the charge-mode decision) and how
                the boot before it ended (its last kernel mark, shutdown recorded or not)
  dmesg.txt     the kernel log one minute after the boot
  shutdown.txt  the state when a shutdown began, with the end of the kernel log

spruce's Bug report task (Tasks menu) also sends a summary of these records, from
Saves/spruce/oakmoss-debug.log, so a report sent that way already carries them.

No WiFi or account settings are collected; the serial number, MAC addresses and lines
naming networks are left out. The base card keeps the same records in
/mnt/UDISK/oakmoss-debug.
