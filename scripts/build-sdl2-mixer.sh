#!/usr/bin/env bash
# SDL2_mixer 2.8.0 for /usr/magicx/lib. The library the overlay carries is TrimUI's SDL2_mixer 2.0.1,
# which cannot load Ogg Vorbis (Mix_LoadWAV on an .ogg returns NULL; PortMaster's GUI crashed on its first
# sound, spruceUI/oakMOSS#3). 2.8 decodes Ogg itself (stb_vorbis), FLAC (dr_flac) and MP3 (minimp3), and
# keeps the soname libSDL2_mixer-2.0.so.0, so the overlay's copy is replaced, not joined.
#
#   scripts/build-sdl2-mixer.sh <rootfs dir>     build.sh image runs it for boards with SDL2_MIXER=1
#
# Built with the image's own Arm GNU 13.3 toolchain (glibc 2.38) against SDL2 2.26.1's headers and the
# overlay's SDL2 binary, with the same configure options as the oakMOSS library set (docs/flip-set.md,
# scripts/build-ports-userland.sh, "sdl2mixer"). libxmp, opusfile, wavpack and libgme stay run-time loads.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
DEST=${1:?usage: scripts/build-sdl2-mixer.sh <rootfs dir>}
CROSS=$ARMGNU_DIR/bin/aarch64-none-linux-gnu-
[ -x "${CROSS}gcc" ] || die "no Arm toolchain at $ARMGNU_DIR (scripts/fetch-inputs.sh, scripts/prepare-toolchain.sh)"
for pin in "$SDL2_HDR_TARBALL $SDL2_HDR_SHA256" "$SDL2_MIXER_TARBALL $SDL2_MIXER_SHA256"; do
    set -- $pin
    [ -f "$INPUTS_DIR/$1" ] && sha256_check "$INPUTS_DIR/$1" "$2" || die "no verified $INPUTS_DIR/$1 (scripts/fetch-inputs.sh)"
done
LIBS=$DEST/usr/magicx/lib
OLD=$(readlink -f "$LIBS/libSDL2_mixer-2.0.so.0") || true
[ -f "$OLD" ] || die "no libSDL2_mixer in $LIBS to replace (the overlay carries one)"
SDL=$(readlink -f "$LIBS/libSDL2-2.0.so.0")
[ -f "$SDL" ] || die "no libSDL2 in $LIBS to link against"

SRC=$BUILDS_DIR/sdl2-mixer-src
rm -rf "$SRC"; mkdir -p "$SRC/sdl/bin"
tar -C "$SRC" -xzf "$INPUTS_DIR/$SDL2_HDR_TARBALL"
tar -C "$SRC" -xzf "$INPUTS_DIR/$SDL2_MIXER_TARBALL"
ln -s "$SDL" "$SRC/sdl/libSDL2-2.0.so.0"
# configure asks sdl2-config (found through --with-sdl-prefix, not the host's); this one answers for the headers and the binary above (nothing else of SDL2 is built).
cat > "$SRC/sdl/bin/sdl2-config" <<CFG
#!/bin/sh
for a in "\$@"; do case \$a in
    --version) echo 2.26.1 ;;
    --cflags) echo "-I$SRC/SDL2-2.26.1/include -D_REENTRANT" ;;
    --libs) echo "-L$SRC/sdl -l:libSDL2-2.0.so.0" ;;
    --prefix) echo "$SRC/sdl" ;;
esac; done
CFG
chmod +x "$SRC/sdl/bin/sdl2-config"
D=$SRC/SDL2_mixer-2.8.0
log "building SDL2_mixer 2.8.0"
( cd "$D" && ./configure --with-sdl-prefix="$SRC/sdl" --host=aarch64-none-linux-gnu CC="${CROSS}gcc" AR="${CROSS}ar" RANLIB="${CROSS}ranlib" \
      --disable-sdltest --disable-music-midi-fluidsynth --disable-static --prefix=/usr > "$SRC/configure.log" 2>&1 &&
  make -j"$(nproc)" > "$SRC/make.log" 2>&1 ) || { { tail -n 20 "$SRC/configure.log"; tail -n 20 "$SRC/make.log"; } >&2; die "SDL2_mixer did not build (logs in $SRC)"; }
NEW=$D/build/.libs/libSDL2_mixer-2.0.so.0.800.0
[ -f "$NEW" ] || NEW=$(find "$D" -name 'libSDL2_mixer-2.0.so.0.800.0' -print -quit)
[ -f "$NEW" ] || die "the build made no libSDL2_mixer-2.0.so.0.800.0"

# Checks: an aarch64 library with the right soname that needs nothing the image lacks, takes no glibc newer than
# the image's 2.38, and exports every Mix_ function the one it replaces did.
READELF=${CROSS}readelf; NM=${CROSS}nm
"$READELF" -h "$NEW" | grep -q 'Machine: *AArch64' || die "not an aarch64 library"
[ "$("$READELF" -d "$NEW" | sed -n 's/.*(SONAME).*\[\(.*\)\]/\1/p')" = libSDL2_mixer-2.0.so.0 ] || die "wrong soname"
need=$("$READELF" -d "$NEW" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p' | sort | tr '\n' ' ')
for n in $need; do case $n in libSDL2-2.0.so.0|libc.so.6|libm.so.6|libdl.so.2|libpthread.so.0|ld-linux-aarch64.so.1) ;; *) die "needs $n, which the image does not carry" ;; esac; done
top=$("$NM" -D --undefined-only "$NEW" | sed -n 's/.*@GLIBC_\([0-9.]*\)$/\1/p' | sort -V | tail -1)
[ -z "$top" ] || [ "$(printf '%s\n2.38\n' "$top" | sort -V | tail -1)" = 2.38 ] || die "needs GLIBC_$top, the image has 2.38"
missing=$(comm -23 <("$NM" -D --defined-only "$OLD" | awk '$2 ~ /^[TDBR]$/ && $3 ~ /^Mix_/ {print $3}' | sort -u) \
                   <("$NM" -D --defined-only "$NEW" | awk '$2 ~ /^[TDBR]$/ && $3 ~ /^Mix_/ {print $3}' | sort -u))
[ -z "$missing" ] || die "the old library exports what 2.8 does not: $(echo $missing | cut -c1-300)"

rm -f "$LIBS"/libSDL2_mixer-2.0.so.0*
"${CROSS}strip" --strip-unneeded -o "$LIBS/libSDL2_mixer-2.0.so.0.800.0" "$NEW"
ln -s libSDL2_mixer-2.0.so.0.800.0 "$LIBS/libSDL2_mixer-2.0.so.0"
log "SDL2_mixer 2.8.0 into usr/magicx/lib (needs: $need; glibc max ${top:-none}; the old library's Mix_ exports all present)"
