oakMOSS debug image: what this folder holds

Each boot of a debug image writes a record here (boot-NNNN), and each orderly shutdown
or reboot adds shutdown.txt to it. To report a problem: make it happen, start the device
once more, wait a minute, then send this whole folder.

  boot.txt      how the boot started (power-on source, the charge-mode decision) and how
                the boot before it ended (its last kernel mark, shutdown recorded or not)
  dmesg.txt     the kernel log one minute after the boot
  shutdown.txt  the state when a shutdown began, with the end of the kernel log

No WiFi or account settings are collected; the serial number, MAC addresses and lines
naming networks are left out. The base card keeps the same records in
/mnt/UDISK/oakmoss-debug.
