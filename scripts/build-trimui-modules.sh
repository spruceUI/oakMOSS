#!/usr/bin/env bash
# Build loadable kernel modules for the TrimUI A133P boards (Brick, Brick Pro, Smart
# Pro) from this SDK's Tina linux-4.9 tree, against the device's own kernel config.
#
#   scripts/build-trimui-modules.sh <config> [out-dir]
#
# <config> is the device's /proc/config.gz (gzipped or plain). The stock kernel and the
# oakMOSS tree share vermagic "4.9.191 SMP preempt mod_unload aarch64" and have
# MODVERSIONS off. The config makes every other layout match, and the patches in
# sdk-patches/trimui-modules/ fix the places where enabling a module changes a
# built-in structure.
#
# The kernel source is copied out of the SDK first (the SDK's in-tree kernel build is
# left untouched), then built with the SDK's own Linaro GCC 6.4 in the container.
# Builds: zsmalloc, zram, lzo, lz4, lz4_compress (the spruce zram stack).
# Output: <out-dir>/modules/*.ko (debug-stripped) + SHA256SUMS + config-delta.txt.
. "$(dirname "$0")/lib.sh"
need_sdk
CONFIG_IN=${1:?usage: build-trimui-modules.sh <device-config> [out-dir]}
OUT=$(realpath -m "${2:-$BUILDS_DIR/$(stamp)-trimui-modules}")
case "$OUT" in "$BUILDS_DIR"/*) ;; *) die "out-dir must be under $BUILDS_DIR (the container mounts only that)";; esac
mkdir -p "$OUT/modules"
REL=${OUT#"$BUILDS_DIR"/}

log "copying linux-4.9 into $OUT/linux-4.9 (sources only)"
rsync -a --delete --exclude='*.o' --exclude='*.ko' --exclude='*.cmd' --exclude='*.a' \
    --exclude='.tmp_*' --exclude='*.mod.c' --exclude='*.dtb' --exclude='vmlinux*' \
    --exclude='Image*' --exclude='System.map' --exclude='.git' \
    "$SDK_DIR/lichee/linux-4.9/" "$OUT/linux-4.9/"
zcat -f "$CONFIG_IN" > "$OUT/device.config"
for p in "$OAKMOSS_ROOT"/sdk-patches/trimui-modules/*.patch; do
    log "patch $(basename "$p")"
    patch -d "$OUT/linux-4.9" -p1 --no-backup-if-mismatch -s < "$p" || die "patch failed: $p"
done

TOOLCHAIN=vendor "$OAKMOSS_ROOT/scripts/run-in-sdk.sh" "set -e
export STAGING_DIR=/tmp PATH=/home/builder/lichee/prebuilt/gcc/linux-x86/aarch64/toolchain-sunxi-glibc/toolchain/bin:\$PATH
cd /home/builder/builds/$REL/linux-4.9
M='make ARCH=arm64 CROSS_COMPILE=aarch64-openwrt-linux-gnu- -j$(nproc)'
\$M mrproper >/dev/null
cp ../device.config .config
scripts/config --module ZSMALLOC --disable ZSMALLOC_STAT --disable PGTABLE_MAPPING \
    --module ZRAM --module CRYPTO_LZ4 --module CRYPTO_LZO --module LZ4_COMPRESS
\$M olddefconfig >/dev/null
diff <(grep -E '^(# )?CONFIG_' ../device.config | sort) <(grep -E '^(# )?CONFIG_' .config | sort) > ../config-delta.txt || true
\$M prepare scripts >/dev/null
# one target per make: several single-.ko goals in one parallel make race in modpost
for k in mm/zsmalloc drivers/block/zram/zram crypto/lz4 crypto/lzo lib/lz4/lz4_compress; do \$M \$k.ko >/dev/null; done
for k in mm/zsmalloc drivers/block/zram/zram crypto/lz4 crypto/lzo lib/lz4/lz4_compress; do
    aarch64-openwrt-linux-gnu-objcopy --strip-debug \$k.ko ../modules/\$(basename \$k).ko
done" || die "module build failed"

# Guard: a built-in-only zone stat must not leak into the module (the NR_ZSPAGES bug).
OBJDUMP=$SDK_DIR/prebuilt/gcc/linux-x86/aarch64/toolchain-sunxi-glibc/toolchain/bin/aarch64-openwrt-linux-gnu-objdump
if "$OBJDUMP" -dr "$OUT/modules/zsmalloc.ko" | grep -q zone_page_state; then
    die "zsmalloc.ko still updates a zone stat: sdk-patches/trimui-modules did not apply"
fi
(cd "$OUT/modules" && sha256sum *.ko > SHA256SUMS)
log "modules in $OUT/modules; review $OUT/config-delta.txt (expect only the =m options and options this tree lacks)"
