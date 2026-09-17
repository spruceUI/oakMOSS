#!/usr/bin/env bash
# Adapt our Zero 40 rootfs squashfs to MagicX's kernel for the HYBRID image.
#
#   UNSQUASHFS=... MKSQUASHFS=... adapt-rootfs.sh <our rootfs.fex> <main-zero40.img> <out rootfs.fex>
#
# The hybrid boots MagicX's own kernel (main-zero40: 4.9.191, vermagic identical
# to ours, MODVERSIONS off in both) with OUR root filesystem. The kernel modules
# in that filesystem are built against OUR kernel configuration, and that is
# not the same kernel: MagicX's has CONFIG_BUG=n and CONFIG_KALLSYMS=n where
# ours has both on, so every WARN_ON in a module of ours is a brk trap its
# kernel cannot classify - report_bug() without GENERIC_BUG answers
# BUG_TRAP_TYPE_BUG and the arm64 handler calls die("Oops - BUG") - and the
# round-8 rebuild turned our netfilter core into modules, so ip_tables.ko and
# x_tables.ko of ours started loading into their kernel at every boot. The
# round-8 rootfs never came up under that kernel (2026-09-16, three images);
# the pre-round-8 one did. MagicX's own rootfs ships modules built for exactly
# that kernel, so the hybrid carries THOSE, and its autoload list, instead of
# ours: pvrsrvkm + dc_sunxi (PowerVR, DDK 1.19@6345021 in both trees, so our
# userland matches), simplepad, fuse, and the iptables set. Nothing of ours
# autoloads. Our radio modules (8189es, xradio_*) stay on the filesystem for
# the diagnostic radio experiment, which loads them itself and is bench work.
#
# The modules come straight out of the main-zero40 image's rootfs partition
# (no extra input), the way the XU20 image takes the vendor's modules out of
# its stock firmware.
# Tools come in through the environment, so nothing here is tree-specific.
set -euo pipefail
die() { echo "adapt-rootfs: $*" >&2; exit 1; }
SRC=${1:?our rootfs.fex}; KG=${2:?main-zero40 image}; OUT=${3:?out rootfs.fex}
UNSQ=${UNSQUASHFS:?set UNSQUASHFS to the SDK unsquashfs4}; MKSQ=${MKSQUASHFS:?set MKSQUASHFS to the SDK mksquashfs4}
[ -f "$SRC" ] || die "no $SRC"; [ -f "$KG" ] || die "no $KG"
[ -x "$UNSQ" ] && [ -x "$MKSQ" ] || die "squashfs tools missing: $UNSQ / $MKSQ"
command -v sfdisk >/dev/null || die "need sfdisk (util-linux)"
KVER=4.9.191
RADIO_MODULES="8189es xradio_core xradio_mac xradio_wlan"   # kept for the experiment lane only
# Unpacking the rootfs and repacking it wants ~1 GiB under ${TMPDIR:-/tmp} (often a tmpfs).
have=$(df -Pk "${TMPDIR:-/tmp}" 2>/dev/null | awk 'NR==2 {print int($4/1024)}')
[ -n "$have" ] && [ "$have" -ge 1024 ] || die "only ${have:-?} MiB free on ${TMPDIR:-/tmp}, need about 1024: free it or export TMPDIR"
W=$(mktemp -d "${TMPDIR:-/tmp}/adapt-z40.XXXX"); trap 'rm -rf "$W"' EXIT

echo "--- MagicX's modules out of $(basename "$KG")"
eval "$(sfdisk -d "$KG" 2>/dev/null | awk -F'[ ,]+' '/name="rootfs"/{for(i=1;i<=NF;i++){if($i=="start=")s=$(i+1); if($i=="size=")z=$(i+1)} print "RS="s" RZ="z}')"
[ -n "${RS:-}" ] && [ -n "${RZ:-}" ] || die "no GPT partition named rootfs in $KG"
dd if="$KG" bs=512 skip="$RS" count="$RZ" status=none > "$W/vendor.sqsh"
[ "$(head -c 4 "$W/vendor.sqsh")" = "hsqs" ] || die "the rootfs partition of $KG is not a squashfs"
"$UNSQ" -n -f -d "$W/vendor" "$W/vendor.sqsh" "lib/modules/$KVER" etc/modules.d >/dev/null 2>&1 || true
VM=$W/vendor/lib/modules/$KVER; VD=$W/vendor/etc/modules.d
[ -d "$VM" ] && [ -d "$VD" ] || die "MagicX's rootfs carries no lib/modules/$KVER or etc/modules.d"
for m in pvrsrvkm dc_sunxi simplepad fuse ip_tables x_tables; do [ -f "$VM/$m.ko" ] || die "MagicX's module set lacks $m.ko"; done
for d in 20-ge8300-km 25-ge8300-km simplepad 80-fuse; do [ -f "$VD/$d" ] || die "MagicX's autoload list lacks $d"; done
echo "    $(ls "$VM"/*.ko | wc -l) modules, $(ls "$VD" | wc -l) autoload files"

