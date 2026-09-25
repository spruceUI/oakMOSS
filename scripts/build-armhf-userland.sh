#!/usr/bin/env bash
# Build card-side userland (binaries and shared libraries) for spruce's PortMaster
# port environment on the armhf line (the Miyoo A30), with the A30 toolchain.
#
#   scripts/build-armhf-userland.sh [package ...]      (no args = every package)
#
# WHY THIS TOOLCHAIN. The output is ordinary armhf glibc userland - not A30-specific
# beyond the ABI. What matters is the glibc it is built against: arm-a30-linux-gnueabihf
# (GCC 13.2, Buildroot 2024.02.1, glibc 2.23 sysroot) is the fleet's armhf floor - see
# TOOLCHAINS.md - so what it produces needs at most GLIBC_2.23 and loads on every spruce
# armhf device. This is the armhf mirror of scripts/build-ports-userland.sh, same package
# set (build list #8, PORTMASTER-EXPANSION-PLAN.md), same provenance contract.
#
# THE TOOLCHAIN ONLY EXISTS INSIDE DOCKER. Unlike the aarch64 lane, the A30 toolchain
# is not unpacked on the host - it lives at /opt/a30 inside the `cores-armhf:latest`
# image that cores-experimental already builds from Dockerfile.armhf.base (see
# TOOLCHAINS.md). Nothing is installed on the host and the image is never modified:
# this script re-execs itself inside `docker run --rm`, with the oakMOSS checkout
# bind-mounted read-only (so it can read itself, lib.sh and inputs/userland) and only
# the output directory bind-mounted read-write. See the re-exec block below.
#
# RPATH DIFFERS FROM THE AARCH64 LANE. The Tina SDK's aarch64 wrapper unconditionally
# appends its own absolute rpath to every link, which build-ports-userland.sh then
# shrinks in place with elf-set-rpath.py (a rewrite that needs an existing DT_RPATH
# to shrink into). The arm-a30 toolchain injects no rpath at all - confirmed empirically,
# and also unusable here: $ORIGIN cannot be threaded through LDFLAGS cleanly, because
# libtool's own rpath validation (it wants what looks like an absolute path) silently
# drops a literal "$ORIGIN" argument instead of embedding it, corrupting the link line
# for anything after it. So this lane builds with no rpath at all, then sets one with
# `patchelf --force-rpath --set-rpath`, which the same cores-armhf image already ships
# (/opt/a30/bin/patchelf) - --force-rpath asks for DT_RPATH rather than DT_RUNPATH, to
# match what the aarch64 lane ships (DT_RPATH also propagates to a library's own
# transitive dependencies, which DT_RUNPATH does not).
#
# NEUTRAL BUILD PATH. Same reason as the aarch64 lane: zstd's assert carries its
# __FILE__ through realpath, and FFmpeg's avutil_configuration() bakes in the whole
# configure line verbatim. $OUT is a real, timestamped host path (bind-mounted at the
# same path inside the container, so relative host layout would otherwise leak straight
# into shipped files), so all building happens under a fixed symlink alias instead - see
# BUILD_ALIAS below - exactly as build-ports-userland.sh does with /tmp/oakmoss-ports-userland.
#
# GNULIB Y2038 TRAP. grep, tar, coreutils and findutils all probe at configure time
# whether the host can represent timestamps past January 2038, and refuse to build a
# 32-bit binary with a 32-bit time_t once they decide it can (this docker host can).
# The A30's glibc 2.23 predates the 64-bit-time_t symbols a fixed build would need,
# so every one of the four is built with --disable-year2038.
#
# Output: <out>/{bin,lib}/ + SHA256SUMS + BUILD-INFO + logs/. The tree is copied as-is
# to spruce/armhf/{bin,lib} in the spruceOS-armhf-userland worktree: the armhf mirror
# of spruce/aarch64, for the A30 line once PortMaster is switched on there
# (DEVICE_SUPPORTS_PORTMASTER stays false on the A30 until that decision is made).
# Sources come from $INPUTS_DIR/userland - the SAME tarballs the aarch64 lane uses -
# and are sha256-checked against inputs/userland/SHA256SUMS. Neither that file, nor
# inputs/userland/urls.txt, nor build-ports-userland.sh is touched by this script.
. "$(dirname "$0")/lib.sh"

SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
DOCKER_IMAGE_ARMHF=${DOCKER_IMAGE_ARMHF:-cores-armhf:latest}

