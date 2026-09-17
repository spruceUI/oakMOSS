#!/usr/bin/env bash
# Zero 40 HYBRID SD1 image: Shaun Inman's main-zero40 release (boot0, U-Boot with
# the RTP40WV101B 480x800 panel, DTB with the axs15205 touch node, kernel
# 4.9.191 of 2026-02-02) with ITS rootfs partition replaced by OUR Zero 40
# rootfs squashfs. Needed because the SDK drop carries neither the Zero 40 panel
# driver nor its touch driver (our own chain shows the Zero 28's h028b23 panel:
# white screen on a Zero 40). See docs/hardware-notes.md.
#
#   scripts/make-hybrid-zero40.sh <zero40 build dir> [out dir]
#
# The main-zero40 image is downloaded by fetch-inputs.sh and never redistributed
# here. The kernel modules in the image are MagicX's own, taken out of that
# image's rootfs by scripts/adapt-zero40-rootfs.sh: our modules are built
# against our kernel configuration, and their kernel (CONFIG_BUG=n,
# CONFIG_KALLSYMS=n, netfilter core as modules) never came up with the round-8
# set of ours - see that script's header. Our PowerVR userland stays: both
# trees are DDK 1.19@6345021, and the adapter checks that on every build.
. "$(dirname "$0")/lib.sh"
BUILD=${1:?zero40 build directory (builds/<stamp>-zero40)}; shift || true
ST=$(stamp); OUT=${1:-$BUILDS_DIR/$ST-zero40-hybrid}
ROOTFS=$(ls "$BUILD"/*.img.dump/rootfs.fex 2>/dev/null | head -1)
[ -f "$ROOTFS" ] || die "no rootfs.fex under $BUILD (scripts/build.sh image zero40 produces it)"
grep -q '^device=zero40' "$BUILD/BUILD-INFO.txt" 2>/dev/null || die "$BUILD is not a zero40 build"
zip=$INPUTS_DIR/$MAINZERO40_ZIP
[ -f "$zip" ] || die "missing $zip (scripts/fetch-inputs.sh)"
sha256_check "$zip" "$MAINZERO40_ZIP_SHA256" || die "unexpected main-zero40 archive"
squashfs_tools
mkdir -p "$OUT"
need_tmp_space 2048
W=$(mktemp -d "${TMPDIR:-/tmp}/oakmoss-hybrid.XXXX"); trap 'rm -rf "$W"' EXIT
unzip -q -o "$zip" -d "$W"
BASE=$(find "$W" -name '*.img' | head -1); [ -f "$BASE" ] || die "no .img inside $zip"
sha256_check "$BASE" "$MAINZERO40_IMG_SHA256" || die "unexpected main-zero40 image"
# Confirm the rootfs really is the Zero 40 one before it goes into a Zero 40 chain.
"$UNSQUASHFS" -n -f -d "$W/r" "$ROOTFS" usr/magicx/device >/dev/null 2>&1 || true
marker=$(tr -d '\r\n' < "$W/r/usr/magicx/device" 2>/dev/null || true)
[ "$marker" = zero40 ] || die "rootfs marker is '$marker', not zero40"
# MagicX's modules and autoload list replace ours (the hybrid runs its kernel).
ADAPTED=$W/rootfs-magicx-modules.fex
UNSQUASHFS="$UNSQUASHFS" MKSQUASHFS="$MKSQUASHFS" "$OAKMOSS_ROOT/scripts/adapt-zero40-rootfs.sh" "$ROOTFS" "$BASE" "$ADAPTED" 2>&1 | sed 's/^/    /' >&2
[ -f "$ADAPTED" ] || die "adapt-zero40-rootfs.sh produced nothing"
FINAL=$OUT/oakmoss-zero40-hybrid-$ST-sd1.img
"$OAKMOSS_ROOT/scripts/replace-rootfs.sh" "$BASE" "$ADAPTED" "$FINAL"
{
  echo "device=zero40"; echo "kind=hybrid"; echo "built=$ST"; echo "oakmoss=$(oakmoss_version)"
  echo "boot_chain=main-zero40 v$MAINZERO40_VERSION (https://github.com/dedicated-os/main-zero40, Shaun Inman): boot0, u-boot, DTB, kernel, env, rootfs_data, private, recovery, pstore untouched"
  echo "boot_chain_sha256=$MAINZERO40_IMG_SHA256"
  echo "rootfs=our Zero 40 rootfs from $BUILD (see its BUILD-INFO.txt) with MagicX's own kernel modules and autoload list in place of ours (scripts/adapt-zero40-rootfs.sh; our radio modules kept, not autoloaded)"
  echo "rootfs_md5=$(md5_of "$ADAPTED") (as written; $(md5_of "$ROOTFS") before the module swap)"
  echo "outputs=$(basename "$FINAL") (raw GPT image: dd or Etcher to SD1, whole card)"
} > "$OUT/BUILD-INFO.txt"
[ "${COMPRESS:-0}" = 1 ] && xz -T0 -6 -k "$FINAL"
log "hybrid image ready: $OUT"; ls -la "$OUT" >&2
