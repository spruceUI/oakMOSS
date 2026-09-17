#!/usr/bin/env bash
# Unpack the Zero 40 stock firmware (a raw card image) into the pieces the
# zero40-stock image reuses, named exactly as the XU20's PhoenixSuit items so
# scripts/make-hybrid-stock.sh reads both boards the same way.
#
#   scripts/unpack-zero40-stock.sh      -> inputs/zero40-stock/
#       adb.img                         the decompressed card image (8 GB, kept)
#       adb.img.dump/                   12345678_1234567890BOOT_0 (card boot0, sector 16),
#                                       12345678_BOOTPKG-00000000 (u-boot+monitor+scp+dtb, sector 32800),
#                                       RFSFAT16_BOOT-RESOURCE_FE (bootloader partition), RFSFAT16_ENV_FEX000000000,
#                                       RFSFAT16_BOOT_FEX00000000 (boot.img), RFSFAT16_DTBO_FEX00000000,
#                                       RFSFAT16_VBMETA_FEX000000 / _SYSTEM_FE / _VENDOR_FE, RFSFAT16_SUPER_FEX0000000
#       vendor/modules/, vendor/etc/firmware/, vendor/firmware/   the vendor's 4.9.170 modules,
#                                       the XR829 firmware and the PowerVR 1.11 firmware, out of the "super" partition (lpunpack ->
#                                       vendor.img -> debugfs)
#
# The image is MagicX's public "Static Adb Firmware" (lib.sh: ZERO40_STOCK_URL),
# fetched by fetch-inputs.sh and never redistributed here. Needs xz, python3,
# sfdisk, debugfs (e2fsprogs), git.
. "$(dirname "$0")/lib.sh"
command -v debugfs >/dev/null || die "need debugfs (e2fsprogs)"
command -v sfdisk >/dev/null || die "need sfdisk (util-linux)"
W=$ZERO40_STOCK_DIR; mkdir -p "$W"
if [ -f "$W/.done" ] && [ "$(cat "$W/.done")" = "$ZERO40_STOCK_IMG_SHA256" ]; then log "have $W"; exit 0; fi
IMG=$W/$ZERO40_STOCK_IMG
if ! [ -f "$IMG" ] || ! sha256_check "$IMG" "$ZERO40_STOCK_IMG_SHA256"; then
    xz=$INPUTS_DIR/$ZERO40_STOCK_XZ
    [ -f "$xz" ] || die "missing $xz (scripts/fetch-inputs.sh)"
    sha256_check "$xz" "$ZERO40_STOCK_XZ_SHA256" || die "unexpected Zero 40 firmware archive"
    log "xz -d $(basename "$xz") -> $IMG (8 GB)"
    xz -dc "$xz" > "$IMG.part" && mv "$IMG.part" "$IMG"
    sha256_check "$IMG" "$ZERO40_STOCK_IMG_SHA256" || die "unexpected Zero 40 firmware image after decompression"
