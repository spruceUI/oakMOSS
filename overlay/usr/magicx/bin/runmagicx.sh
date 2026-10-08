#!/bin/sh
# oakMOSS hand-off, run by /etc/rc.local at the end of boot.
#
# Contract, as established by Shaun Inman's Moss-zero28 runmagicx.sh (the Zero 28
# hook, mirrored from what TrimUI and Miyoo do on their Tina builds): the user card at
# /mnt/SDCARD, run /mnt/SDCARD/magicx/init.sh if present, otherwise
# /mnt/SDCARD/.tmp_update/updater. Differences: the card can be SD1's own SPRUCEOS
# partition or SD2, whichever carries the newer spruce (oakmoss-cards.sh, docs/cards.md);
# with no launcher on either the board shows a no-frontend screen; and the device powers
# off if the hand-off returns without a shutdown of the launcher's own under way, so a
# crashed launcher never leaves the base OS idling behind the boot logo.
export PATH=/usr/magicx/bin:$PATH
export LD_LIBRARY_PATH=/usr/magicx/lib:$LD_LIBRARY_PATH

LOG=/mnt/UDISK/oakmoss-boot.log
log() { echo "$(cut -d' ' -f1 /proc/uptime) $*" >> "$LOG" 2>/dev/null; }
echo "=== boot $(date '+%Y-%m-%d %H:%M:%S') device=$(cat /usr/magicx/device 2>/dev/null) version=$(cat /usr/magicx/version 2>/dev/null) slot=$(fw_printenv -n root_partition 2>/dev/null)" >> "$LOG" 2>/dev/null

# Reaching userland confirms an updated slot (docs/updates.md); until then U-Boot
# falls back to the previous one on the next boot.
if [ -n "$(fw_printenv -n ab_try 2>/dev/null)" ]; then
    if printf 'ab_try\nab_fallback_boot\nab_fallback_root\n' > /tmp/ab-confirm &&
        fw_setenv -s /tmp/ab-confirm; then
        log "updated slot confirmed"
    else
        log "could not confirm the updated slot: the next boot goes back to $(fw_printenv -n ab_fallback_root 2>/dev/null)"
    fi
fi
# Logged once: the flag is cleared after it is reported.
if [ "$(fw_printenv -n ab_reverted 2>/dev/null)" = 1 ]; then
    log "the updated slot did not boot; U-Boot went back to this one"
    fw_setenv ab_reverted 2>/dev/null
fi

# Plugged in while off (androidboot.mode=charger from U-Boot, charge_mode = 1): a charging
# screen with the battery level until the power key, then the launcher (charge-screen.sh
# returns 0); it powers off only if the charger goes away first.
case " $(cat /proc/cmdline 2>/dev/null) " in
    *" androidboot.mode=charger "*) /usr/magicx/bin/charge-screen.sh || exit 0 ;;
esac

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

MAGICX_PATH=/mnt/SDCARD/magicx/init.sh
UPDATER_PATH=/mnt/SDCARD/.tmp_update/updater
while :; do
    # The cards: the host at /mnt/SDCARD, the other at /mnt/SDCARD_INT or /mnt/SDCARD_EXT.
    oakmoss-cards.sh mount
    HOST=none SD1_ROOT= SD2_ROOT=
    [ -f /tmp/oakmoss-cards ] && . /tmp/oakmoss-cards

    # Debug records and kernel marks stay on unless SD1's partition can be read and holds no
    # oakmoss-debug file. The env carries it to U-Boot, so kernel marks follow from the next boot.
    debug=1
    [ -n "$SD1_ROOT" ] && [ ! -e "$SD1_ROOT/oakmoss-debug" ] && debug=0
    if [ "$(fw_printenv -n oakmoss_debug 2>/dev/null)" != "$debug" ] && fw_setenv oakmoss_debug "$debug"; then
        log "oakmoss_debug set to $debug"
        [ "$debug" = 1 ] && [ ! -f /tmp/oakmoss-debug/n ] && /etc/init.d/oakmoss-debug start
    fi

    # Updates from both cards go to the installer, which picks the newest and shows its own frame.
    dev=$(cat /usr/magicx/device 2>/dev/null)
    pkgs=$(ls /mnt/SDCARD/oakmoss-"$dev"-*.omupd /mnt/SDCARD_INT/oakmoss-"$dev"-*.omupd \
        /mnt/SDCARD_EXT/oakmoss-"$dev"-*.omupd 2>/dev/null)
    if [ -n "$pkgs" ] && oakmoss-update.sh $pkgs; then
        sync
        reboot
        exit 0
    fi

    [ -f "$MAGICX_PATH" ] || [ -f "$UPDATER_PATH" ] && break

    # No launcher on any card: with the charger in, the charging screen until the power key
    # (then the cards again) or until the charger goes (it powers off); otherwise power off.
    if [ "$(cat /sys/class/power_supply/axp2202-usb/online 2>/dev/null)" = 1 ]; then
        log "no frontend on any card (host $HOST); charging screen"
        /usr/magicx/bin/charge-screen.sh nofrontend || exit 0
        continue
    fi
    log "no frontend on any card (host $HOST) and no charger; powering off in 10 s"
    /usr/magicx/bin/charge-screen.sh nofrontend-off
    sleep 10
    sync
    poweroff
    exit 0
done

if [ -f "$MAGICX_PATH" ]; then
    log "running $MAGICX_PATH"
    "$MAGICX_PATH"
else
    log "running $UPDATER_PATH"
    "$UPDATER_PATH"
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
