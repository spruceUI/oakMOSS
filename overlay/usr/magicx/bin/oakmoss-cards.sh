#!/bin/sh
# The spruce cards (docs/cards.md). /mnt/SDCARD is the host: the card whose spruce is newer,
# SD1 on a tie; with no frontend on either, SD2 if it is in. The other card is mounted at
# /mnt/SDCARD_INT (SD1's SPRUCEOS partition, when SD2 hosts) or /mnt/SDCARD_EXT (SD2, when SD1
# hosts). The outcome goes to /tmp/oakmoss-cards: HOST (sd1, sd2, none), SD1_DEV, SD1_ROOT,
# SD2_DEV, SD2_ROOT.
#
#   oakmoss-cards.sh mount     prepare SD1's partition, mount the cards, elect (runmagicx.sh)
#   oakmoss-cards.sh umount    take them down again, before a re-check
#
# MNT, SD1_DISK and SD2_GLOB exist for testing with loop devices.

export PATH=/usr/magicx/bin:$PATH
STATE=/tmp/oakmoss-cards
T=/tmp/oakmoss-cards.d
LOG=${LOG:-/mnt/UDISK/oakmoss-boot.log}
MNT=${MNT:-/mnt}
SD2_GLOB=${SD2_GLOB:-/sys/block/mmcblk*}
log() { echo "$(cut -d' ' -f1 /proc/uptime) cards: $*" >> "$LOG" 2>/dev/null; }

frontend() { [ -f "$1/magicx/init.sh" ] || [ -f "$1/.tmp_update/updater" ]; }

# x.y.z from spruce/spruce, then BUILD_UNIX from spruce/build; a card without them counts as oldest.
version() {
    v=$(head -n 1 "$1/spruce/spruce" 2>/dev/null | tr -d '\r ')
    b=$(sed -n 's/^BUILD_UNIX=//p' "$1/spruce/build" 2>/dev/null | head -n 1 | tr -d '\r"')
    case $b in ''|*[!0-9]*) b=0 ;; esac
    echo "${v:-0.0.0} $b"
}
newer() {	# newer A B: the spruce at A is newer than the one at B
    { version "$1"; version "$2"; } | awk 'NR == 1 { split($1, a, "."); ab = $2 } NR == 2 { split($1, b, "."); bb = $2 }
        END { for (i = 1; i <= 3; i++) if (a[i] + 0 != b[i] + 0) exit !(a[i] + 0 > b[i] + 0); exit !(ab + 0 > bb + 0) }'
}

mount_card() {	# mount_card <device> <dir>: as the SDK's fstab mounted SD2 (rw,async), NTFS through ntfs-3g
    mkdir -p "$2"
    mount -o rw,async "$1" "$2" 2>/dev/null && return 0
    [ -x /usr/bin/ntfs-3g ] && /usr/bin/ntfs-3g "$1" "$2" -o rw,noatime,nodiratime,nosuid,nodev 2>/dev/null
}

magic() {	# the filesystem a partition starts with: fat32, exfat, ntfs, none, or unread
    dd if="$1" of="$T/bs" bs=512 count=1 2>/dev/null
    [ "$(wc -c < "$T/bs" 2>/dev/null)" = 512 ] || { echo unread; return; }
    [ "$(dd if="$T/bs" bs=1 skip=82 count=8 2>/dev/null)" = "FAT32   " ] && { echo fat32; return; }
    case $(dd if="$T/bs" bs=1 skip=3 count=8 2>/dev/null) in
        "EXFAT   ") echo exfat ;; "NTFS    ") echo ntfs ;; *) echo none ;;
    esac
}

SD1_DISK=${SD1_DISK:-$(readlink -f /dev/by-name/boot 2>/dev/null | sed -n 's/p[0-9]*$//p')}
SD1_DISK=${SD1_DISK:-/dev/mmcblk0}

