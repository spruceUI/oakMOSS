#!/bin/sh
# TrimUI panel and radio experiment (2026-10-26). Runs from the diagnostic hand-off once the card is
# up, only on the TrimUI A133P boards, only when installed (EXPERIMENTS="brick-panel-wifi").
#
# Why it exists: on the Brick's first DIAG boot the panel stayed lit from U-Boot's init (disp_reserve),
# so tree patch 160's table never ran. Closing and reopening the display (fb0 blank 4, then 0) makes
# the kernel run its own power-off and power-on, table included; the panel then shows ORANGE for 6 s
# (what the user reports). Then the XR829 by hand, as spruce would load it, and a scan. All to $LOG.
case "$(cat /usr/magicx/device 2>/dev/null)" in brick|brickpro|smartpro) ;; *) exit 0 ;; esac
LOG=${LOG:-/mnt/UDISK/spruce-base-boot.log}
{
    echo "--- panel + radio experiment (brick-panel-wifi)"
    n0=$(dmesg | grep -c 'trimui-brick panel')
    echo 4 > /sys/class/graphics/fb0/blank; echo "fb0 blank 4: rc=$?"; sleep 2
    echo 0 > /sys/class/graphics/fb0/blank; echo "fb0 blank 0: rc=$?"; sleep 1
    fbfill aa5500; sleep 6
    echo "panel lines before $n0, now $(dmesg | grep -c 'trimui-brick panel'):"; dmesg | grep -E 'trimui-brick panel|lcd_panel|DISP\]' | tail -8
    echo "sdio before: $(ls /sys/bus/sdio/devices/ 2>&1 | tr '\n' ' ')"; echo "net before: $(ls /sys/class/net | tr '\n' ' ')"
    modprobe xradio_wlan 2>&1; echo "modprobe xradio_wlan: rc=$?"; sleep 5
    echo "sdio after:"; for d in /sys/bus/sdio/devices/*; do [ -e "$d" ] && echo "$d vendor=$(cat "$d/vendor") device=$(cat "$d/device")"; done
    echo "net after: $(ls /sys/class/net | tr '\n' ' ')"; grep -E 'xradio' /proc/modules
    if [ -e /sys/class/net/wlan0 ]; then
        ip link set wlan0 up 2>&1 || ifconfig wlan0 up 2>&1; sleep 2
        if command -v iw >/dev/null; then s=$(iw dev wlan0 scan 2>&1 | sed -n 's/^[[:space:]]*SSID: //p')
        else s=$(iwlist wlan0 scan 2>&1 | sed -n 's/.*ESSID:"\(.*\)"/\1/p'); fi
        echo "scan: $(printf '%s\n' "$s" | grep -c .) networks: $(printf '%s\n' "$s" | head -6 | tr '\n' '|')"
    fi
    echo "dmesg tail:"; dmesg | tail -40 | grep -i -E 'xradio|xr829|sdc1|mmc1|sdio|wlan|firmware'
} >> "$LOG" 2>&1