echo "--- our rootfs $(basename "$SRC")"
"$UNSQ" -n -d "$W/root" "$SRC" >/dev/null 2>"$W/unsq.err" || true
grep -v -i 'could not\|xattr\|mknod\|permission\|compressor options' "$W/unsq.err" | head -3 >&2 || true
R=$W/root
[ "$(tr -d '\r\n' < "$R/usr/magicx/device" 2>/dev/null)" = zero40 ] || die "rootfs marker is not zero40"
OM=$R/lib/modules/$KVER
[ -d "$OM" ] || die "our rootfs carries no lib/modules/$KVER"
# The two kernels must agree on the module ABI tag before a module of theirs
# can go into a filesystem of ours: identical vermagic, and no CRCs to compare.
ours=$(strings "$OM/pvrsrvkm.ko" | grep -m1 '^vermagic=' || true); theirs=$(strings "$VM/pvrsrvkm.ko" | grep -m1 '^vermagic=' || true)
[ -n "$ours" ] && [ "$ours" = "$theirs" ] || die "vermagic differs: ours '$ours' vs MagicX '$theirs'"
# The PowerVR userland we ship must be the DDK their pvrsrvkm was built from.
kddk=$(strings "$VM/pvrsrvkm.ko" | grep -m1 -oE '[0-9]+\.[0-9]+@[0-9]+' || true)
uddk=$(strings "$R/usr/lib/libGLESv2.so" | grep -m1 -oE '[0-9]+\.[0-9]+@[0-9]+' || true)
[ -n "$kddk" ] && [ "$kddk" = "$uddk" ] || die "PowerVR DDK mismatch: MagicX's pvrsrvkm is $kddk, our userland is $uddk"

echo "--- modules: MagicX's set replaces ours (${theirs#vermagic=}; PowerVR DDK $kddk)"
mkdir -p "$W/keep"
for m in $RADIO_MODULES; do [ -f "$OM/$m.ko" ] && cp -a "$OM/$m.ko" "$W/keep/"; done
rm -rf "$OM"; mkdir -p "$OM"
cp -a "$VM"/*.ko "$OM/"
cp -a "$W/keep"/*.ko "$OM/" 2>/dev/null || true
rm -f "$R"/etc/modules.d/*
cp -a "$VD"/* "$R/etc/modules.d/"
: > "$R/etc/modules.d/net-xr829"   # the stub spruce's radio loader expects; loads nothing
grep -rlE '^(8189es|xradio_[a-z]+|vin_io|vin_v4l2|cci)$' "$R/etc/modules.d" | grep . && die "a module of ours would still autoload" || true
echo "    $(ls "$OM"/*.ko | wc -l) modules ($(ls "$W/keep" | wc -l) of ours kept, radio only, not autoloaded)"
echo "    autoload: $(ls "$R/etc/modules.d" | tr '\n' ' ')"

echo "--- repack (xz, 256 KiB blocks, root-owned, as the SDK does)"
# -p entries as in the SDK's build/image.mk; /dev already exists after the
# unpack, so mksquashfs notes the duplicate pseudo entry and moves on.
"$MKSQ" "$R" "$OUT" -noappend -root-owned -comp xz -b 262144 -processors "$(nproc)" \
    -p '/dev d 755 0 0' -p '/dev/console c 600 0 0 5 1' >/dev/null 2>"$W/mksq.err" || { cat "$W/mksq.err" >&2; die "mksquashfs failed"; }
grep -v 'Pseudo file\|Ignoring, exclude' "$W/mksq.err" >&2 || true
"$UNSQ" -s "$OUT" 2>/dev/null | grep -E 'Filesystem size|Compression|Block size' | sed 's/^/    /'
echo "    $OUT ($(stat -c%s "$OUT") bytes)"
