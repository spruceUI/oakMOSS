#!/bin/sh
# oakMOSS charge screen, run by runmagicx.sh when U-Boot booted for the charger
# (androidboot.mode=charger: plugged in while off, charge_mode = 1 in the board's
# sys_config.fex). The muOS model (script/device/charge.sh + muxcharge on the H700
# boards): stay up at the lowest clock showing a charging screen with the battery level.
# The panel goes dark after BLANK_AFTER seconds; any press (pad or power) while it is dark
# only wakes it, and a power press while it is lit starts the launcher (returns 0). Powers
# the board off if the charger goes away first. It never powers
# off with the charger attached: the PMIC powers these boards straight back on while
# USB is present (a Zero 28 looped that way, 2026-09-26).
#
# Frames are pre-rendered by scripts/make-charge-screens.py in the framebuffer's own
# format (the board's page size, B G R A bytes), written to both pages and flipped to; the kernel's
# framebuffer rotation turns them for the panel on the flip.

MODE=$1                 # "frame": draw once and exit (see below)
FRAMES=/usr/magicx/share/charge
FB=/dev/fb0
FBSYS=/sys/class/graphics/fb0
BAT=/sys/class/power_supply/axp2202-battery/capacity
USB=/sys/class/power_supply/axp2202-usb/online
GOV=/sys/devices/system/cpu/cpufreq/policy0/scaling_governor
LOG=/mnt/UDISK/oakmoss-boot.log
BLANK_AFTER=30          # seconds after the last press before the panel goes dark

log() { echo "$(cut -d' ' -f1 /proc/uptime) charge-screen: $*" >> "$LOG" 2>/dev/null; }

# Display-state trace, only while /mnt/UDISK/charge-debug exists: the fb's blank and pan state,
# the backlight and the layer the display engine shows, one line per call.
DBG=""; [ -e /mnt/UDISK/charge-debug ] && DBG=/mnt/UDISK/charge-debug.log
dbg() {
    [ -n "$DBG" ] || return 0
    _sys=$(cat /sys/class/disp/disp/attr/sys 2>/dev/null | tr -s ' \t' ' ' |
        sed -n 's/.*\(backlight([0-9]*)\).*/\1/p; s/.*BUF *\(enable\|disable\).*addr\[\([^,]*\),.*/\1 addr=\2/p' | tr '\n' ' ')
    echo "$(cut -d' ' -f1 /proc/uptime) $* blank=$(cat "$FBSYS/blank" 2>/dev/null) pan=$(cat "$FBSYS/pan" 2>/dev/null) $_sys" >> "$DBG" 2>/dev/null
}

[ -f "$FRAMES/loading.rgba.gz" ] || exit 0

# Page geometry from the framebuffer: two pages of W x H (virtual_size is W,2H), rows of stride bytes.
set -- $(tr ',' ' ' < "$FBSYS/virtual_size" 2>/dev/null)
H=$(( ${2:-960} / 2 ))
STRIDE=$(cat "$FBSYS/stride" 2>/dev/null); STRIDE=${STRIDE:-2560}

show() {
    zcat "$FRAMES/$1.rgba.gz" > /tmp/charge-frame 2>/dev/null || return 1
    dd if=/tmp/charge-frame of="$FB" bs="$STRIDE" 2>/dev/null
    dd if=/tmp/charge-frame of="$FB" bs="$STRIDE" seek="$H" 2>/dev/null
    echo "0,$H" > "$FBSYS/pan" 2>/dev/null
    echo 0,0 > "$FBSYS/pan" 2>/dev/null
    rm -f /tmp/charge-frame
    dbg "show $1"
}

level_frame() {
    c=$(cat "$BAT" 2>/dev/null)
    case "$c" in ''|*[!0-9]*) c=0 ;; esac
    c=$(( (c + 2) / 5 * 5 )); [ "$c" -gt 100 ] && c=100
    printf 'level-%03d' "$c"
}

# `charge-screen.sh frame`: draw the level frame once and exit. /etc/init.d/chargeframe runs
# it early in a charger boot: the Zero 40 scans its framebuffer out directly, and the GPU
# driver's fbdev setup (pvrsrvkm, ~4.2 s) blanked U-Boot's picture there until this script
# ran from rc.local ~2.6 s later (2026-09-28). The rotated boards show a G2D copy instead.
if [ "$MODE" = frame ]; then
    # /mnt/UDISK is not mounted this early; the main run copies this into the boot log.
    DBG=/tmp/chargeframe.log
    dbg "early frame start"
    # Unblank too: the GPU driver's fbdev setup blanks the display, and the frame stays
    # hidden until an unblank - drawing alone left the Zero 40 dark until the main run's.
    echo 0 > "$FBSYS/blank" 2>/dev/null
    show "$(level_frame)"
    exit 0
fi

# `charge-screen.sh updating`: "Updating, do not power off" while oakmoss-update.sh writes the card.
if [ "$MODE" = updating ]; then
    echo 0 > "$FBSYS/blank" 2>/dev/null
    show updating || show loading
    exit 0
fi

