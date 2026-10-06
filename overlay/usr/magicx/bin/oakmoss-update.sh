#!/bin/sh
# Install an oakMOSS update (.omupd, scripts/make-update.py) into the slot that is
# not running, update boot0, the U-Boot package and boot-resource when they
# differ, then point U-Boot at the new slot for a trial boot (docs/updates.md).
# Exits 0 when the device should reboot. The package is removed on success and
# renamed to .failed otherwise, so a bad one is not retried every boot.
#
#   oakmoss-update.sh <file.omupd>
#
# DEVICE, BYNAME, DISK and FIRST_SECTOR exist for testing against plain files.

PKG=$1
BYNAME=${BYNAME:-/dev/by-name}
DEVICE=${DEVICE:-$(cat /usr/magicx/device 2>/dev/null)}
LOG=${LOG:-/mnt/UDISK/oakmoss-boot.log}
W=${TMPDIR:-/tmp}/omupd

log() {
    echo "$(cut -d' ' -f1 /proc/uptime) update: $*" >> "$LOG" 2>/dev/null
    echo "update: $*" >&2
}
fail() {
    log "failed: $*"
    mv -f "$PKG" "$PKG.failed" 2>/dev/null
    rm -rf "$W"
    exit 1
}

rm -rf "$W"; mkdir -p "$W"
dd if="$PKG" bs=4096 count=1 2>/dev/null | tr -d '\000' > "$W/manifest"
m() { sed -n "s/^$1=//p" "$W/manifest" | head -n 1; }

[ "$(m FORMAT)" = omupd1 ] || fail "$PKG is not an oakMOSS update"
[ "$(m BOARD)" = "$DEVICE" ] || fail "$PKG is for the $(m BOARD), this is the $DEVICE"
log "$(m VERSION) from $PKG"

part() {
    _off=$(m "$1_OFFSET"); _len=$(m "$1_LENGTH")
    dd if="$PKG" bs=4096 skip=$((_off / 4096)) count=$(((_len + 4095) / 4096)) 2>/dev/null |
        head -c "$_len" |
        if [ "$(m "$1_GZIP")" = 1 ]; then gzip -dc; else cat; fi
}

# sha256 of SIZE bytes of a device or file, starting at a sector.
on_card() {
    sync
    { echo 3 > /proc/sys/vm/drop_caches; } 2>/dev/null
    if [ "$3" = 0 ]; then
        dd if="$1" bs=1M count=$((($2 + 1048575) / 1048576)) 2>/dev/null
    else
        dd if="$1" bs=512 skip="$3" count=$((($2 + 511) / 512)) 2>/dev/null
    fi | head -c "$2" | sha256sum | cut -d' ' -f1
}

size_of() {
    _dev=$(readlink -f "$1")
    if [ -b "$_dev" ]; then
        echo $(($(cat "/sys/class/block/${_dev##*/}/size") * 512))
    else
        wc -c < "$_dev"
    fi
}

# put <part> <device> <sector>: write, then read back and compare.
put() {
    if [ "$3" = 0 ]; then
        part "$1" | dd of="$2" bs=1M conv=fsync 2>/dev/null
    else
        part "$1" | dd of="$2" bs=512 seek="$3" conv=notrunc,fsync 2>/dev/null
    fi || fail "writing $1 to $2"
    [ "$(on_card "$2" "$(m "$1_SIZE")" "$3")" = "$(m "$1_SHA256")" ] || fail "$1 on $2 does not read back"
    log "$1 written to $2 at sector $3"
}

for p in $(m PARTS); do
    [ "$(part "$p" | sha256sum | cut -d' ' -f1)" = "$(m "${p}_SHA256")" ] || fail "$p is damaged"
done

cur_boot=$(fw_printenv -n boot_partition 2>/dev/null); cur_boot=${cur_boot:-boot}
cur_root=$(fw_printenv -n root_partition 2>/dev/null); cur_root=${cur_root:-rootfs}
if [ "$cur_root" = rootfs_b ]; then new_boot=boot new_root=rootfs; else new_boot=boot_b new_root=rootfs_b; fi
[ -e "$BYNAME/$new_boot" ] && [ -e "$BYNAME/$new_root" ] ||
    fail "this card has no second slot; flash an oakMOSS image with one first"
for p in boot:$new_boot rootfs:$new_root bootres:bootloader; do
    [ "$(m "${p%%:*}_SIZE")" -le "$(size_of "$BYNAME/${p#*:}")" ] || fail "${p%%:*} does not fit in ${p#*:}"
done

put boot "$BYNAME/$new_boot" 0
put rootfs "$BYNAME/$new_root" 0

# Second copy first: an interrupted write leaves the other copy whole.
DISK=${DISK:-$(readlink -f "$BYNAME/boot" | sed 's/p[0-9]*$//')}
FIRST_SECTOR=${FIRST_SECTOR:-$(cat "/sys/class/block/$(readlink -f "$BYNAME/bootloader" | sed 's|.*/||')/start" 2>/dev/null)}
[ "$((256 * 512 + $(m boot0_SIZE)))" -le $((2048 * 512)) ] || fail "boot0 is too big for its second copy"
[ "$((24576 * 512 + $(m package_SIZE)))" -le $((32800 * 512)) ] || fail "the U-Boot package is too big for its second copy"
[ -n "$FIRST_SECTOR" ] && [ "$((32800 * 512 + $(m package_SIZE)))" -le $((FIRST_SECTOR * 512)) ] ||
    fail "the U-Boot package runs into the partitions"
for p in boot0:256:16 package:24576:32800; do
    name=${p%%:*}; spare=${p#*:}; spare=${spare%:*}; main=${p##*:}
    [ "$(on_card "$DISK" "$(m "${name}_SIZE")" "$main")" = "$(m "${name}_SHA256")" ] && continue
    put "$name" "$DISK" "$spare"
    put "$name" "$DISK" "$main"
done
if [ "$(on_card "$BYNAME/bootloader" "$(m bootres_SIZE)" 0)" != "$(m bootres_SHA256)" ]; then
    put bootres "$BYNAME/bootloader" 0
fi

cat > "$W/env" <<EOF
boot_partition $new_boot
root_partition $new_root
ab_fallback_boot $cur_boot
ab_fallback_root $cur_root
ab_try 1
ab_reverted
parts_clean rootfs_data
EOF
fw_setenv -s "$W/env" || fail "could not switch to $new_root"
log "next boot tries $new_boot + $new_root, falling back to $cur_boot + $cur_root"
rm -f "$PKG"
rm -rf "$W"
sync
exit 0
