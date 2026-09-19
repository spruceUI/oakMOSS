#!/bin/sh
# INIT STAMP: the kernel's init= on a diagnostic card. Proves, on the card itself,
# that the kernel mounted the root filesystem and ran a program from it, without
# mounting anything writable (a mount would move the rootfs_data/UDISK mount counts
# that bracket the next stage). Appends "i<uptime>;" to the last sector of the
# pstore partition, raw, then hands over to /sbin/init exactly as the kernel would.
# Installed by make-own-kernel-stock.sh with INIT_STAMP=1 (needs PSTORE=1).
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
mount -t proc proc /proc 2>/dev/null
mount -t sysfs sysfs /sys 2>/dev/null
for u in /sys/class/block/*/uevent; do
    grep -qx 'PARTNAME=pstore' "$u" 2>/dev/null || continue
    b=${u%/uevent}; dev=/dev/${b##*/}; last=$(( $(cat "$b/size") - 1 ))
    [ -b "$dev" ] || break
    old=$(dd if="$dev" bs=512 skip="$last" count=1 2>/dev/null | tr -d '\000')
    printf '%s' "${old}i$(cut -d' ' -f1 /proc/uptime);" | dd of="$dev" bs=512 seek="$last" count=1 conv=sync,notrunc 2>/dev/null
    sync
    break
done
umount /sys 2>/dev/null; umount /proc 2>/dev/null
exec /sbin/init "$@"
