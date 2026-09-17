#!/usr/bin/env bash
# Unpack MagicX's Tina SDK drop into $SDK_DIR (sdk/lichee) and stage the extra
# source tarballs the SDK's own download step can no longer fetch.
#
#   scripts/unpack-sdk.sh [--force] [--remove-zip]
#
# Linux_SDK.zip contains mplus_a133_tina_v1.0.tar.gz split into three members.
# They are streamed straight from the zip into tar (no 11 GB intermediate copy)
# while the joined stream is md5-summed against the value printed in the SDK's
# own README. --remove-zip deletes the zip afterwards (CI runners are short of disk).
. "$(dirname "$0")/lib.sh"
FORCE=0; REMOVE=0
for a in "$@"; do case $a in --force) FORCE=1 ;; --remove-zip) REMOVE=1 ;; *) die "unknown option $a" ;; esac; done
zip=$INPUTS_DIR/$TINA_SDK_ZIP
sdkparent=$(dirname "$SDK_DIR")

if [ -f "$SDK_DIR/build/envsetup.sh" ] && [ "$FORCE" = 0 ]; then
    log "SDK already unpacked at $SDK_DIR (use --force to redo)"; exit 0
fi
[ -f "$zip" ] || die "missing $zip (scripts/fetch-inputs.sh)"
command -v unzip >/dev/null || die "need unzip"
[ "$FORCE" = 1 ] && rm -rf "$SDK_DIR"
mkdir -p "$sdkparent"
unzip -l "$zip" | grep -q 'mplus_a133_tina_v1.0.tar.gz.0' || die "$zip does not look like the mplus_a133_tina_v1.0 drop"

log "unpacking $(basename "$zip") -> $SDK_DIR (this takes a while: ~11 GB compressed, 18 GB unpacked)"
fifo=$(mktemp -u "$sdkparent/.md5fifo.XXXX"); mkfifo "$fifo"; trap 'rm -f "$fifo"' EXIT
md5sum < "$fifo" > "$sdkparent/.tar.md5" & md5pid=$!
# unzip -p emits the members in archive order (.0 .1 .2), which is the join order.
unzip -p "$zip" "$TINA_SDK_TAR_GLOB" | tee "$fifo" | tar -xz -C "$sdkparent"
wait "$md5pid"
got=$(cut -c1-32 "$sdkparent/.tar.md5")
[ "$got" = "$TINA_SDK_TAR_MD5" ] || die "joined tarball md5 $got != $TINA_SDK_TAR_MD5 (SDK README); the drop is not mplus_a133_tina_v1.0"
[ -f "$SDK_DIR/build/envsetup.sh" ] || die "tarball did not produce $SDK_DIR (expected a top-level lichee/)"

mkdir -p "$SDK_DIR/dl"
for t in "$NCURSES_TARBALL" "$GCC750_TARBALL" "$BINUTILS228_TARBALL"; do
    [ -f "$INPUTS_DIR/$t" ] && { cp -a "$INPUTS_DIR/$t" "$SDK_DIR/dl/$t"; log "staged dl/$t"; }
done
{ echo "tarball_md5=$got"; echo "unpacked=$(date -u +%FT%TZ)"; echo "zip_sha256=$(sha256_of "$zip")"; } > "$SDK_DIR/.oakmoss-sdk"
[ "$REMOVE" = 1 ] && { rm -f "$zip"; log "removed $zip"; }
log "SDK ready (md5 $got)"