OUT=${OUT:-$BUILDS_DIR/$(stamp)-armhf-userland}
SRC_DIR=${SRC_DIR:-$INPUTS_DIR/userland}
mkdir -p "$OUT"/{bin,lib,logs,work}

# ---- re-exec inside the A30 toolchain image ------------------------------------
# Everything after this block runs a SECOND time, inside `docker run`, which is how
# it reaches /opt/a30. OAKMOSS_ROOT is bind-mounted read-only at its own host path
# (so $SELF and lib.sh resolve exactly as they do here, and inputs/userland is
# reachable through it); $OUT is bind-mounted read-write at its own path, nested
# under the read-only mount - Docker resolves that nesting per-mount, so $OUT stays
# writable and everything else under OAKMOSS_ROOT stays read-only, proven with a
# throwaway container before this script was written. The image itself is never
# built, committed, or written to - only these two bind mounts, and --rm discards
# the container on exit.
if [ "${OAKMOSS_IN_ARMHF_IMAGE:-}" != 1 ]; then
    command -v docker >/dev/null || die "docker not found on host"
    docker image inspect "$DOCKER_IMAGE_ARMHF" >/dev/null 2>&1 \
        || die "no local image $DOCKER_IMAGE_ARMHF (build it in cores-experimental: docker build -f Dockerfile.armhf.base -t $DOCKER_IMAGE_ARMHF .)"
    log "re-exec inside $DOCKER_IMAGE_ARMHF (out: $OUT)"
    exec docker run --rm \
        -e OAKMOSS_IN_ARMHF_IMAGE=1 -e JOBS="$JOBS" -e OUT="$OUT" \
        -v "$OAKMOSS_ROOT:$OAKMOSS_ROOT:ro" \
        -v "$OUT:$OUT" \
        "$DOCKER_IMAGE_ARMHF" \
        bash "$SELF" "$@"
fi

# ---- from here on we are inside the container -----------------------------------
BUILD_ALIAS=/build                          # fixed and neutral: see header comment
mkdir -p "$OUT/work"
ln -sfn "$OUT/work" "$BUILD_ALIAS"
WORK=$BUILD_ALIAS

TC=/opt/a30/bin
TRIPLET=arm-a30-linux-gnueabihf
[ -x "$TC/$TRIPLET-gcc" ] || die "no A30 toolchain at $TC (expected inside $DOCKER_IMAGE_ARMHF)"

STAGE=$WORK/staging                         # headers + .so for later packages
export PATH="$TC:$PATH"
export CC=$TRIPLET-gcc CXX=$TRIPLET-g++ AR=$TRIPLET-ar RANLIB=$TRIPLET-ranlib
export STRIP=$TRIPLET-strip LD=$TRIPLET-ld NM=$TRIPLET-nm
export CPPFLAGS="-I$STAGE/usr/include"
# __NO_STRING_INLINES: this glibc 2.23 sysroot's <bits/string2.h> defines several
# functions (strndup among them) as __extension__ inline shims under -O2, and GCC
# 13.2's own gnulib-driven redeclaration of the same functions (coreutils/findutils,
# "for -Wmismatched-dealloc", __GNUC__>=11) collides with them at parse time
# ("expected identifier or '(' before '__extension__'" in lib/string.h). The sysroot
# header names this exact opt-out itself; nothing here needs the inline fast paths.
export CFLAGS="-O2 -fPIC -D__NO_STRING_INLINES -I$STAGE/usr/include"
export LDFLAGS="-L$STAGE/usr/lib -Wl,-rpath-link,$STAGE/usr/lib"
export PKG_CONFIG_PATH="$STAGE/usr/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$STAGE/usr/lib/pkgconfig"

# No rpath is embedded at link time (see header comment); patchelf sets it afterwards.
BIN_RPATH='$ORIGIN/../lib'                  # spruce/armhf/bin looks in spruce/armhf/lib
LIB_RPATH='$ORIGIN'
set_rpath() { patchelf --force-rpath --set-rpath "$1" "$2"; }

CU_TOOLS="env sort mv cp stat timeout shuf tac sha1sum sha256sum md5sum"
LIB_PKGS="zlib xz zstd libbsd pcre2 libpng libjpegturbo libwebp libogg libvorbis libsndfile libevdev libuuid ncurses5 smartcols"
TOOL_PKGS="grep tar unzip coreutils findutils"
# Best-effort, last, allowed to fail (see build_one and the final loop): not a
# build-stopping error if these do not fit in the time available.
LAST_PKGS="lame libvpx ffmpeg"
ALL_PKGS="$LIB_PKGS $TOOL_PKGS $LAST_PKGS"
PKGS=${*:-$ALL_PKGS}

