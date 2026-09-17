#!/usr/bin/env bash
# Unpack the Arm GNU Toolchain 13.3.Rel1 and build the two shims Tina's
# external-toolchain mode needs (docs/toolchain.md):
#
#   toolchains/arm-gnu-13.3-aarch64/            the toolchain as shipped by Arm
#   toolchains/arm-gnu-13.3-aarch64/tina-sysroot  ./lib + ./usr/lib with the runtime
#       libraries the SDK copies into the rootfs (Tina's CONFIG_LIBC_FILE_SPEC globs
#       expect glibc under ./lib and libstdc++/libgcc_s/libatomic under ./usr/lib;
#       Arm keeps them in lib64/, with the loader in lib/). Real copies, not
#       symlinked directories: the SDK's cp -R would ship dangling links otherwise.
#       ./lib/libc.so -> libc.so.6 satisfies Allwinner's prebuilt libresamplerate_64.so,
#       which NEEDs the unversioned name.
#   toolchains/arm-gnu-13.3-aarch64/wrap/       compiler and linker wrappers that append
#       the OpenWrt staging include/lib paths (Allwinner's own prebuilt toolchain has a
#       sysroot pre-populated with package headers, so many Tina packages never pass
#       CPPFLAGS/LDFLAGS; a clean toolchain needs them injected).
#
#   scripts/prepare-toolchain.sh [--force]
. "$(dirname "$0")/lib.sh"
FORCE=0; for a in "$@"; do case $a in --force) FORCE=1 ;; *) die "unknown option $a" ;; esac; done
tarball=$INPUTS_DIR/$ARMGNU_TARBALL
if [ "$FORCE" = 0 ] && [ -x "$ARMGNU_DIR/bin/aarch64-none-linux-gnu-gcc" ] && [ -f "$ARMGNU_DIR/tina-sysroot/lib/libc.so.6" ] && [ -x "$ARMGNU_DIR/wrap/aarch64-none-linux-gnu-gcc" ]; then
    log "toolchain already prepared at $ARMGNU_DIR"; exit 0
fi
[ -f "$tarball" ] || die "missing $tarball (scripts/fetch-inputs.sh)"
sha256_check "$tarball" "$ARMGNU_SHA256" || die "refusing to unpack an unverified toolchain"

log "unpacking $(basename "$tarball") -> $ARMGNU_DIR"
rm -rf "$ARMGNU_DIR"; mkdir -p "$ARMGNU_DIR"
tar -xJf "$tarball" -C "$ARMGNU_DIR" --strip-components=1
libc=$ARMGNU_DIR/aarch64-none-linux-gnu/libc
[ -f "$libc/lib64/libc.so.6" ] || die "unexpected toolchain layout: no $libc/lib64/libc.so.6"

sr=$ARMGNU_DIR/tina-sysroot
mkdir -p "$sr/lib" "$sr/usr/lib"
cp -a "$libc"/lib64/*.so* "$sr/lib/"
cp -a "$libc/lib/ld-linux-aarch64.so.1" "$sr/lib/"
ln -sfn libc.so.6 "$sr/lib/libc.so"
cp -a "$libc"/usr/lib64/libstdc++.so.6* "$libc/usr/lib64/libgcc_s.so.1" "$libc"/usr/lib64/libatomic.so.1* "$sr/usr/lib/"

wrap=$ARMGNU_DIR/wrap
mkdir -p "$wrap"
install -m 0755 "$OAKMOSS_ROOT/sdk-patches/toolchain/arm-gnu-wrapper.sh" "$wrap/wrapper.sh"
for t in gcc g++ c++ cpp ld ld.bfd; do ln -sfn wrapper.sh "$wrap/aarch64-none-linux-gnu-$t"; done

ver=$("$ARMGNU_DIR/bin/aarch64-none-linux-gnu-gcc" --version | head -1)
glibc=$(strings "$sr/lib/libc.so.6" | grep -m1 'GNU C Library' || true)
log "ready: $ver"; log "sysroot: $glibc"
