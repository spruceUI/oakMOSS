#!/bin/sh
# oakMOSS hand-off, run by /etc/rc.local at the end of boot.
#
# Contract, as established by Shaun Inman's Moss-zero28 runmagicx.sh (the Zero 28
# hook, mirrored from what TrimUI and Miyoo do on their Tina builds): wait for the
# user card at /mnt/SDCARD, run /mnt/SDCARD/magicx/init.sh if present, otherwise
# /mnt/SDCARD/.tmp_update/updater, and power off when neither exists. Two
# differences: the wait is 10 s instead of 3 s (some cards enumerate late), and
# the device powers off if the hand-off returns without a shutdown of the
# launcher's own under way, so a crashed launcher never leaves the base OS
# idling behind the boot logo.
export PATH=/usr/magicx/bin:$PATH
export LD_LIBRARY_PATH=/usr/magicx/lib:$LD_LIBRARY_PATH

LOG=/mnt/UDISK/oakmoss-boot.log
log() { echo "$(cut -d' ' -f1 /proc/uptime) $*" >> "$LOG" 2>/dev/null; }
echo "=== boot $(date '+%Y-%m-%d %H:%M:%S') device=$(cat /usr/magicx/device 2>/dev/null)" >> "$LOG" 2>/dev/null

# A stable WiFi MAC for the XR829 (Zero 40). Its driver keeps the address in
# /data/misc/wifi/xr_wifi.conf - an Android path this base did not have - and drew a
# random one on every load when it could not save it there: a new MAC, DHCP lease and
# IP on every boot (2026-09-18). The file holds an address derived from the SoC serial,
# so the board keeps it across reboots and reflashes. It must pass the driver's own
# check (MACADDR_VAILID: unicast and NOT locally administered), or the driver replaces
# it with a random one: so the driver's default vendor prefix DC:44:6D plus three bytes
# of the serial's md5. The Realtek radios (Zero 28, XU20) read theirs from efuse.
wifi_mac_file=/data/misc/wifi/xr_wifi.conf
if [ "$(cat /usr/magicx/device 2>/dev/null)" = zero40 ]; then
    serial=$(sed -n 's/^sunxi_serial *: *//p' /sys/class/sunxi_info/sys_info 2>/dev/null)
    if [ -n "$serial" ]; then
        h=$(printf '%s' "$serial" | md5sum | cut -c1-6)
        mac=$(printf 'dc:44:6d:%s:%s:%s' $(echo "$h" | sed 's/../& /g'))
        if [ "$(cat "$wifi_mac_file" 2>/dev/null)" != "$mac" ]; then
            mkdir -p "${wifi_mac_file%/*}" && printf '%s' "$mac" > "$wifi_mac_file" &&
                log "wifi MAC for the XR829: $mac (from the SoC serial)"
        fi
    fi
fi

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
rc=$?
# The launcher also returns when it is itself rebooting or powering off: spruce's
# shutdown closes its own session (SIGTERM, rc=143), then unmounts the card and calls
# reboot or poweroff from a stage it staged in /tmp. Powering off here at once won that
# race and turned every spruce reboot into a power-off (2026-09-18). While the
# launcher's shutdown is staged, leave the transition to it (init kills this script
# when it runs); otherwise give any transition already requested a moment first.
if [ -e /tmp/save_poweroff_stage2.sh ] || [ -e /tmp/shutting_down.lock ]; then
    log "hand-off returned rc=$rc during the launcher's own shutdown; leaving the power transition to it"
    sleep 600
else
    log "hand-off returned rc=$rc; powering off in 10 s unless a shutdown is already under way"
    sleep 10
fi
log "no power transition came; powering off"
sync
poweroff