mkdir -p "$OUT"/{bin,lib,logs} "$WORK" "$STAGE"

src() {  # src <tarball> <unpacked-dir> : verify, unpack into $WORK, echo the dir
    local glob=$1 dir=$2 tb
    tb=$SRC_DIR/$glob
    [ -f "$tb" ] || die "source missing: $tb (see inputs/userland/urls.txt)"
    (cd "$SRC_DIR" && grep " $(basename "$tb")\$" SHA256SUMS | sha256sum -c --status -) \
        || die "sha256 mismatch: $tb"
    rm -rf "${WORK:?}/$dir"
    tar -C "$WORK" -xf "$tb"
    [ -d "$WORK/$dir" ] || die "unpacked tree is not $WORK/$dir"
    echo "$WORK/$dir"
}

ship_lib() {  # ship_lib <soname> ... : copy from the staging prefix, keep the symlink chain
    local so real
    for so in "$@"; do
        real=$(readlink -f "$STAGE/usr/lib/$so") || die "not staged: $so"
        [ -f "$real" ] || die "not staged: $so"
        cp -f "$real" "$OUT/lib/$so"
        "$STRIP" --strip-unneeded "$OUT/lib/$so"
        set_rpath "$LIB_RPATH" "$OUT/lib/$so"
    done
}

ship_bin() {  # ship_bin <path> <name>
    cp -f "$1" "$OUT/bin/$2"
    "$STRIP" --strip-unneeded "$OUT/bin/$2"
    set_rpath "$BIN_RPATH" "$OUT/bin/$2"
}