fi
log "card image items -> $IMG.dump"
DUMP=$IMG.dump; rm -rf "$DUMP"; mkdir -p "$DUMP"
# Partition geometry comes from the image's own GPT, never from constants.
part() { sfdisk -d "$IMG" 2>/dev/null | awk -F'[ ,]+' -v n="$1" '$0 ~ "name=\"" n "\"" {for(i=1;i<=NF;i++){if($i=="start=")s=$(i+1); if($i=="size=")z=$(i+1)} print s, z}'; }
cut() { # cut <name> <item> [bytes]: a whole partition, or its first N bytes
    read -r s z <<<"$(part "$1")"; [ -n "$s" ] || die "no GPT partition named $1 in the image"
    if [ -n "${3:-}" ]; then dd if="$IMG" bs=512 skip="$s" count=$(( ($3 + 511) / 512 )) status=none | head -c "$3" > "$DUMP/$2"
    else dd if="$IMG" bs=512 skip="$s" count="$z" status=none > "$DUMP/$2"; fi
    echo "    $2 <- $1 ($(stat -c%s "$DUMP/$2") bytes)"
}
[ "$(dd if="$IMG" bs=512 skip=16 count=1 status=none | head -c 8 | tail -c 4)" = "eGON" ] || die "no boot0 at sector 16"
[ "$(dd if="$IMG" bs=512 skip=32800 count=1 status=none | head -c 13)" = "sunxi-package" ] || die "no boot package at sector 32800"
dd if="$IMG" bs=512 skip=16 count=128 status=none > "$DUMP/12345678_1234567890BOOT_0"        # boot0_sdcard: 64 KiB, as the XU20 item
# The boot package declares its own items (name, offset, length at 368-byte
# stride from byte 64); take up to the end of the last one, 8 KiB-rounded.
pkg_len=$(dd if="$IMG" bs=512 skip=32800 count=8 status=none | python3 -c '
import struct,sys; b=sys.stdin.buffer.read(); end=0
for off in range(64, 64+368*8, 368):
    name=b[off:off+64].split(b"\0")[0]
    if not name: break
    o,l=struct.unpack_from("<II", b, off+64); end=max(end,o+l)
print((end+8191)//8192*8192)')
[ "$pkg_len" -gt 65536 ] || die "boot package length parse failed ($pkg_len)"
dd if="$IMG" bs=512 skip=32800 count=$((pkg_len/512)) status=none > "$DUMP/12345678_BOOTPKG-00000000"
echo "    boot0 65536 bytes, boot package $pkg_len bytes"
cut bootloader RFSFAT16_BOOT-RESOURCE_FE
cut env        RFSFAT16_ENV_FEX000000000 131072
cut boot       RFSFAT16_BOOT_FEX00000000
cut dtbo       RFSFAT16_DTBO_FEX00000000
# vbmeta items: 256-byte header + authentication + auxiliary blocks, page-rounded
for pair in "vbmeta:RFSFAT16_VBMETA_FEX000000" "vbmeta_system:RFSFAT16_VBMETA_SYSTEM_FE" "vbmeta_vendor:RFSFAT16_VBMETA_VENDOR_FE"; do
    n=${pair%%:*}; it=${pair#*:}; read -r s z <<<"$(part "$n")"
    len=$(dd if="$IMG" bs=512 skip="$s" count=1 status=none | python3 -c 'import struct,sys; h=sys.stdin.buffer.read(); a,x=struct.unpack(">QQ",h[12:28]); print(((256+a+x)+4095)//4096*4096 if h[:4]==b"AVB0" else 0)')
    [ "$len" -gt 0 ] || die "$n is not an AVB image"
    cut "$n" "$it" "$len"
done
[ "$(head -c 8 "$DUMP/RFSFAT16_BOOT_FEX00000000")" = "ANDROID!" ] || die "boot partition is not an Android boot image"
[ "$(head -c 4 "$DUMP/RFSFAT16_ENV_FEX000000000" | tail -c 0 ; tr -d '\0' < "$DUMP/RFSFAT16_ENV_FEX000000000" | grep -c 'bootcmd=')" -ge 1 ] || die "env item carries no bootcmd"

log "super: lpunpack -> vendor.img"
LP=$TOOLS_DIR/lpunpack
if [ ! -f "$LP/lpunpack.py" ] || [ "$(git -C "$LP" rev-parse HEAD 2>/dev/null)" != "$LPUNPACK_COMMIT" ]; then
    rm -rf "$LP"; git clone -q "$LPUNPACK_REPO" "$LP"; git -C "$LP" checkout -q "$LPUNPACK_COMMIT"
fi
read -r s z <<<"$(part super)"; [ -n "$s" ] || die "no super partition"
dd if="$IMG" bs=512 skip="$s" count="$z" status=none > "$W/super.raw"     # raw here, not sparse as in the PhoenixSuit pack
mkdir -p "$W/super"
python3 "$LP/lpunpack.py" -p vendor "$W/super.raw" "$W/super" >/dev/null || die "lpunpack could not extract vendor from super"
[ -f "$W/super/vendor.img" ] || die "no vendor.img out of super"
rm -f "$W/super.raw"

log "vendor.img: modules and firmware"
rm -rf "$W/vendor"; mkdir -p "$W/vendor" "$W/vendor/etc"
debugfs -R "rdump /modules $W/vendor" "$W/super/vendor.img" >/dev/null 2>&1 || die "debugfs could not read vendor.img"
debugfs -R "rdump /etc/firmware $W/vendor/etc" "$W/super/vendor.img" >/dev/null 2>&1 || true
# The PowerVR firmware the vendor kernel's pvrsrvkm 1.11 loads lives at /vendor/firmware
# (a different DDK build from the rgx.fw our SDK ships for its 1.19 driver).
debugfs -R "rdump /firmware $W/vendor" "$W/super/vendor.img" >/dev/null 2>&1 || true
[ -d "$W/vendor/modules" ] || die "vendor.img carries no /modules"
for m in pvrsrvkm simplepad sunxi-vibrator 8189es xr829; do
    [ -f "$W/vendor/modules/$m.ko" ] || die "vendor module missing: $m.ko"
done
[ -f "$W/vendor/etc/firmware/fw_xr829.bin" ] || die "XR829 firmware missing from vendor/etc/firmware"
[ -f "$W/vendor/firmware/rgx.fw.22.102.54.38" ] || die "PowerVR firmware missing from vendor/firmware"
log "$(ls "$W/vendor/modules"/*.ko | wc -l) vendor modules, $(ls "$W/vendor/etc/firmware" | wc -l) firmware files"
echo "$ZERO40_STOCK_IMG_SHA256" > "$W/.done"
log "Zero 40 stock firmware unpacked in $W"
