#!/usr/bin/env bash
# Build OpenixCard (GPL-2.0, https://github.com/YuzukiTsuru/OpenixCard) from
# source at the pinned commit. It converts Allwinner's PhoenixSuit image into a
# raw GPT image that can be written to the card with dd or Etcher.
#
#   scripts/build-openixcard.sh [--force]
#
# Host packages: cmake build-essential git libconfuse-dev pkg-config automake autoconf.
# To use a binary you already have instead: export OPENIXCARD_BIN=/path/to/OpenixCard.
. "$(dirname "$0")/lib.sh"
FORCE=0; for a in "$@"; do case $a in --force) FORCE=1 ;; *) die "unknown option $a" ;; esac; done
if [ "$FORCE" = 0 ] && [ -x "$OPENIXCARD_BIN" ]; then log "have $OPENIXCARD_BIN"; exit 0; fi
for c in cmake git make; do command -v $c >/dev/null || die "need $c"; done
pkg-config --exists libconfuse 2>/dev/null || warn "libconfuse not found by pkg-config (apt: libconfuse-dev); the build will probably fail"

base=$TOOLS_DIR/openixcard; src=$base/src; bld=$base/build
mkdir -p "$base"
if [ ! -d "$src/.git" ]; then
    log "cloning OpenixCard @ ${OPENIXCARD_COMMIT:0:12}"
    git clone --recursive "$OPENIXCARD_REPO" "$src"
fi
git -C "$src" fetch -q origin "$OPENIXCARD_COMMIT" 2>/dev/null || true
git -C "$src" checkout -q "$OPENIXCARD_COMMIT"
git -C "$src" submodule update --init --recursive -q
cmake -S "$src" -B "$bld" -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build "$bld" -j"$JOBS"
mkdir -p "$(dirname "$OPENIXCARD_BIN")"
install -m 0755 "$bld/dist/OpenixCard" "$OPENIXCARD_BIN"
log "built $OPENIXCARD_BIN ($(git -C "$src" describe --tags --always))"
