#!/bin/sh
# Zero 40 radio experiment (2026-09-16). Runs from the diagnostic hand-off once
# the user card is mounted, only on a Zero 40, and only when installed: the
# diagnostic image maker puts it at /usr/magicx/diag/experiments/ when asked
# (EXPERIMENTS="zero40-radio"). It is not part of a normal boot.
#
# Why it exists: the Zero 40's device tree gives the WiFi glue no chip-enable
# GPIO (chip_en = true) where the Zero 28's drives PL7, and the Realtek driver's
# SDIO rescans on sdc1 fail (cmd 5 RE). Drive the candidate pins high from
# userland, reload the driver, and record what appears on the bus. Everything
# lands in the boot log ($LOG, set by the hand-off).
[ "$(cat /usr/magicx/device 2>/dev/null)" = "zero40" ] || exit 0
LOG=${LOG:-/mnt/UDISK/spruce-base-boot.log}
{
    echo "--- radio experiment (zero40-radio)"
    echo "gpiochips:"; for c in /sys/class/gpio/gpiochip*; do echo "$c base=$(cat $c/base) ngpio=$(cat $c/ngpio) label=$(cat $c/label)"; done
    echo "sdio before:"; ls /sys/bus/sdio/devices/ 2>&1; echo "net before: $(ls /sys/class/net | tr '\n' ' ')"
    for g in 359 357; do echo $g > /sys/class/gpio/export 2>&1; echo out > /sys/class/gpio/gpio$g/direction 2>&1; echo 1 > /sys/class/gpio/gpio$g/value 2>&1; echo "gpio$g=$(cat /sys/class/gpio/gpio$g/value 2>&1)"; done
    rmmod 8189es 2>&1; sleep 1; modprobe 8189es 2>&1; sleep 5
    echo "sdio after:"; for d in /sys/bus/sdio/devices/*; do [ -e "$d" ] && echo "$d vendor=$(cat $d/vendor) device=$(cat $d/device)"; done; echo "net after: $(ls /sys/class/net | tr '\n' ' ')"
    echo "dmesg tail:"; dmesg | tail -40 | grep -i -E 'RTW|sdc1|mmc2|sdio|wlan'
} >> "$LOG" 2>&1
