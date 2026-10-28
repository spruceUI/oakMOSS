#!/usr/bin/env bash
# A TrimUI A133P board's stock chain, as the items scripts/make-own-kernel-stock.sh reads, out of
# TrimUI's public firmware zip (scripts/fetch-inputs.sh, pinned in lib.sh), every item checked
# against its pin. The zip's PhoenixSuit image is read in place (scripts/awimg-items.py).
#
#   scripts/unpack-trimui-stock.sh brick [zip]      -> $TRIMUI_BRICK_STOCK_DIR
#
#   items/12345678_1234567890BOOT_0    the card boot0, sector 16 and 256
#   items/BOOT    _BOOT0_0000000000    the NAND boot0 (only for make-own-kernel-stock.sh's sanity check)
#   items/12345678_BOOTPKG-00000000    U-Boot, BL31, SCP and the device tree, sector 32800
#   items/RFSFAT16_ENV_FEX000000000    the redundant U-Boot env (128 KiB)
#   items/RFSFAT16_BOOT_FEX00000000    the v0 boot image, for its header
#   items/RFSFAT16_BOOT-RESOURCE_FE    the stock boot logo, charge pictures and fonts
#   trimui_inputd                      TrimUI's input daemon, out of the image's rootfs (local images only)
#
# Needs python3 and debugfs (e2fsprogs). Nothing here is redistributed.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
BOARD=${1:?board: brick}
case $BOARD in
    brick) ZIP=${2:-$INPUTS_DIR/$TRIMUI_BRICK_ZIP}; OUT=$TRIMUI_BRICK_STOCK_DIR; P=TRIMUI_BRICK ;;
    *) die "unknown TrimUI board $BOARD (brick)" ;;
esac
pin() { local v="${P}_$1_SHA256"; printf '%s' "${!v:?no pin $v in scripts/lib.sh}"; }
# Debian keeps debugfs in /usr/sbin, which a non-login shell's PATH lacks (as mke2fs).
DEBUGFS=$(command -v debugfs || command -v /usr/sbin/debugfs || command -v /sbin/debugfs || true)
[ -n "$DEBUGFS" ] || die "need debugfs (e2fsprogs)"
[ -f "$ZIP" ] || die "no $ZIP (scripts/fetch-inputs.sh)"
sha256_check "$ZIP" "$(pin ZIP)" || die "$ZIP does not match its pin in scripts/lib.sh"

rm -rf "$OUT"; mkdir -p "$OUT/items"
python3 "$OAKMOSS_ROOT/scripts/awimg-items.py" "$ZIP" "$OUT/items" \
    12345678_1234567890BOOT_0 'BOOT    _BOOT0_0000000000' 12345678_BOOTPKG-00000000 RFSFAT16_ENV_FEX000000000 \
    RFSFAT16_BOOT_FEX00000000 RFSFAT16_BOOT-RESOURCE_FE RFSFAT16_ROOTFS_FEX000000 || die "awimg-items.py failed on $ZIP"
item() {  # item <item> <pin name>
    sha256_check "$OUT/items/$1" "$(pin "$2")" || die "items/$1 does not match its pin ($2) in scripts/lib.sh"
    log "items/$1: as pinned"
}
item 12345678_1234567890BOOT_0 BOOT0
item 12345678_BOOTPKG-00000000 PKG
item RFSFAT16_ENV_FEX000000000 ENV
item RFSFAT16_BOOT_FEX00000000 BOOTIMG
item RFSFAT16_BOOT-RESOURCE_FE BOOTRES
"$DEBUGFS" -R "dump /usr/trimui/bin/trimui_inputd $OUT/trimui_inputd" "$OUT/items/RFSFAT16_ROOTFS_FEX000000" >/dev/null 2>&1 ||
    die "debugfs could not read /usr/trimui/bin/trimui_inputd from the stock rootfs"
rm -f "$OUT/items/RFSFAT16_ROOTFS_FEX000000"
sha256_check "$OUT/trimui_inputd" "$(pin INPUTD)" || die "trimui_inputd does not match its pin in scripts/lib.sh"
chmod 0755 "$OUT/trimui_inputd"; log "trimui_inputd: as pinned"
[ "$(head -c 8 "$OUT/items/12345678_1234567890BOOT_0" | tail -c 4)" = eGON ] || die "boot0 magic missing"
python3 "$OAKMOSS_ROOT/scripts/toc1-checksum.py" --check "$OUT/items/12345678_BOOTPKG-00000000" || die "the boot package fails its checksum"
log "TrimUI $BOARD stock chain ready: $OUT"