build_one() {
    local p=$1 d
    log "=== $p"
    case $p in
    zlib)   # build dependency only; every armhf device already has libz.so.1. FLOOR RULE (as on the aarch64
            # lane, 2026-09-23): the OLDEST zlib a firmware serves ahead of the card - 1.2.8 on the A30 - so
            # nothing built here can import a symbol that board lacks (inflateValidate arrived in 1.2.9).
        d=$(src zlib-1.2.8.tar.gz zlib-1.2.8)
        (cd "$d" && CHOST=$TRIPLET ./configure --prefix=/usr >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null) ;;
    xz)
        d=$(src xz-5.4.7.tar.gz xz-5.4.7)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --disable-static \
            --disable-xz --disable-xzdec --disable-lzmadec --disable-lzmainfo \
            --disable-scripts --disable-doc --disable-nls >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null)
        ship_lib liblzma.so.5 ;;
    zstd)
        d=$(src zstd-1.5.6.tar.gz zstd-1.5.6)
        # LIB_SRCDIR=./ keeps the source paths relative, same reason as the aarch64
        # lane: its default resolves through realpath, which would carry $BUILD_ALIAS's
        # *target* (the real, timestamped $OUT/work) into an assert's __FILE__ instead
        # of the neutral alias path.
        (cd "$d/lib" && make -j"$JOBS" CC="$CC" AR="$AR" LIB_SRCDIR=./ libzstd >/dev/null &&
         make PREFIX=/usr DESTDIR="$STAGE" install-shared install-includes install-pc >/dev/null)
        ship_lib libzstd.so.1 ;;
    libbsd)
        d=$(src libbsd-0.10.0.tar.xz libbsd-0.10.0)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --disable-static >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null)
        ship_lib libbsd.so.0 ;;
    pcre2)
        d=$(src pcre2-10.44.tar.gz pcre2-10.44)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --disable-static \
            --enable-pcre2-8 --disable-pcre2-16 --disable-pcre2-32 >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null)
        ship_lib libpcre2-8.so.0 ;;
    libpng)     # needs zlib staged first
        d=$(src libpng-1.6.43.tar.xz libpng-1.6.43)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --disable-static >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null)
        ship_lib libpng16.so.16 ;;
    ncurses5)   # libncurses.so.5 (ABI 5, terminfo merged in, narrow chars): spruce/bin/nano asks for exactly
                # that soname and no armhf rootfs in the fleet has it (Mini, A30: fleet census 2026-09-23).
        d=$(src ncurses-6.5.tar.gz ncurses-6.5)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --with-abi-version=5 --with-shared --without-normal \
            --without-debug --without-ada --without-cxx --without-cxx-binding --without-manpages --without-progs \
            --without-tests --disable-widec --with-default-terminfo-dir=/usr/share/terminfo --disable-db-install >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install.libs >/dev/null)
        ship_lib libncurses.so.5 ;;
    smartcols)  # libsmartcols.so.1: spruce/bin/rfkill (util-linux) asks for it; no armhf rootfs has it.
                # util-linux built with every program off and only this library on.
        d=$(src util-linux-2.39.4.tar.xz util-linux-2.39.4)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --disable-static --disable-all-programs \
            --enable-libsmartcols --disable-libuuid --disable-libblkid --disable-libmount --disable-libfdisk \
            --without-python --without-systemd --without-ncurses --without-tinfo --disable-nls --disable-bash-completion >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null &&
         mv -f "$STAGE"/lib/libsmartcols.so* "$STAGE/usr/lib/")   # util-linux installs its libraries under /lib
        ship_lib libsmartcols.so.1 ;;
    libjpegturbo)   # libjpeg.so.62
        d=$(src libjpeg-turbo-1.5.3.tar.gz libjpeg-turbo-1.5.3)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --disable-static >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null)
        ship_lib libjpeg.so.62 ;;
    libwebp)    # 0.5.x: soname libwebp.so.6, same version the aarch64 lane ships
        d=$(src libwebp-0.5.2.tar.gz libwebp-0.5.2)
        (cd "$d" && LDFLAGS="$LDFLAGS -lm" ./configure --host=$TRIPLET --prefix=/usr \
            --disable-static --disable-libwebpextras --disable-libwebpdecoder >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null)
        ship_lib libwebp.so.6 ;;
    libogg)
        d=$(src libogg-1.3.5.tar.xz libogg-1.3.5)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --disable-static >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null)
        ship_lib libogg.so.0 ;;
    libvorbis)  # needs libogg staged first
        d=$(src libvorbis-1.3.7.tar.xz libvorbis-1.3.7)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --disable-static \
            --disable-docs --disable-examples --disable-oggtest >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null)
        ship_lib libvorbis.so.0 libvorbisfile.so.3 libvorbisenc.so.2 ;;
    libsndfile) # WAV/AIFF/etc only, same as the aarch64 lane
        d=$(src libsndfile-1.2.2.tar.xz libsndfile-1.2.2)
        (cd "$d" && LDFLAGS="$LDFLAGS -lm" ./configure --host=$TRIPLET --prefix=/usr --disable-static \
            --disable-external-libs --disable-mpeg --disable-alsa --disable-sqlite \
            --disable-full-suite --disable-test-coverage >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null)
        ship_lib libsndfile.so.1 ;;
    libevdev)
        d=$(src libevdev-1.13.3.tar.xz libevdev-1.13.3)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --disable-static \
            --disable-documentation >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null)
        ship_lib libevdev.so.2 ;;
    libuuid)
        d=$(src util-linux-2.39.4.tar.xz util-linux-2.39.4)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --disable-static \
            --disable-all-programs --enable-libuuid --disable-nls --without-python \
            --disable-bash-completion --disable-makeinstall-chown --disable-makeinstall-setuid \
            --disable-asciidoc >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null)
        # util-linux installs the shared object under /lib and leaves only the dev
        # symlink in /usr/lib; ship_lib reads the staging /usr/lib, so put it there.
        cp -af "$STAGE"/lib/libuuid.so.1* "$STAGE/usr/lib/"
        ship_lib libuuid.so.1 ;;
    grep)   # needs pcre2 staged first, for `grep -P`. --disable-year2038: gnulib's
            # time_t probe refuses a 32-bit time_t on a host that itself supports
            # post-2038 timestamps (this build host does); the A30's glibc 2.23 has
            # no 64-bit-time_t symbols to link against regardless, so 32-bit it is.
        d=$(src grep-3.11.tar.gz grep-3.11)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr \
            --disable-nls --enable-perl-regexp --disable-year2038 >/dev/null &&
         make -j"$JOBS" >/dev/null)
        ship_bin "$d/src/grep" grep ;;
    tar)
        d=$(src tar-1.35.tar.gz tar-1.35)
        (cd "$d" && FORCE_UNSAFE_CONFIGURE=1 \
            ./configure --host=$TRIPLET --prefix=/usr --disable-nls --disable-year2038 >/dev/null &&
         make -j"$JOBS" >/dev/null)
        ship_bin "$d/src/tar" tar ;;
    unzip)  # -U__DATE__: keep rebuilds byte-identical (GCC 13.2 still has no SOURCE_DATE_EPOCH here)
        d=$(src unzip60.tar.gz unzip60)
        (cd "$d" && make -f unix/Makefile generic \
            CC="$CC" LD="$CC" AS="$CC -c" STRIP=true \
            LOC="-DLARGE_FILE_SUPPORT -DUNICODE_SUPPORT -DUNICODE_WCHAR -DUTF8_MAYBE_NATIVE -DNO_LCHMOD -DDATE_FORMAT=DF_YMD -DNOMEMCPY -Wno-builtin-macro-redefined -U__DATE__" \
            >/dev/null)
        ship_bin "$d/unzip" unzip ;;
    coreutils)  # 9.1, matching the aarch64 lane; no known armhf build issue like aarch64's getdents one.
                # The Buildroot sysroot carries OpenSSL 3, libattr, libacl, libcap and gmp, and
                # configure links whatever it finds: the first build's md5sum/sha*sum/sort needed
                # libcrypto.so.3, which no spruce device has. Every optional library is named off.
                # FORCE_UNSAFE_CONFIGURE=1: this whole lane runs as root inside the container.
        d=$(src coreutils-9.1.tar.xz coreutils-9.1)
        (cd "$d" && FORCE_UNSAFE_CONFIGURE=1 ./configure --host=$TRIPLET --prefix=/usr \
            --disable-nls --without-selinux --enable-no-install-program=stdbuf --disable-year2038 \
            --with-openssl=no --disable-xattr --disable-acl --disable-libcap --without-gmp \
            fu_cv_sys_stat_statfs2_bsize=yes gl_cv_host_operating_system=Linux >/dev/null &&
         make -j"$JOBS" >/dev/null)
        for t in $CU_TOOLS; do ship_bin "$d/src/$t" "$t"; done ;;
    findutils)  # its own gnulib snapshot spells the Y2038 opt-out differently (no --disable-year2038)
        d=$(src findutils-4.8.0.tar.xz findutils-4.8.0)
        (cd "$d" && TIME_T_32_BIT_OK=yes ./configure --host=$TRIPLET --prefix=/usr \
            --disable-nls gl_cv_func_wcwidth_works=yes >/dev/null &&
         make -j"$JOBS" >/dev/null)
        ship_bin "$d/find/find" find
        ship_bin "$d/xargs/xargs" xargs ;;
    lame)
        d=$(src lame-3.100.tar.gz lame-3.100)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --disable-static \
            --disable-frontend --disable-nls >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null)
        ship_lib libmp3lame.so.0 ;;
    libvpx)
        d=$(src libvpx-1.13.1.tar.gz libvpx-1.13.1)
        # glibc 2.23 still has a separate libpthread, so -lpthread is not implied.
        # No NEON by default on this toolchain (see TOOLCHAINS.md) - disabled explicitly
        # rather than relying on configure's autodetection under a cross build.
        (cd "$d" && LDFLAGS="$LDFLAGS -lpthread" CROSS=$TRIPLET- ./configure --target=armv7-linux-gcc --prefix=/usr \
            --enable-pic --enable-shared --disable-static --disable-examples \
            --disable-tools --disable-docs --disable-unit-tests --disable-neon --disable-neon-asm >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null)
        ship_lib libvpx.so.8 ;;
    ffmpeg) # needs lame + libvpx staged first for the encoders it links against
            # --disable-autodetect: the sysroot has xcb, ALSA, SDL2, bzip2 and OpenSSL, and the first
            # build's libavdevice/libavformat linked them; the A30 has no libxcb or libbz2 on any
            # port path. zlib is the one system library this set is allowed (the aarch64 set too).
        d=$(src ffmpeg-4.4.5.tar.xz ffmpeg-4.4.5)
        (cd "$d" && ./configure --enable-cross-compile --arch=arm --cpu=cortex-a7 --target-os=linux \
            --cross-prefix=$TRIPLET- --prefix=/usr --enable-shared --disable-static \
            --disable-programs --disable-doc --disable-debug --enable-gpl \
            --disable-autodetect --enable-zlib \
            --enable-libmp3lame --enable-libvpx \
            --extra-cflags="-I$STAGE/usr/include" --extra-ldflags="-L$STAGE/usr/lib" \
            --extra-libs="-lpthread -lm" \
            >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null)
        ship_lib libavcodec.so.58 libavformat.so.58 libavutil.so.56 \
                 libswresample.so.3 libswscale.so.5 libavfilter.so.7 libavdevice.so.58 \
                 libpostproc.so.55 ;;
    *) die "unknown package: $p" ;;
    esac
}

