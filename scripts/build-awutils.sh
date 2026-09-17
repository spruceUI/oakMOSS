#!/usr/bin/env bash
# Build awutils' `awimage` from source at a pinned commit, with the one patch the
# XU20 stock firmware needs: its PhoenixSuit image carries header version 0x0415,
# which OpenixCard refuses and unpatched awutils misreads (it wrote a hundred
# gigabytes of garbage before anyone noticed). The patch treats 0x0415 as the
# 0x0300 layout, which is what it is.
#
#   scripts/build-awutils.sh            -> tools/awutils/bin/awimage
. "$(dirname "$0")/lib.sh"
SRC=$TOOLS_DIR/awutils-src; BIN=$TOOLS_DIR/awutils/bin
if [ -x "$BIN/awimage" ] && [ "$(cat "$BIN/.commit" 2>/dev/null)" = "$AWUTILS_COMMIT" ]; then log "have awimage ($AWUTILS_COMMIT)"; exit 0; fi
command -v gcc >/dev/null || die "need a C compiler (build-essential)"
rm -rf "$SRC"; mkdir -p "$TOOLS_DIR"
git clone -q "$AWUTILS_REPO" "$SRC"
git -C "$SRC" checkout -q "$AWUTILS_COMMIT"
git -C "$SRC" apply "$OAKMOSS_ROOT/tools-patches/awutils-imagewty-0x415.patch" || die "the 0x0415 patch no longer applies at $AWUTILS_COMMIT"
make -C "$SRC" awimage >/dev/null
mkdir -p "$BIN"; install -m 0755 "$SRC/awimage" "$BIN/awimage"; echo "$AWUTILS_COMMIT" > "$BIN/.commit"
log "awimage built: $BIN/awimage"
