#!/bin/sh
# oakMOSS hand-off, run by /etc/rc.local at the end of boot.
#
# Contract, as established by Shaun Inman's Moss-zero28 runmagicx.sh (the Zero 28
# hook, mirrored from what TrimUI and Miyoo do on their Tina builds): wait for the
# user card at /mnt/SDCARD, run /mnt/SDCARD/magicx/init.sh if present, otherwise
# /mnt/SDCARD/.tmp_update/updater, and power off when neither exists. Two
# differences: the wait is 10 s instead of 3 s (some cards enumerate late), and
# the device powers off if the hand-off ever returns, so a crashed launcher
# never leaves the base OS idling behind the boot logo.
export PATH=/usr/magicx/bin:$PATH
export LD_LIBRARY_PATH=/usr/magicx/lib:$LD_LIBRARY_PATH

LOG=/mnt/UDISK/oakmoss-boot.log
log() { echo "$(cut -d' ' -f1 /proc/uptime) $*" >> "$LOG" 2>/dev/null; }
echo "=== boot $(date '+%Y-%m-%d %H:%M:%S') device=$(cat /usr/magicx/device 2>/dev/null)" >> "$LOG" 2>/dev/null

n=0
while ! grep -q ' /mnt/SDCARD ' /proc/mounts; do
    [ "$n" -ge 20 ] && break
    sleep 0.5
    n=$((n + 1))
done

MAGICX_PATH=/mnt/SDCARD/magicx/init.sh
UPDATER_PATH=/mnt/SDCARD/.tmp_update/updater
if [ -f "$MAGICX_PATH" ]; then
    log "running $MAGICX_PATH"
    "$MAGICX_PATH"
elif [ -f "$UPDATER_PATH" ]; then
    log "running $UPDATER_PATH"
    "$UPDATER_PATH"
else
    log "no card or nothing to run after ${n} x 0.5 s; powering off"
    sync
    poweroff
    exit 0
fi
log "hand-off returned rc=$?; powering off"
sync
poweroff
