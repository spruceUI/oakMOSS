#!/usr/bin/env bash
# Copy a raw SD1 image and write a rootfs squashfs into its "rootfs" partition.
#
#   scripts/replace-rootfs.sh <src.img> <rootfs.fex> <out.img>
#
# Used by make-hybrid-zero40.sh (known-good boot chain + our rootfs) and
# make-diag-image.sh. The partition is located by its GPT name through sfdisk,
# zero-filled, written, and read back for an md5 check. A sibling
# <out.img>.rootfs.fex keeps the exact squashfs that went in.
#
# Then the whole image is compared against the source: everything outside the
# rootfs partition must be identical. When a hybrid card fails to come up, this
# is the fact that decides where to look - a boot chain identical to a card that
# is known to boot cannot be why the screen stayed dark (Zero 40, 2026-09-16,
# where working that out by hand cost a round trip).
. "$(dirname "$0")/lib.sh"
SRC=${1:?src.img}; ROOTFS=${2:?rootfs.fex}; OUT=${3:?out.img}
[ -f "$SRC" ] || die "no $SRC"; [ -f "$ROOTFS" ] || die "no $ROOTFS"
command -v sfdisk >/dev/null || die "need sfdisk (util-linux)"
# OUT is an image FILE. Writing a card is a separate, deliberate act; refuse a
# block device here so a mistyped argument cannot overwrite a disk.
[ ! -b "$OUT" ] || die "refusing to write to the block device $OUT: this produces an image file, not a card"
[ ! -e "$OUT" ] || [ -f "$OUT" ] || die "$OUT exists and is not a regular file"
eval "$(sfdisk -d "$SRC" 2>/dev/null | awk -F'[ ,]+' '/name="rootfs"/{for(i=1;i<=NF;i++){if($i=="start=")s=$(i+1); if($i=="size=")z=$(i+1)} print "RS="s" RZ="z}')"
[ -n "${RS:-}" ] && [ -n "${RZ:-}" ] || die "no GPT partition named rootfs in $SRC"
SZ=$(stat -c%s "$ROOTFS")
[ "$SZ" -le $((RZ*512)) ] || die "rootfs ($SZ bytes) exceeds the partition ($((RZ*512)) bytes)"
mkdir -p "$(dirname "$OUT")"
cp -a "$SRC" "$OUT"
dd if=/dev/zero of="$OUT" bs=512 seek="$RS" count="$RZ" conv=notrunc status=none
dd if="$ROOTFS" of="$OUT" bs=512 seek="$RS" conv=notrunc status=none
flush_file "$OUT"   # never a bare sync: see lib.sh
a=$(dd if="$OUT" bs=512 skip="$RS" count=$(( (SZ+511)/512 )) status=none | head -c "$SZ" | md5sum | cut -c1-32)
b=$(md5_of "$ROOTFS")
[ "$a" = "$b" ] || die "read-back mismatch"
python3 - "$SRC" "$OUT" "$RS" "$RZ" <<'PY'
import os, sys
src, out, rs, rz = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
if os.path.getsize(src) != os.path.getsize(out):
    raise SystemExit(f"image size changed: {os.path.getsize(src)} -> {os.path.getsize(out)}")
lo, hi, step, size = rs * 512, (rs + rz) * 512, 8 << 20, os.path.getsize(src)
a, b = open(src, 'rb'), open(out, 'rb'); pos = 0
while pos < size:
    n = min(step, size - pos)
    if pos + n <= lo or pos >= hi:
        a.seek(pos); b.seek(pos)
        if a.read(n) != b.read(n):
            raise SystemExit(f"bytes outside the rootfs partition changed, first near offset {pos}")
    pos += n
PY
cp -a "$ROOTFS" "$OUT.rootfs.fex"
log "rootfs written at sector $RS ($SZ bytes, md5 $b) -> $OUT; everything outside sectors $RS..$((RS+RZ)) is the source image, byte for byte"
