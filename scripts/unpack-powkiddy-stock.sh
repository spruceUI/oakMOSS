#!/usr/bin/env bash
# The Powkiddy V90S/V20 stock boot chain, as the items scripts/make-own-kernel-stock.sh reads:
# from the files scripts/fetch-inputs.sh downloads (Knulli's public copies, pinned in lib.sh) or
# from a local directory holding the same files (e.g. read off a stock card), each checked
# against its pin. The V90S and V20 cards carry the same chain.
#
#   scripts/unpack-powkiddy-stock.sh [source dir]      default: $INPUTS_DIR/powkiddy-stock-src
#
#   boot0.img        -> 12345678_1234567890BOOT_0  the card's boot0 (DDR3 576 MHz), sector 16/256
#   boot_package.fex -> 12345678_BOOTPKG-00000000  U-Boot, BL31, SCP and the tree, sector 32800
#   env.img          -> RFSFAT16_ENV_FEX000000000  the U-Boot env (128 KiB)
#   boot.img         -> RFSFAT16_BOOT_FEX00000000  the v0 boot image, for its header
#   boot-resource.fex (optional) -> RFSFAT16_BOOT-RESOURCE_FE  the stock logo partition; without
#                       it the card takes this build's own boot-resource (our logo)
set -euo pipefail
. "$(dirname "$0")/lib.sh"
SRC=${1:-$INPUTS_DIR/powkiddy-stock-src}
OUT=$POWKIDDY_STOCK_DIR/items
item() {  # item <source file> <item name> <sha256 pin>
    local f=$SRC/$1
    [ -f "$f" ] || die "no $f (scripts/fetch-inputs.sh, or a source directory that has $1)"
    sha256_check "$f" "$3" || die "$f does not match its pin in scripts/lib.sh"
    cp -f "$f" "$OUT/$2"; log "$1 -> items/$2"
}
mkdir -p "$OUT"
item boot0.img        12345678_1234567890BOOT_0 "$POWKIDDY_STOCK_BOOT0_SHA256"
item boot_package.fex 12345678_BOOTPKG-00000000 "$POWKIDDY_STOCK_PKG_SHA256"
item env.img          RFSFAT16_ENV_FEX000000000 "$POWKIDDY_STOCK_ENV_SHA256"
item boot.img         RFSFAT16_BOOT_FEX00000000 "$POWKIDDY_STOCK_BOOTIMG_SHA256"
if [ -f "$SRC/boot-resource.fex" ]; then
    cp -f "$SRC/boot-resource.fex" "$OUT/RFSFAT16_BOOT-RESOURCE_FE"; log "boot-resource.fex -> items (the stock logo)"
else
    rm -f "$OUT/RFSFAT16_BOOT-RESOURCE_FE"; log "no boot-resource in $SRC: the card will take the build's own"
fi
[ "$(head -c 8 "$OUT/12345678_1234567890BOOT_0" | tail -c 4)" = eGON ] || die "boot0 magic missing"
python3 "$OAKMOSS_ROOT/scripts/toc1-checksum.py" --check "$OUT/12345678_BOOTPKG-00000000" || die "the boot package fails its checksum"
log "Powkiddy stock chain ready: $OUT"