FAILED=""
for p in $PKGS; do
    if build_one "$p" > "$OUT/logs/$p.log" 2>&1; then
        log "$p ok"
    else
        case " $LAST_PKGS " in
        *" $p "*)
            # Allowed to fail: report and move on, per the task's instructions.
            warn "$p failed (best-effort, not fatal): see $OUT/logs/$p.log"
            tail -15 "$OUT/logs/$p.log" >&2
            FAILED="$FAILED $p" ;;
        *)
            tail -30 "$OUT/logs/$p.log" >&2
            die "$p failed (log: $OUT/logs/$p.log)" ;;
        esac
    fi
done

# ---- report -------------------------------------------------------------------
{
    echo "oakmoss=$(oakmoss_version)"
    echo "built=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "toolchain=$("$TC/$TRIPLET-gcc" --version | head -1)"
    echo "toolchain_glibc=$(strings /opt/a30/$TRIPLET/sysroot/lib/libc-2.23.so | grep -m1 'release version' | tr -d '\n')"
    echo "packages=$PKGS"
    [ -n "$FAILED" ] && echo "not_built=$FAILED"
} > "$OUT/BUILD-INFO"
( cd "$OUT" && find bin lib -type f | sort | xargs sha256sum > SHA256SUMS )

log "glibc floor per shipped file (>2.23 fails the build)"
bad=0
{
    for f in "$OUT"/bin/* "$OUT"/lib/*; do
        [ -f "$f" ] || continue
        v=$(readelf -V "$f" 2>/dev/null | grep -oE 'GLIBC_2\.[0-9]+' | sort -t. -k2 -n | tail -1)
        printf '%-40s %s\n' "$(basename "$f")" "${v:-none}"
        case "$v" in
            GLIBC_2.2[4-9]|GLIBC_2.[3-9][0-9]) echo "TOO NEW: $f needs $v" >&2; bad=1 ;;
        esac
    done
} | tee "$OUT/logs/glibc-versions.txt" >&2
[ "$bad" = 0 ] || die "some artifacts need a glibc newer than the A30's 2.23 floor"

# The glibc floor says nothing about WHICH libraries a file asks for. A cross sysroot that is
# richer than the device (this one is a full Buildroot) leaks straight into DT_NEEDED through
# configure's auto-detection. Everything a shipped file needs must be in this tree, or be one of
# the few libraries every spruce armhf rootfs has - the same list the aarch64 set keeps to.
log "checking that nothing needs a library outside this tree and the base system"
SYSTEM_OK="libc.so.6 libm.so.6 libdl.so.2 libpthread.so.0 librt.so.1 ld-linux-armhf.so.3 libgcc_s.so.1 libstdc++.so.6 libz.so.1"
bad=0
for f in "$OUT"/bin/* "$OUT"/lib/*; do
    [ -f "$f" ] || continue
    for n in $(readelf -d "$f" 2>/dev/null | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p'); do
        [ -e "$OUT/lib/$n" ] && continue
        case " $SYSTEM_OK " in *" $n "*) continue ;; esac
        echo "STRAY DEPENDENCY: $(basename "$f") needs $n" >&2; bad=1
    done
done
[ "$bad" = 0 ] || die "a shipped file needs a library that is neither shipped nor part of the base system"

log "checking for build-host paths in shipped files"
leaked=0
for f in "$OUT"/bin/* "$OUT"/lib/*; do
    [ -f "$f" ] || continue
    if strings "$f" | grep -qE "$OAKMOSS_ROOT|/root/|/home/[a-z]+/"; then
        echo "HOST PATH LEAKED: $f" >&2
        strings "$f" | grep -E "$OAKMOSS_ROOT|/root/|/home/[a-z]+/" >&2
        leaked=1
    fi
done
[ "$leaked" = 0 ] || die "a build-host path leaked into a shipped artifact"

[ -z "$FAILED" ] || warn "not built (best-effort, see logs):$FAILED"
log "done: $OUT"