# SD1's SPRUCEOS partition: added at 2 GiB on the first boot (oakmoss-sd1part), reattached after a
# re-flash, formatted only while it holds no filesystem at all.
sd1() {
    [ -b "$SD1_DISK" ] && command -v oakmoss-sd1part >/dev/null || return 1
    set -- $(oakmoss-sd1part "$SD1_DISK")
    case $1 in
        present|reattached|new) ;;
        *) log "SD1: no SPRUCEOS partition: $*"; return 1 ;;
    esac
    dev=${SD1_DISK}p$2; n=0
    while [ ! -b "$dev" ] && [ "$n" -lt 20 ]; do sleep 0.1; n=$((n + 1)); done
    [ "$1" = present ] || log "SD1: SPRUCEOS partition $1 (${dev##*/})"
    fs=$(magic "$dev")
    [ "$fs" = unread ] && { log "SD1: ${dev##*/} cannot be read"; return 1; }
    if [ "$fs" = none ]; then
        mkfs.vfat -n SPRUCEOS "$dev" >/dev/null 2>&1 || { log "SD1: formatting ${dev##*/} failed"; return 1; }
        log "SD1: ${dev##*/} formatted FAT32, $(( $(cat "/sys/class/block/${dev##*/}/size") / 2048 )) MiB"
    fi
    echo "$dev"
}

sd2() {		# sd2 <wait s>: SD2, the other MMC card (its first partition, or the whole card)
    n=0
    while :; do
        for d in $SD2_GLOB; do
            case ${d##*/} in *boot*|*rpmb) continue ;; esac
            [ "/dev/${d##*/}" = "$SD1_DISK" ] && continue
            [ -b "/dev/${d##*/}" ] || continue
            sleep 0.2	# the partitions appear with the disk; give their nodes a moment
            if [ -b "/dev/${d##*/}p1" ]; then echo "/dev/${d##*/}p1"; else echo "/dev/${d##*/}"; fi
            return 0
        done
        [ "$n" -ge $(($1 * 4)) ] && return 1
        sleep 0.25; n=$((n + 1))
    done
}

cards_umount() {
    for m in $MNT/SDCARD_INT $MNT/SDCARD_EXT $MNT/SDCARD "$T/sd1" "$T/sd2"; do
        grep -q " $m " /proc/mounts && { umount "$m" 2>/dev/null || umount -l "$m"; }
    done
    rm -f "$STATE"
}

cards_mount() {
    cards_umount
    mkdir -p "$T"
    d1=$(sd1) && mount_card "$d1" "$T/sd1" || d1=
    f1=; [ -n "$d1" ] && frontend "$T/sd1" && f1=yes
    # SD2 may enumerate late: wait for it 10 s, or 3 s when SD1 can start a frontend anyway.
    w=10; [ -n "$f1" ] && w=3
    d2=$(sd2 "$w") && mount_card "$d2" "$T/sd2" || d2=
    f2=; [ -n "$d2" ] && frontend "$T/sd2" && f2=yes

    if [ -n "$f1" ] && [ -n "$f2" ]; then
        if newer "$T/sd2" "$T/sd1"; then host=sd2; else host=sd1; fi
    elif [ -n "$f1" ]; then host=sd1
    elif [ -n "$f2" ]; then host=sd2
    elif [ -n "$d2" ]; then host=sd2
    elif [ -n "$d1" ]; then host=sd1
    else host=none
    fi
    v1=$(version "$T/sd1"); v2=$(version "$T/sd2")

    # Each card goes where its role says: unmounted from the peek, mounted again there.
    r1=; r2=
    case $host in
        sd1) r1=$MNT/SDCARD; [ -n "$d2" ] && r2=$MNT/SDCARD_EXT ;;
        sd2) r2=$MNT/SDCARD; [ -n "$d1" ] && r1=$MNT/SDCARD_INT ;;
    esac
    [ -n "$d1" ] && umount "$T/sd1"
    [ -n "$d2" ] && umount "$T/sd2"
    [ -n "$r1" ] && { mount_card "$d1" "$r1" || { log "SD1: ${d1##*/} did not mount at $r1"; r1=; }; }
    [ -n "$r2" ] && { mount_card "$d2" "$r2" || { log "SD2: ${d2##*/} did not mount at $r2"; r2=; }; }

    printf '%s\n' "HOST=$host" "SD1_DEV=$d1" "SD1_ROOT=$r1" "SD2_DEV=$d2" "SD2_ROOT=$r2" > "$STATE"
    log "host $host; SD1 ${d1:-none}${d1:+ (spruce ${v1% *}, frontend ${f1:-no})} at ${r1:--};" \
        "SD2 ${d2:-none}${d2:+ (spruce ${v2% *}, frontend ${f2:-no})} at ${r2:--}"
}

case $1 in
    mount) cards_mount ;;
    umount) cards_umount ;;
    *) echo "usage: $0 mount|umount" >&2; exit 2 ;;
esac
