#!/usr/bin/env bash
# DIAGNOSTIC SD1 image: a built image with its rootfs re-packed to carry the
# colour-staged hand-off (diag/runmagicx-diag.sh replaces /usr/magicx/bin/runmagicx.sh,
# the original stays as runmagicx.sh.orig) and fbfill. Boot progress becomes
# visible without a console (green: rc.local reached, blue: card mounted,
# red: no card after 30 s then poweroff, yellow: the hand-off returned) and a
# full snapshot (mounts, power_supply, input bitmaps, sdio ids, modules, dmesg)
# lands on /mnt/UDISK/spruce-base-boot.log on SD1 and Saves/spruce/base-boot.log
# on the user card. diag/decode-input-bitmap.py reads that log.
#
#   scripts/make-diag-image.sh <sd1.img> <rootfs.fex> <out.img> [src:dest ...]
#
# EXPERIMENTS="zero40-radio ..." installs diag/experiments/<name>.sh under
# /usr/magicx/diag/experiments; the hand-off runs each once the card is up. A
# normal diagnostic image carries none: an experiment is bench work for one
# board, kept in its own lane so it never rides along by accident.
#
# Extra src:dest pairs are copied into the unpacked root before repacking
# (dest relative to /, e.g. /tmp/libfoo.so.0:usr/lib/libfoo.so.0). Both a
# build's own image and a hybrid image can be the source.
. "$(dirname "$0")/lib.sh"
SRC_IMG=${1:?sd1.img}; ROOTFS=${2:?rootfs.fex}; OUT_IMG=${3:?out.img}; shift 3; EXTRA=("$@")
squashfs_tools
EXPERIMENTS=${EXPERIMENTS:-}
D=$OAKMOSS_ROOT/diag
# fbfill is built from source with the Arm toolchain (static, so it needs nothing from the rootfs).
FBFILL=$BUILDS_DIR/fbfill
if [ ! -x "$FBFILL" ]; then
    CC=$ARMGNU_DIR/bin/aarch64-none-linux-gnu-gcc
    [ -x "$CC" ] || die "need the Arm toolchain to build fbfill (scripts/prepare-toolchain.sh)"
    mkdir -p "$BUILDS_DIR"; "$CC" -static -Os -s -o "$FBFILL" "$D/fbfill.c"; log "built fbfill"
fi
need_tmp_space 1024
W=$(mktemp -d "${TMPDIR:-/tmp}/oakmoss-diag.XXXX"); trap 'rm -rf "$W"' EXIT
log "unpack $(basename "$ROOTFS")"
"$UNSQUASHFS" -n -d "$W/root" "$ROOTFS" >/dev/null 2>"$W/unsq.err" || true
grep -v -i 'could not\|xattr\|mknod\|permission' "$W/unsq.err" | head -5 >&2 || true
[ -f "$W/root/usr/magicx/bin/runmagicx.sh" ] || die "no runmagicx.sh in the rootfs"
cp "$W/root/usr/magicx/bin/runmagicx.sh" "$W/root/usr/magicx/bin/runmagicx.sh.orig"
install -m 0755 "$D/runmagicx-diag.sh" "$W/root/usr/magicx/bin/runmagicx.sh"
install -m 0755 "$FBFILL" "$W/root/usr/magicx/bin/fbfill"
for x in $EXPERIMENTS; do
    [ -f "$D/experiments/$x.sh" ] || die "no such experiment: $x (diag/experiments/)"
    mkdir -p "$W/root/usr/magicx/diag/experiments"
    install -m 0755 "$D/experiments/$x.sh" "$W/root/usr/magicx/diag/experiments/$x.sh"; log "experiment installed: $x"
done
for pair in "${EXTRA[@]}"; do
    src=${pair%%:*}; dst=${pair#*:}
    mkdir -p "$W/root/$(dirname "$dst")"; cp -a "$src" "$W/root/$dst"; log "added $dst"
done
log "repack (xz, 256 KiB blocks, root-owned, as the SDK's image.mk does)"
"$MKSQUASHFS" "$W/root" "$W/rootfs.fex" -noappend -root-owned -comp xz -b 262144 -processors "$JOBS" \
    -p '/dev d 755 0 0' -p '/dev/console c 600 0 0 5 1' >/dev/null
"$OAKMOSS_ROOT/scripts/replace-rootfs.sh" "$SRC_IMG" "$W/rootfs.fex" "$OUT_IMG"
{
  echo "kind=diag"; echo "built=$(stamp)"; echo "oakmoss=$(oakmoss_version)"; echo "source_image=$SRC_IMG"; echo "source_rootfs=$ROOTFS"
  echo "extras=${EXTRA[*]:-none}"; echo "experiments=${EXPERIMENTS:-none}"
  echo "what_it_shows=green = rc.local reached; blue = /mnt/SDCARD mounted (hand-off follows); red = no card after 30 s, then poweroff; yellow = the hand-off returned, then poweroff after 10 s"
  echo "logs=/mnt/UDISK/spruce-base-boot.log on SD1; Saves/spruce/base-boot.log and Saves/spruce/base-handoff.log on the user card"
} > "$(dirname "$OUT_IMG")/BUILD-INFO-diag.txt"
log "diag image ready: $OUT_IMG"
