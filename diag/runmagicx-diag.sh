#!/bin/sh
# DIAGNOSTIC hand-off: same contract as the stock runmagicx.sh
# (magicx/init.sh, else .tmp_update/updater, else poweroff) with three additions:
#   - the screen is painted a colour at each stage, so progress is visible with no console
#       green  = rc.local reached          blue   = /mnt/SDCARD mounted
#       red    = no card after 30 s (then poweroff)
#       yellow = the hand-off returned (spruce exited); details in the log, then poweroff
#   - the wait for the card is 30 s, not 3 s
#   - a boot log is written to /mnt/UDISK/spruce-base-boot.log (SD1, persistent)
#     and copied to /mnt/SDCARD/Saves/spruce/base-boot.log once the card is up
export PATH=/usr/magicx/bin:$PATH
export LD_LIBRARY_PATH=/usr/magicx/lib:$LD_LIBRARY_PATH
LOG=/mnt/UDISK/spruce-base-boot.log
mkdir -p /mnt/UDISK 2>/dev/null
log() { echo "$(cut -d' ' -f1 /proc/uptime) $*" >> "$LOG" 2>/dev/null; }
snapshot() {
    { echo "--- $1"; echo "mounts:"; cat /proc/mounts; echo "partitions:"; cat /proc/partitions;
      echo "mmc:"; ls -l /dev/mmcblk* 2>&1; echo "power_supply:"; for p in /sys/class/power_supply/*; do echo "[$p]"; cat "$p/uevent" 2>&1; done;
      echo "inputs:"; cat /proc/bus/input/devices 2>&1;
      for e in /sys/class/input/event*; do echo "[$e] name=$(cat $e/device/name 2>/dev/null) key=$(cat $e/device/capabilities/key 2>/dev/null) abs=$(cat $e/device/capabilities/abs 2>/dev/null)"; done;
      echo "sdio devices:"; for d in /sys/bus/sdio/devices/*; do [ -e "$d" ] && echo "$d vendor=$(cat $d/vendor 2>/dev/null) device=$(cat $d/device 2>/dev/null) class=$(cat $d/class 2>/dev/null)"; done;
      echo "modules:"; cat /proc/modules 2>&1; echo "net:"; ls /sys/class/net 2>&1; cat /proc/net/wireless 2>&1; ip link 2>&1 || ifconfig -a 2>&1;
      echo "rfkill:"; for r in /sys/class/rfkill/*; do [ -e "$r" ] && echo "$r $(cat $r/name 2>/dev/null) state=$(cat $r/state 2>/dev/null)"; done;
      echo "dmesg (full):"; dmesg; } >> "$LOG" 2>&1
}
echo "=== boot $(date '+%Y-%m-%d %H:%M:%S') device=$(cat /usr/magicx/device 2>/dev/null)" >> "$LOG" 2>/dev/null
fbfill 004400 >> "$LOG" 2>&1
log "rc.local reached"
COUNT=0
while ! grep -q SDCARD /proc/mounts && [ $COUNT -lt 60 ]; do
    sleep 0.5; COUNT=$((COUNT + 1))
    if [ $COUNT -eq 6 ]; then
        log "card not mounted after 3 s: partitions / block info / block mount"; snapshot "3s"
        /sbin/block info >> "$LOG" 2>&1
        /sbin/block mount >> "$LOG" 2>&1
    fi
    if [ $COUNT -eq 20 ]; then
        # 10 s: mount the first FAT partition we can find, whatever it is called.
        for dev in $(/sbin/block info 2>/dev/null | sed -n 's|^\(/dev/[a-z0-9]*\):.*TYPE="\(vfat\|msdos\|fat\)".*|\1|p'); do
            log "10 s: trying $dev at /mnt/SDCARD"; mkdir -p /mnt/SDCARD
            mount -t vfat -o rw,noatime,fmask=0000,dmask=0000,iocharset=utf8 "$dev" /mnt/SDCARD >> "$LOG" 2>&1 && { log "mounted $dev"; break; }
        done
    fi
done
if ! grep -q SDCARD /proc/mounts; then
    log "no card after 30 s"; snapshot "no-card"
    fbfill 660000 >> "$LOG" 2>&1; sleep 5; sync; poweroff; exit 0
fi
log "card mounted"; snapshot "card-mounted"
fbfill 000066 >> "$LOG" 2>&1
mkdir -p /mnt/SDCARD/Saves/spruce 2>/dev/null
cp "$LOG" /mnt/SDCARD/Saves/spruce/base-boot.log 2>/dev/null; sync /mnt/SDCARD/Saves/spruce/base-boot.log 2>/dev/null
# Experiments: opt-in scripts installed under /usr/magicx/diag/experiments by
# the image maker (EXPERIMENTS="..." to make-diag-image.sh). Each runs once the
# card is up and blue is on the panel, with $LOG exported, and decides for
# itself which board it is for. A normal diagnostic image carries none. Each
# is fenced by this BusyBox's timeout (`-t SECS`), and the log is copied to
# the user card again afterwards: an experiment that wedges the GPU must not
# take the evidence with it (2026-09-16, the first EGL run did exactly that).
if [ -d /usr/magicx/diag/experiments ]; then
    for x in /usr/magicx/diag/experiments/*.sh; do
        [ -f "$x" ] || continue
        log "experiment: $(basename "$x")"; LOG="$LOG" timeout -t 90 sh "$x"; log "experiment rc=$?"
        cp "$LOG" /mnt/SDCARD/Saves/spruce/base-boot.log 2>/dev/null; sync /mnt/SDCARD/Saves/spruce/base-boot.log 2>/dev/null
    done
fi
MAGICX_PATH=/mnt/SDCARD/magicx/init.sh
UPDATER_PATH=/mnt/SDCARD/.tmp_update/updater
if [ -f "$MAGICX_PATH" ]; then log "running $MAGICX_PATH"; "$MAGICX_PATH" >> /mnt/SDCARD/Saves/spruce/base-handoff.log 2>&1; rc=$?
elif [ -f "$UPDATER_PATH" ]; then log "running $UPDATER_PATH"; "$UPDATER_PATH" >> /mnt/SDCARD/Saves/spruce/base-handoff.log 2>&1; rc=$?
else log "nothing to run on the card"; rc=127; fi
log "hand-off returned rc=$rc"; snapshot "after-handoff"
cp "$LOG" /mnt/SDCARD/Saves/spruce/base-boot.log 2>/dev/null; sync
fbfill 666600 >> "$LOG" 2>&1; sleep 10; sync; poweroff
