# BatteryPlus: battery percent from the cell's voltage

The boards' AXP2202 fuel gauge is not a dependable source of the battery percent: it reads low until
it has learned a cycle of the cell (docs/hardware-notes.md), and spruce already replaces its reading
with a linear voltage estimate on the Zero 40. BatteryPlus, Mikhailzrick's battery daemon from Knulli
([knubat.components](https://github.com/Mikhailzrick/knubat.components), GPL-2.0), works the
percent out from the battery voltage instead: median-of-3 filtering, smoothing, separate charge and
discharge curves, a step-limited visible value, and a full voltage it learns from the cell. It
writes the result to `/tmp/battery.percent`.

## In the image

| what | where | |
|---|---|---|
| the daemon | `/usr/magicx/bin/batteryplus` | built by `build.sh` from the source pinned in `scripts/lib.sh` (`BATTERYPLUS_*`), unmodified, static, with the Arm GNU 13.3 toolchain |
| the service | `/etc/init.d/batteryplus` (S13, K50) | procd starts it once `/mnt/UDISK` is mounted and restarts it if it exits; stopping it (SIGTERM) saves its state before the K99 unmount |
| the configuration | `/etc/batteryplus/batteryplus.conf` | voltage mode; data in `/mnt/UDISK/batteryplus` |
| its hook directories | `/etc/batteryplus/{charging.d,discharging.d,state.d}` | empty; shipped so it never has to create them |

The learned data (the voltage map, the calibration and the restore state) lives in
`/mnt/UDISK/batteryplus`. It survives reboots; an update wipes `/mnt/UDISK`, and BatteryPlus
learns it again.

## For the launcher

- Read `/tmp/battery.percent` (an integer) where the gauge's `capacity` would be read, and fall
  back to the gauge when the file is missing: an image without BatteryPlus, or the daemon not
  running yet.
- After resuming from sleep, send it SIGUSR1 (`killall -USR1 batteryplus`). It then works the
  percent out again at once instead of reading the gap as a long discharge.
- `/mnt/UDISK/batteryplus/batteryplus.conf` overrides the settings (not `data_dir`): `mode=pmic`
  makes it pass the gauge's own percent through the same smoothing. `/etc/init.d/batteryplus stop`
  stops it until the next boot.