# The picture first, before waiting for the input nodes: nothing else is on the panel until
# a frame is up (on the Zero 40 /etc/init.d/chargeframe has usually put one up already).
dbg "start"
gov=$(cat "$GOV" 2>/dev/null)
echo powersave > "$GOV" 2>/dev/null
echo 0 > "$FBSYS/blank" 2>/dev/null
frame=$(level_frame); show "$frame"

# The pad is a module (simplepad) and registers late - 5.9 s into a Zero 28 boot, with
# this script already up at 6.7 s - so wait up to 10 s for both nodes.
pek=""; pad=""; n=0
while :; do
    for d in /sys/class/input/event*; do
        case "$(cat "$d/device/name" 2>/dev/null)" in
            axp2202-pek) pek=/dev/input/${d##*/} ;;
            magicx-input) pad=/dev/input/${d##*/} ;;
        esac
    done
    [ -n "$pek" ] && [ -n "$pad" ] && break
    [ "$n" -ge 40 ] && break
    sleep 0.25; n=$((n + 1))
done

[ -f /tmp/chargeframe.log ] && while read -r _l; do log "early: $_l"; done < /tmp/chargeframe.log
log "charging at $(cat "$BAT" 2>/dev/null)% (governor $gov -> powersave), keys pek=${pek:-none} pad=${pad:-none}"

# Every event from the power key and the pad, read continuously (a reader per node appends
# the raw 24-byte input_events to a file), so a press is told from its release: a release
# right after a wake must not count as the confirming press.
PEK_LOG=/tmp/charge-pek; PAD_LOG=/tmp/charge-pad
: > "$PEK_LOG"; : > "$PAD_LOG"
[ -n "$pek" ] && { cat "$pek" >> "$PEK_LOG" & pekpid=$!; }
[ -n "$pad" ] && { cat "$pad" >> "$PAD_LOG" & padpid=$!; }
pek_off=0; pad_off=0

# key_down FILE OFFSET: consume the whole events after OFFSET; true if one was a key going
# down (type EV_KEY = 1, value 1). Sets NEXT to the new offset. The base's BusyBox od has no
# -A/-t (it read nothing, and no press ever counted: Zero 28, 2026-09-26), so xxd prints each
# 24-byte event as 48 hex digits: type at digits 33-36, value at 41-48, little-endian.
key_down() {
    _sz=$(wc -c < "$1"); _len=$(( (_sz - $2) / 24 * 24 ))
    NEXT=$(( $2 + _len ))
    [ "$_len" -gt 0 ] || return 1
    xxd -p -c 24 -s "$2" -l "$_len" "$1" |
        awk 'length($0) == 48 && substr($0, 33, 4) == "0100" && substr($0, 41, 8) == "01000000" { d = 1 } END { exit !d }'
}

stop_readers() {
    [ -n "$pekpid" ] && kill "$pekpid" 2>/dev/null
    [ -n "$padpid" ] && kill "$padpid" 2>/dev/null
    rm -f "$PEK_LOG" "$PAD_LOG"
}

# 4 ticks a second. The panel stays lit for BLANK_AFTER seconds after the last press; while
# it is dark any press only wakes it, and while it is lit the power key starts the launcher.
# The charger counts as gone only after 3 s offline: a flat cell on a fresh charger read
# offline once, 20 s in, and the board powered off and came back up into a normal boot
# (Zero 28, 2026-09-27).
TICKS=$((BLANK_AFTER * 4)); lit=$TICKS; offline=0; tick=0
while :; do
    tick=$((tick + 1))
    if [ "$tick" -le 80 ] || [ $((tick % 20)) -eq 0 ]; then dbg "tick $tick lit=$lit"; fi
    if [ "$(cat "$USB" 2>/dev/null)" = 0 ]; then offline=$((offline + 1)); else offline=0; fi
    if [ "$offline" -ge 12 ]; then
        log "charger removed at $(cat "$BAT" 2>/dev/null)%; powering off"
        stop_readers
        sync
        poweroff
        exit 1
    fi
    power=1; other=1
    key_down "$PEK_LOG" "$pek_off" && power=0; pek_off=$NEXT
    key_down "$PAD_LOG" "$pad_off" && other=0; pad_off=$NEXT
    if [ "$power" = 0 ] && [ "$lit" -gt 0 ]; then
        break
    fi
    if [ "$power" = 0 ] || [ "$other" = 0 ]; then
        if [ "$lit" -eq 0 ]; then
            echo 0 > "$FBSYS/blank" 2>/dev/null
            frame=$(level_frame); show "$frame"
            log "woken at $(cat "$BAT" 2>/dev/null)%"
        fi
        lit=$TICKS
    fi
    if [ "$lit" -gt 0 ]; then
        new=$(level_frame)
        [ "$new" != "$frame" ] && { frame=$new; show "$frame"; }
        lit=$((lit - 1))
        [ "$lit" -eq 0 ] && echo 4 > "$FBSYS/blank" 2>/dev/null
    fi
    sleep 0.25
done

stop_readers
log "power key at $(cat "$BAT" 2>/dev/null)%; starting the launcher"
echo 0 > "$FBSYS/blank" 2>/dev/null
show loading
[ -n "$gov" ] && echo "$gov" > "$GOV" 2>/dev/null
exit 0
