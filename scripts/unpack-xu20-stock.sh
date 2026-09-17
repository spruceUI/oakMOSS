#!/usr/bin/env bash
# Unpack the XU20 V32 stock firmware into the pieces the XU20 image reuses.
#
#   scripts/unpack-xu20-stock.sh        -> inputs/xu20-stock/
#       user.img.dump/                  every image item (boot0, boot package, boot,
#                                       dtbo, vbmeta, boot-resource, env, ...), by
#                                       awimage
#       vendor/modules/, vendor/firmware/   the vendor's kernel modules (4.9.170)
#                                       and firmware, out of the Android "super"
#                                       partition (sparse -> raw -> lpunpack ->
#                                       vendor.img -> debugfs)
#
# The firmware is MagicX's public developer release (lib.sh: XU20_STOCK_URL); it
# is fetched by fetch-inputs.sh and never redistributed here. Needs
# tools/awutils/bin/awimage (scripts/build-awutils.sh), python3, debugfs
# (e2fsprogs), unzip, git.
. "$(dirname "$0")/lib.sh"
AWIMAGE=$TOOLS_DIR/awutils/bin/awimage
[ -x "$AWIMAGE" ] || die "no $AWIMAGE (run scripts/build-awutils.sh)"
command -v debugfs >/dev/null || die "need debugfs (e2fsprogs)"
zip=$INPUTS_DIR/$XU20_STOCK_ZIP
[ -f "$zip" ] || die "missing $zip (scripts/fetch-inputs.sh)"
sha256_check "$zip" "$XU20_STOCK_ZIP_SHA256" || die "unexpected XU20 firmware archive"
W=$XU20_STOCK_DIR
if [ -f "$W/.done" ] && [ "$(cat "$W/.done")" = "$XU20_STOCK_IMG_SHA256" ]; then log "have $W"; exit 0; fi
rm -rf "$W"; mkdir -p "$W"
log "unzip $(basename "$zip")"
unzip -q -o "$zip" "$XU20_STOCK_IMG" -d "$W"
sha256_check "$W/$XU20_STOCK_IMG" "$XU20_STOCK_IMG_SHA256" || die "unexpected XU20 firmware image"

log "awimage: unpack the image items"
# A file-size limit is a belt for the braces the patch provides: an unpatched
# awimage on this header once wrote 109 GB of garbage before it was stopped.
( cd "$W" && ulimit -f 4000000 && "$AWIMAGE" -u "$XU20_STOCK_IMG" >/dev/null 2>"$W/awimage.err" ) \
    || die "awimage failed: $(head -3 "$W/awimage.err")"
DUMP=$W/$XU20_STOCK_IMG.dump
[ -d "$DUMP" ] || die "awimage produced no $DUMP"
for item in 12345678_1234567890BOOT_0 12345678_BOOTPKG-00000000 RFSFAT16_BOOT_FEX00000000 RFSFAT16_DTBO_FEX00000000 \
            RFSFAT16_ENV_FEX000000000 RFSFAT16_BOOT-RESOURCE_FE RFSFAT16_VBMETA_FEX000000 RFSFAT16_VBMETA_SYSTEM_FE \
            RFSFAT16_VBMETA_VENDOR_FE RFSFAT16_SUPER_FEX0000000; do
    [ -f "$DUMP/$item" ] || die "image item missing after unpack: $item"
done
log "$(ls "$DUMP" | grep -vc '\.hdr$') items unpacked"

log "super: Android sparse image -> raw"
python3 - "$DUMP/RFSFAT16_SUPER_FEX0000000" "$W/super.raw" <<'PY'
# simg2img in forty lines: the Android sparse format is a header and a list of
# chunks that are raw, fill, skip, or crc.
import struct, sys
src, dst = sys.argv[1], sys.argv[2]
f = open(src, 'rb'); o = open(dst, 'wb')
magic, major, minor, fhs, chs, blk, total_blks, total_chunks, _ = struct.unpack('<IHHHHIIII', f.read(28))
if magic != 0xED26FF3A:
    raise SystemExit("super item is not an Android sparse image")
f.seek(fhs)
for _ in range(total_chunks):
    ctype, _, csz, tsz = struct.unpack('<HHII', f.read(chs))
    body = tsz - chs
    if ctype == 0xCAC1:   # raw
        o.write(f.read(body))
    elif ctype == 0xCAC2: # fill
        o.write(f.read(4) * (csz * blk // 4))
    elif ctype == 0xCAC3: # don't care
        o.seek(csz * blk, 1)
    elif ctype == 0xCAC4: # crc
        f.seek(body, 1)
    else:
        raise SystemExit(f"unknown sparse chunk type {ctype:#x}")
o.truncate(total_blks * blk); o.close()
print(f"    {total_blks * blk} bytes raw")
PY

log "super: lpunpack -> vendor.img"
LP=$TOOLS_DIR/lpunpack
if [ ! -f "$LP/lpunpack.py" ] || [ "$(git -C "$LP" rev-parse HEAD 2>/dev/null)" != "$LPUNPACK_COMMIT" ]; then
    rm -rf "$LP"; git clone -q "$LPUNPACK_REPO" "$LP"; git -C "$LP" checkout -q "$LPUNPACK_COMMIT"
fi
mkdir -p "$W/super"
python3 "$LP/lpunpack.py" -p vendor "$W/super.raw" "$W/super" >/dev/null || die "lpunpack could not extract vendor from super"
[ -f "$W/super/vendor.img" ] || die "no vendor.img out of super"
rm -f "$W/super.raw"

log "vendor.img: modules and firmware"
# Allwinner's Android keeps the modules at the partition root (/vendor/modules,
# which is what its init.rc insmods), not under lib/.
mkdir -p "$W/vendor" "$W/vendor/etc"
debugfs -R "rdump /modules $W/vendor" "$W/super/vendor.img" >/dev/null 2>&1 || die "debugfs could not read vendor.img"
debugfs -R "rdump /etc/firmware $W/vendor/etc" "$W/super/vendor.img" >/dev/null 2>&1 || true
# The PowerVR firmware the vendor kernel's pvrsrvkm 1.11 loads lives at /vendor/firmware
# (a different DDK build from the rgx.fw our SDK ships for its 1.19 driver).
debugfs -R "rdump /firmware $W/vendor" "$W/super/vendor.img" >/dev/null 2>&1 || true
[ -d "$W/vendor/modules" ] || die "vendor.img carries no /modules"
for m in pvrsrvkm simplepad sunxi-vibrator 8189es xr829; do
    [ -f "$W/vendor/modules/$m.ko" ] || die "vendor module missing: $m.ko"
done
[ -f "$W/vendor/firmware/rgx.fw.22.102.54.38" ] || die "PowerVR firmware missing from vendor/firmware"
log "$(ls "$W/vendor/modules"/*.ko | wc -l) vendor modules"
echo "$XU20_STOCK_IMG_SHA256" > "$W/.done"
log "XU20 stock firmware unpacked in $W"
