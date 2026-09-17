#!/bin/sh
# EARLY PROBE: the kernel's init= while a board is being brought up. Runs as
# PID 1 before the real init, with no console anyone can read, and answers two
# questions the panel alone cannot: did the kernel mount our root and execute
# a program from it (the panel turns MAGENTA the moment this runs), and what
# did the kernel say on the way (dmesg, cmdline, block devices, mounts go to a
# file on the USER card's FAT filesystem - readable on any PC - and on this
# card's UDISK partition). Then it hands over to /sbin/init exactly as the
# kernel would have. Installed by the stock-chain recipe when EARLY_PROBE=1;
# a shipped card never carries it.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
mount -t proc proc /proc 2>/dev/null
mount -t sysfs sysfs /sys 2>/dev/null
mount -t devtmpfs devtmpfs /dev 2>/dev/null
/usr/magicx/bin/fbfill 660066 2>/dev/null        # magenta: root mounted, init= running
up() { cut -d' ' -f1 /proc/uptime 2>/dev/null; }
# The disk the root filesystem is on, by the major:minor of "/".
rootmm=$(awk '$5=="/" {print $3; exit}' /proc/self/mountinfo 2>/dev/null)
rootdisk=""
for b in /sys/class/block/mmcblk*p*; do
    [ -e "$b/dev" ] || continue
    if [ "$(cat "$b/dev" 2>/dev/null)" = "$rootmm" ]; then rootdisk=${b##*/}; rootdisk=${rootdisk%p*}; break; fi
done
report() {
    echo "=== oakMOSS early probe $(up) s, device=$(cat /usr/magicx/device 2>/dev/null)"
    echo "--- cmdline"; cat /proc/cmdline
    echo "--- root: $rootmm on ${rootdisk:-?}"
    echo "--- block devices"; for b in /sys/class/block/*; do n=${b##*/}; case $n in loop*|ram*|zram*) continue;; esac; echo "$n dev=$(cat "$b/dev" 2>/dev/null) size=$(cat "$b/size" 2>/dev/null) $(cat "$b/partition" 2>/dev/null | sed 's/^/part=/')"; done
    echo "--- mmc hosts"; for h in /sys/class/mmc_host/*; do echo "${h##*/} -> $(readlink "$h" | sed 's|.*/devices/||')"; done
    echo "--- mounts"; cat /proc/mounts
    echo "--- dmesg"; dmesg
}
mkdir -p /tmp/probe-sd2 /tmp/probe-udisk
wrote=""
for b in /sys/class/block/mmcblk*p1; do
    n=${b##*/}; case $n in "$rootdisk"p*) continue;; esac
    [ -e "/dev/$n" ] || continue
    if mount -t vfat -o rw,noatime "/dev/$n" /tmp/probe-sd2 2>/dev/null || mount -t exfat -o rw,noatime "/dev/$n" /tmp/probe-sd2 2>/dev/null; then
        report > /tmp/probe-sd2/oakmoss-early-probe.log 2>&1; sync /tmp/probe-sd2/oakmoss-early-probe.log 2>/dev/null
        umount /tmp/probe-sd2 2>/dev/null; wrote="$wrote $n"
    fi
done
if [ -n "$rootdisk" ] && [ -e "/dev/${rootdisk}p8" ] && mount -t ext4 -o rw,noatime "/dev/${rootdisk}p8" /tmp/probe-udisk 2>/dev/null; then
    { report; echo "--- written to user card partitions:${wrote:- none}"; } > /tmp/probe-udisk/oakmoss-early-probe.log 2>&1
    umount /tmp/probe-udisk 2>/dev/null
fi
/usr/magicx/bin/fbfill 006666 2>/dev/null        # teal: the probe finished writing, handing over to init
umount /dev 2>/dev/null; umount /sys 2>/dev/null; umount /proc 2>/dev/null
exec /sbin/init
