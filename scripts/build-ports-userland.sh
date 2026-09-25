#!/usr/bin/env bash
# Build card-side userland (binaries and shared libraries) for spruce's PortMaster
# port environment. By default with the SDK's own vendor toolchain; a second toolchain
# at the fleet's glibc ceiling is selectable (PORTS_TOOLCHAIN, see the block below lib.sh).
#
#   scripts/build-ports-userland.sh [package ...]      (no args = every package)
#   PORTS_TOOLCHAIN=armgnu103 scripts/build-ports-userland.sh [package ...]
#
# WHY THE VENDOR TOOLCHAIN IS THE DEFAULT. The output is ordinary aarch64 glibc userland -
# it is not board-specific and not even A133P-specific. What matters is the glibc it is
# built against: the SDK's prebuilt Linaro GCC 6.4 targets glibc 2.23, so what it
# produces needs at most GLIBC_2.17 and loads on every spruce aarch64 device on any
# firmware, including the TrimUI units at glibc 2.33 and the Miyoo Flip at 2.38.
#
# The `ext` lane (Arm GNU 13.3, glibc 2.38) must NOT be used for this. Anything built
# against glibc 2.34 or newer imports __libc_start_main@GLIBC_2.34 and cannot start on
# the TrimUI devices; spruce already ships an `unzip` and a `liblzma.so.5` like that in
# spruce/flip (muOS builds made for the Flip, April 2025), which is what this set replaces.
# GCC 13's libstdc++ is also above what TrimUI, the XX line and the Miniloong carry.
#
# Unlike the rest of oakMOSS this runs on the host, not in the container: the SDK
# toolchain is a prebuilt x86_64 Linux cross-compiler and these are ordinary
# autotools/make packages.
#
# Output: <out>/{bin,lib}/ + SHA256SUMS + BUILD-INFO + logs/. The tree is copied as-is
# to spruce/aarch64/{bin,lib} on the spruceOS card: one shared aarch64 userland,
# first on every aarch64 platform's port path.
# Sources come from $INPUTS_DIR/userland and are sha256-checked against
# inputs/userland/SHA256SUMS.
. "$(dirname "$0")/lib.sh"

# TWO TOOLCHAINS, ONE RECIPE LIST (2026-09-21, see spruce-lib-audit TOOLCHAINS.md).
#   PORTS_TOOLCHAIN=tina       (default) the vendor Linaro GCC 6.4 / glibc 2.23. Every file it makes needs
#                        at most GLIBC_2.17, so it runs on any firmware a device can be carrying.
#   PORTS_TOOLCHAIN=armgnu103  Arm GNU Toolchain 10.3-2021.07: GCC 10.3.1 / glibc 2.33, which is the
#                        HIGHEST floor the aarch64 fleet allows (the four TrimUI units are at 2.33,
#                        and anything built against 2.34+ imports __libc_start_main@GLIBC_2.34).
#                        Output that calls the stat family needs exactly GLIBC_2.33: zero margin on
#                        TrimUI, and it will not start on a Smart Pro below firmware 1.0.4 (2.29).
#                        It builds what GCC 6.4 cannot (OpenAL Soft 1.23.1).
PORTS_TOOLCHAIN=${PORTS_TOOLCHAIN:-tina}
case "$PORTS_TOOLCHAIN" in
    tina)      OUT_SUFFIX="" ;;
    armgnu103) OUT_SUFFIX="-glibc233" ;;
    *) die "unknown PORTS_TOOLCHAIN=$PORTS_TOOLCHAIN (tina | armgnu103)" ;;
esac

OUT=${OUT:-$BUILDS_DIR/$(stamp)-ports-userland$OUT_SUFFIX}
WORK_REAL=${WORK:-$OUT/work}
SRC_DIR=${SRC_DIR:-$INPUTS_DIR/userland}

# Build under a fixed, neutral path. Several packages bake their build directory
# into the artifact - FFmpeg keeps the whole configure line in
# avutil_configuration(), zstd carries an assert's __FILE__ - and the real one is
# under the builder's home directory. A symlink costs nothing and keeps that out
# of files that ship.
BUILD_ALIAS=${BUILD_ALIAS:-/tmp/oakmoss-ports-userland}
mkdir -p "$WORK_REAL"
ln -sfn "$WORK_REAL" "$BUILD_ALIAS"
WORK=$BUILD_ALIAS

case "$PORTS_TOOLCHAIN" in
tina)
    TC=$SDK_DIR/prebuilt/gcc/linux-x86/aarch64/toolchain-sunxi-glibc/toolchain
    TRIPLET=aarch64-openwrt-linux-gnu
    TC_LIBDIR=$TC/lib64                     # where the toolchain keeps its own target runtime libs
    TC_LIBC=$TC/lib/libc.so.6
    EXTRA_LDFLAGS=""                        # the wrapper adds an rpath to every link by itself
    OPENAL_VER=1.19.1 ;;
armgnu103)
    TC=$TOOLCHAINS_DIR/arm-gnu-10.3-aarch64
    TRIPLET=aarch64-none-linux-gnu
    TC_LIBDIR=$TC/$TRIPLET/lib64
    TC_LIBC=$TC/$TRIPLET/libc/lib64/libc.so.6
    # This toolchain adds no rpath, and elf-set-rpath.py can only SHRINK one that exists, so every
    # link gets a long placeholder to be rewritten to $ORIGIN afterwards. --disable-new-dtags asks
    # for DT_RPATH, which is what the Tina lane ships (it also covers a library's own dependencies).
    EXTRA_LDFLAGS="-Wl,--disable-new-dtags -Wl,-rpath,/tmp/oakmoss-rpath-placeholder-0000000000000000000000000000"
    OPENAL_VER=1.23.1 ;;
esac
# COMMANDS THE FLEET DOES NOT HAVE (2026-09-21). Only in the armgnu103 lane, so the default lane's output
# stays byte-identical. Chosen from what PortMaster calls bare, measured against the 20 lab profiles:
#   getconf   absent on every unit. PortMaster's probe-based device_info.txt asks it for the glibc version
#             first; its fallback paths miss Debian multiarch, so the seven H700 units would read 0.0.0
#             and lose every port with a min_glibc.
#   od        the same script's first choice for reading a devicetree cell (hexdump and xxd are fallbacks).
#   lscpu     absent on 19 of 20. device_info.txt 0.1.x (what ships today) sets DEVICE_CPU from it.
#   taskset losetup zramctl   util-linux is built for libuuid anyway. zramctl: absent everywhere, eleven
#             ports call it bare; losetup: absent on Brick, Brick Pro and Smart Pro; taskset: 17 of 20.
#             (hexdump is not switchable on its own under --disable-all-programs, and every aarch64
#             unit has the BusyBox applet; it is only the probe's second choice after od.)
#   dos2unix  fifteen ports call it bare; the MagicX images have the BusyBox applet but no link to it.
case "$PORTS_TOOLCHAIN" in
    armgnu103) EXTRA_CU_TOOLS="od"; EXTRA_PKGS="getconf utilprogs dos2unix" ;;
    *)         EXTRA_CU_TOOLS="";   EXTRA_PKGS="" ;;
esac
[ -x "$TC/bin/$TRIPLET-gcc" ] || die "no $PORTS_TOOLCHAIN toolchain at $TC"

STAGE=$WORK/staging                        # headers + .so for later packages
export STAGING_DIR=$WORK/.openwrt-staging  # only to silence the gcc wrapper
export PATH="$TC/bin:$PATH"
export CC=$TRIPLET-gcc CXX=$TRIPLET-g++ AR=$TRIPLET-ar RANLIB=$TRIPLET-ranlib
export STRIP=$TRIPLET-strip LD=$TRIPLET-ld NM=$TRIPLET-nm
export CPPFLAGS="-I$STAGE/usr/include"
export CFLAGS="-O2 -fPIC -I$STAGE/usr/include"
export LDFLAGS="-L$STAGE/usr/lib -Wl,-rpath-link,$STAGE/usr/lib${EXTRA_LDFLAGS:+ $EXTRA_LDFLAGS}"
export PKG_CONFIG_PATH="$STAGE/usr/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$STAGE/usr/lib/pkgconfig"

# The toolchain wrapper appends its own absolute path to every link's rpath and
# has no switch to stop it, so each artifact is rewritten after the fact: a
# binary looks beside itself for its libraries, a library looks next to its
# siblings, and the builder's directory never ships. See elf-set-rpath.py.
BIN_RPATH='$ORIGIN/../lib'          # spruce/aarch64/bin looks in spruce/aarch64/lib
LIB_RPATH='$ORIGIN'
set_rpath() { "$OAKMOSS_ROOT/scripts/elf-set-rpath.py" "$1" "$2"; }

CU_TOOLS="env sort mv cp stat timeout shuf tac sha1sum sha256sum md5sum${EXTRA_CU_TOOLS:+ $EXTRA_CU_TOOLS}"
ALL_PKGS="zlib xz zstd libbsd pcre2 grep tar unzip coreutils findutils lame libvpx ffmpeg libjpegturbo libjpegturbo8 libpng libwebp libogg libvorbis libsndfile libevdev libuuid alsa flac theora modplug physfs openal mpg123 libatomic pcre openssl ncurses boost ltdl speexdsp pulseaudio interpose curl libdrm freetypefloor harfbuzz libffi glib fluidsynth sdl12 sdlimage12 sdlttf freetype${EXTRA_PKGS:+ $EXTRA_PKGS}"
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

cmake_cross() {  # cmake_cross <srcdir> [-D...] : configure into <srcdir>/build for the vendor toolchain
    local src=$1; shift
    cat > "$WORK/toolchain.cmake" <<EOF
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_C_COMPILER $TC/bin/$TRIPLET-gcc)
set(CMAKE_CXX_COMPILER $TC/bin/$TRIPLET-g++)
set(CMAKE_FIND_ROOT_PATH $STAGE/usr)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
EOF
    # The toolchain file names the compilers; CC/CFLAGS and friends must NOT leak in through the
    # environment, because a CMake project that builds native helper tools while cross-compiling
    # (openal-soft's bin2h and bsincgen) would pick the cross compiler up for those too and then
    # try to run aarch64 programs on the build host.
    env -u CC -u CXX -u AR -u RANLIB -u LD -u NM -u STRIP -u CFLAGS -u CPPFLAGS -u LDFLAGS \
    cmake -S "$src" -B "$src/build" -DCMAKE_TOOLCHAIN_FILE="$WORK/toolchain.cmake" \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=lib \
        -DCMAKE_SKIP_RPATH=ON -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DCMAKE_C_FLAGS="$CFLAGS" -DCMAKE_CXX_FLAGS="$CFLAGS" -DCMAKE_SHARED_LINKER_FLAGS="$LDFLAGS" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" "$@"
}

cmake_make() {  # cmake_make <srcdir> [make args] : same clean environment as cmake_cross
    local src=$1; shift
    env -u CC -u CXX -u AR -u RANLIB -u LD -u NM -u STRIP -u CFLAGS -u CPPFLAGS -u LDFLAGS \
        make -C "$src/build" "$@"
}

build_one() {
    local p=$1 d
    log "=== $p"
    case $p in
    zlib)   # build dependency only; every device already has libz.so.1. FLOOR RULE: this is the OLDEST zlib
            # a device firmware serves ahead of the card (1.2.8 on the TrimUI and MagicX rootfs, 2026-09-23), so
            # nothing built here can import a symbol those boards lack (inflateValidate arrived in 1.2.9).
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
        # LIB_SRCDIR=./ keeps the source paths relative. Its default is
        # $(dir $(realpath ...)), and realpath resolves the build symlink, so an
        # assert's __FILE__ would carry the builder's real directory into the .so
        # (libzstd.mk:24).
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
    grep)   # the only tool that can do `grep -P`; BusyBox has no PCRE at all
        d=$(src grep-3.11.tar.gz grep-3.11)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr \
            --disable-nls --enable-perl-regexp >/dev/null &&
         make -j"$JOBS" >/dev/null)
        ship_bin "$d/src/grep" grep ;;
    tar)    # BusyBox tar has no -z/-j/-J; GNU tar shells out to gzip/bzip2/xz
        d=$(src tar-1.35.tar.gz tar-1.35)
        (cd "$d" && FORCE_UNSAFE_CONFIGURE=1 \
            ./configure --host=$TRIPLET --prefix=/usr --disable-nls >/dev/null &&
         make -j"$JOBS" >/dev/null)
        ship_bin "$d/src/tar" tar ;;
    unzip)  # replaces spruce/flip/bin/unzip, which needs GLIBC_2.34.
            # No -DUSE_BZIP2: that needs bzlib headers, and the bzip2 compression
            # method is vanishingly rare in the zips ports download.
            # Its Makefile ignores LDFLAGS and its generated `flags` file overrides LF2 and LFLAGS1,
            # so the only way to plant the placeholder rpath (armgnu103) is through LD itself.
            # -U__DATE__: unzip prints its compile date in `unzip -v`; GCC 6.4 has no
            # SOURCE_DATE_EPOCH, so without this every rebuild differs by one byte.
        d=$(src unzip60.tar.gz unzip60)
        (cd "$d" && make -f unix/Makefile generic \
            CC="$CC" LD="$CC${EXTRA_LDFLAGS:+ $EXTRA_LDFLAGS}" AS="$CC -c" STRIP=true \
            LOC="-DLARGE_FILE_SUPPORT -DUNICODE_SUPPORT -DUNICODE_WCHAR -DUTF8_MAYBE_NATIVE -DNO_LCHMOD -DDATE_FORMAT=DF_YMD -DNOMEMCPY -Wno-builtin-macro-redefined -U__DATE__" \
            >/dev/null)
        ship_bin "$d/unzip" unzip ;;
    coreutils)  # measured BusyBox 1.27.2 rejections on the A133P units:
                # `env -u` (which is how PortMaster starts its message dialog -
                # 375 ports call pm_message), `mv -T`, `cp -RT`, `sort -V`; and
                # stat, timeout, shuf and tac are not built in at all.
                # 9.1, not the Debian 11 8.32: 8.32's src/ls.c calls
                # SYS_getdents unconditionally and aarch64 has only getdents64,
                # so that tree does not build for this target at all.
        d=$(src coreutils-9.1.tar.xz coreutils-9.1)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr \
            --disable-nls --without-selinux --enable-no-install-program=stdbuf \
            fu_cv_sys_stat_statfs2_bsize=yes gl_cv_host_operating_system=Linux >/dev/null &&
         make -j"$JOBS" >/dev/null)
        for t in $CU_TOOLS; do ship_bin "$d/src/$t" "$t"; done ;;
    findutils)  # `find -quit`, `-not`, `-empty` and `-delete` are all rejected
        d=$(src findutils-4.8.0.tar.xz findutils-4.8.0)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr \
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
        # glibc 2.23 still has a separate libpthread, so -lpthread is not implied
        (cd "$d" && LDFLAGS="$LDFLAGS -lpthread" CROSS=$TRIPLET- ./configure --target=arm64-linux-gcc --prefix=/usr \
            --enable-pic --enable-shared --disable-static --disable-examples \
            --disable-tools --disable-docs --disable-unit-tests >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null)
        ship_lib libvpx.so.8 ;;
    ffmpeg) # libavcodec.so.58 / libavformat.so.58 / libavutil.so.56 + friends
        d=$(src ffmpeg-4.4.5.tar.xz ffmpeg-4.4.5)
        (cd "$d" && ./configure --enable-cross-compile --arch=aarch64 --target-os=linux \
            --cross-prefix=$TRIPLET- --prefix=/usr --enable-shared --disable-static \
            --disable-programs --disable-doc --disable-debug --enable-gpl \
            --enable-libmp3lame --enable-libvpx \
            --extra-cflags="-I$STAGE/usr/include" --extra-ldflags="-L$STAGE/usr/lib" \
            --extra-libs="-lpthread -lm" \
            >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null)
        ship_lib libavcodec.so.58 libavformat.so.58 libavutil.so.56 \
                 libswresample.so.3 libswscale.so.5 libavfilter.so.7 libavdevice.so.58 \
                 libpostproc.so.55 ;;
    libjpegturbo)   # libjpeg.so.62, which no spruce device has today
        d=$(src libjpeg-turbo-1.5.3.tar.gz libjpeg-turbo-1.5.3)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --disable-static >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null)
        ship_lib libjpeg.so.62 ;;
    libjpegturbo8)  # the same source again for the jpeg8 ABI. spruce ships one
                    # in flip/lib, but only the Brick and Brick Pro have that
                    # directory on the port library path - the Smart Pro does not.
        d=$(src libjpeg-turbo-1.5.3.tar.gz libjpeg-turbo-1.5.3)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --disable-static \
            --with-jpeg8 >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null)
        ship_lib libjpeg.so.8 ;;
    libpng)     # missing from every TrimUI rootfs; the CFW guide asks for it
        d=$(src libpng-1.6.43.tar.xz libpng-1.6.43)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --disable-static >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null)
        ship_lib libpng16.so.16 ;;
    libwebp)        # 0.5.x is the release whose soname is libwebp.so.6, which is what
                    # the CFW guide names and what 55 ports carry their own copy of
        d=$(src libwebp-0.5.2.tar.gz libwebp-0.5.2)
        # -lm: the example tools link libwebp's math calls, and glibc 2.23 keeps
        # them in libm; --disable-libwebp{demux,mux,...} keeps the build to the
        # one library that is actually wanted.
        (cd "$d" && LDFLAGS="$LDFLAGS -lm" ./configure --host=$TRIPLET --prefix=/usr \
            --disable-static --disable-libwebpextras --disable-libwebpdecoder >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null)
        ship_lib libwebp.so.6 ;;
    libogg)     # gmtoolkit's oggdec and rlvm need vorbisfile; no MagicX rootfs has it
        d=$(src libogg-1.3.5.tar.xz libogg-1.3.5)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --disable-static >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null)
        ship_lib libogg.so.0 ;;
    libvorbis)
        d=$(src libvorbis-1.3.7.tar.xz libvorbis-1.3.7)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --disable-static \
            --disable-docs --disable-examples --disable-oggtest >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null)
        ship_lib libvorbis.so.0 libvorbisfile.so.3 libvorbisenc.so.2 ;;
    libsndfile)     # rlvm's core; missing on the H700 BaseOS rootfs. WAV/AIFF/etc only:
                    # the external codecs (FLAC, opus, mpeg) would drag in more libraries
        d=$(src libsndfile-1.2.2.tar.xz libsndfile-1.2.2)
        (cd "$d" && LDFLAGS="$LDFLAGS -lm" ./configure --host=$TRIPLET --prefix=/usr --disable-static \
            --disable-external-libs --disable-mpeg --disable-alsa --disable-sqlite \
            --disable-full-suite --disable-test-coverage >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null)
        ship_lib libsndfile.so.1 ;;
    libevdev)       # weston's libexec_weston -> libinput -> libevdev; absent on the H700 BaseOS
        d=$(src libevdev-1.13.3.tar.xz libevdev-1.13.3)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --disable-static \
            --disable-documentation >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null)
        ship_lib libevdev.so.2 ;;
    libuuid)        # Xwayland's fontconfig needs it; every copy on the card is a 2.38 build
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
    getconf)    # Not built: the toolchain ships glibc's own target getconf, and it is the one program
                # here that has to come from glibc. It needs GLIBC_2.17 and libc alone, carries no
                # rpath, and answers from the RUNNING libc (confstr), so it reports the device's
                # glibc, not the 2.33 it was built beside. The floor and closure gates below still
                # check it like everything else.
        [ "$PORTS_TOOLCHAIN" = armgnu103 ] || die "getconf comes from the armgnu103 sysroot only"
        cp -f "$TC/$TRIPLET/libc/usr/bin/getconf" "$OUT/bin/getconf"
        "$STRIP" --strip-unneeded "$OUT/bin/getconf" ;;
    utilprogs)  # util-linux programs, libsmartcols linked in statically so nothing new ships in lib/.
                # Re-unpacks the tree the libuuid package used; that one's output is already staged.
        d=$(src util-linux-2.39.4.tar.xz util-linux-2.39.4)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --disable-shared --enable-static \
            --disable-all-programs --enable-libsmartcols --enable-lscpu \
            --enable-schedutils --enable-losetup --enable-zramctl --disable-nls --without-python \
            --without-systemd --without-udev --without-ncurses --without-ncursesw --without-tinfo \
            --without-readline --without-cap-ng --without-libz --without-user --without-selinux \
            --without-audit --without-econf --disable-bash-completion --disable-makeinstall-chown \
            --disable-makeinstall-setuid --disable-asciidoc >/dev/null &&
         make -j"$JOBS" lscpu taskset losetup zramctl >/dev/null)
        for t in lscpu taskset losetup zramctl; do ship_bin "$d/$t" "$t"; done ;;
    dos2unix)
        d=$(src dos2unix-7.5.2.tar.gz dos2unix-7.5.2)
        (cd "$d" && make -j"$JOBS" CC="$CC" ENABLE_NLS= LDFLAGS_USER="$LDFLAGS" dos2unix >/dev/null)
        ship_bin "$d/dos2unix" dos2unix ;;
    alsa)   # build dependency only: headers for openal's ALSA backend, which it dlopens at
            # run time. Every device has its own libasound.so.2; this one does not ship.
        d=$(src alsa-lib-1.1.9.tar.bz2 alsa-lib-1.1.9)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --disable-static --disable-python \
            --disable-alisp --disable-old-symbols >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null) ;;
    flac)   # libFLAC.so.8 is the soname ports and the CFW guide name; 1.4 moved to .so.12
        d=$(src flac-1.3.4.tar.xz flac-1.3.4)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --disable-static --disable-cpplibs \
            --disable-doxygen-docs --disable-xmms-plugin --disable-examples --disable-programs \
            --with-ogg="$STAGE/usr" >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null)
        ship_lib libFLAC.so.8 ;;
    theora)
        d=$(src libtheora-1.1.1.tar.bz2 libtheora-1.1.1)
        # 2009's config.sub has never heard of aarch64; take a current pair from libogg's tree
        # (built earlier in every full run) or from the host's automake.
        for f in config.sub config.guess; do
            if [ -f "$WORK/libogg-1.3.5/$f" ]; then cp -f "$WORK/libogg-1.3.5/$f" "$d/$f"
            else cp -f "$(ls /usr/share/automake-*/$f | tail -1)" "$d/$f"; fi
        done
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --disable-static --disable-examples \
            --disable-spec --disable-oggtest --disable-vorbistest --disable-sdltest \
            --with-ogg="$STAGE/usr" --with-vorbis="$STAGE/usr" >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null)
        ship_lib libtheoradec.so.1 libtheoraenc.so.1 libtheora.so.0 ;;
    modplug)
        d=$(src libmodplug-0.8.9.0.tar.gz libmodplug-0.8.9.0)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --disable-static >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null)
        ship_lib libmodplug.so.1 ;;
    physfs) # the first CMake package in this lane; see cmake_cross below
        d=$(src physfs-3.0.2.tar.gz physfs-release-3.0.2)
        (cmake_cross "$d" -DPHYSFS_BUILD_STATIC=OFF -DPHYSFS_BUILD_TEST=OFF -DPHYSFS_BUILD_DOCS=OFF >/dev/null &&
         cmake_make "$d" -j"$JOBS" >/dev/null && cmake_make "$d" DESTDIR="$STAGE" install >/dev/null)
        ship_lib libphysfs.so.1 ;;
    openal) # ALSA only, loaded with dlopen, so the device's own libasound.so.2 is what runs.
        case "$OPENAL_VER" in
        1.19.1) # The last C release, and the newest one GCC 6.4 builds (1.20 went C++11, 1.21 C++14).
                # GCC 10 cannot build it: it defines globals in headers and GCC 10 is -fno-common.
            d=$(src openal-soft-1.19.1.tar.gz openal-soft-openal-soft-1.19.1)
            (cmake_cross "$d" -DALSOFT_UTILS=OFF -DALSOFT_EXAMPLES=OFF -DALSOFT_TESTS=OFF -DALSOFT_CONFIG=OFF \
                -DALSOFT_HRTF_DEFS=OFF -DALSOFT_AMBDEC_PRESETS=OFF -DALSOFT_NO_CONFIG_UTIL=ON \
                -DALSOFT_DLOPEN=ON -DALSOFT_REQUIRE_ALSA=ON -DALSOFT_BACKEND_OSS=OFF -DALSOFT_BACKEND_PULSEAUDIO=OFF \
                -DALSOFT_BACKEND_JACK=OFF -DALSOFT_BACKEND_PORTAUDIO=OFF -DALSOFT_BACKEND_SNDIO=OFF \
                -DALSOFT_BACKEND_SOLARIS=OFF -DALSOFT_BACKEND_QSA=OFF -DALSOFT_BACKEND_SDL2=OFF \
                -DALSOFT_BACKEND_WAVE=OFF >/dev/null &&
             cmake_make "$d" -j"$JOBS" >/dev/null && cmake_make "$d" DESTDIR="$STAGE" install >/dev/null) ;;
        1.23.1) # Built with GCC 10.3 it needs only GLIBC_2.27 and GLIBCXX_3.4.22 - under every device,
                # TrimUI's GLIBCXX_3.4.28 included - and it is newer than any stock copy (1.21.1 on the SPS).
            d=$(src openal-soft-1.23.1.tar.bz2 openal-soft-1.23.1)
            (cmake_cross "$d" -DALSOFT_UTILS=OFF -DALSOFT_EXAMPLES=OFF -DALSOFT_TESTS=OFF -DALSOFT_NO_CONFIG_UTIL=ON \
                -DALSOFT_DLOPEN=ON -DALSOFT_REQUIRE_ALSA=ON -DALSOFT_BACKEND_OSS=OFF -DALSOFT_BACKEND_PULSEAUDIO=OFF \
                -DALSOFT_BACKEND_JACK=OFF -DALSOFT_BACKEND_PORTAUDIO=OFF -DALSOFT_BACKEND_SNDIO=OFF \
                -DALSOFT_BACKEND_SOLARIS=OFF -DALSOFT_BACKEND_SDL2=OFF -DALSOFT_BACKEND_WAVE=OFF \
                -DALSOFT_BACKEND_PIPEWIRE=OFF -DALSOFT_BACKEND_OBOE=OFF -DALSOFT_BACKEND_OPENSL=OFF >/dev/null &&
             cmake_make "$d" -j"$JOBS" >/dev/null && cmake_make "$d" DESTDIR="$STAGE" install >/dev/null) ;;
        esac
        ship_lib libopenal.so.1 ;;
    mpg123) # with libatomic and openal this retires spruce/h700/ports-lib64, which was never H700-specific
        d=$(src mpg123-1.32.9.tar.bz2 mpg123-1.32.9)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --disable-static --with-audio=dummy \
            --with-cpu=aarch64 --disable-components --enable-libmpg123 >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null)
        ship_lib libmpg123.so.0 ;;
    # ---- 2026-09-22: the libraries the card still could not resolve somewhere, built here so that
    # spruce/aarch64/lib (last on every 64-bit board's LD_LIBRARY_PATH since the same day, first on the
    # port path) is the one place they live. Evidence: CFW/RootUI/pixel2/PIXEL2-LIBRARIES.md and the
    # 2026-09-22 dedupe audit. Nothing here needs more than the lane's own glibc.
    pcre)   # pcre1. spruce/bin64/wget and Emu/SCUMMVM's glib link libpcre.so.1; neither twigUI rootfs nor
            # the H700 BaseOS has it (BaseOS carries only pcre3's libpcre.so.3).
        d=$(src pcre-8.45.tar.bz2 pcre-8.45)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --disable-static --enable-utf \
            --enable-unicode-properties --disable-cpp --disable-pcregrep-libz --disable-pcregrep-libbz2 >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null)
        ship_lib libpcre.so.1 ;;
    openssl)    # OpenSSL 1.1.1. spruce/bin64/wget and spruce/flip/lib's libcurl.so.4 / libzip.so.5 link
                # libssl.so.1.1; the H700 BaseOS and both Pixel 2 firmwares carry OpenSSL 3 on the path and
                # libcrypto.so.1.1 at most in a compat directory. CC is unset: Configure prefixes its own
                # default compiler with --cross-compile-prefix and would double the triplet otherwise.
        d=$(src openssl-1.1.1w.tar.gz openssl-1.1.1w)
        (cd "$d" && env -u CC -u CXX -u AR -u RANLIB -u LD -u NM -u STRIP \
            ./Configure linux-aarch64 --prefix=/usr --openssldir=/etc/ssl shared no-tests no-async \
            --cross-compile-prefix=$TRIPLET- $CFLAGS $LDFLAGS >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install_sw >/dev/null)
        ship_lib libcrypto.so.1.1 libssl.so.1.1 ;;
    ncurses)    # libncursesw.so.6 + libtinfo.so.6: what spruce/bin64/rnano links (Emu/N64's own libncurses.so.6
                # needs the tinfo half). The TrimUI, Flip and Miniloong rootfs have neither; MagicX has both.
                # Wide build with the terminfo library under its plain name, no programs, no database.
        d=$(src ncurses-6.5.tar.gz ncurses-6.5)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --with-build-cc=gcc --with-shared --without-normal \
            --without-debug --without-ada --without-cxx --without-cxx-binding --without-manpages --without-progs \
            --without-tests --without-tack --with-termlib=tinfo --disable-db-install --disable-stripping \
            --enable-widec --with-abi-version=6 >/dev/null &&
         make -j"$JOBS" libs >/dev/null && make DESTDIR="$STAGE" install.libs >/dev/null)
        ship_lib libtinfo.so.6 libncursesw.so.6 ;;
    boost)  # libboost_filesystem.so.1.71.0: Emu/SATURN/yabasanshiro links that exact soname and no rootfs
            # has it. bootstrap builds b2 for the host, so the cross compiler must not leak into it.
        d=$(src boost_1_71_0.tar.bz2 boost_1_71_0)
        (cd "$d" && env -u CC -u CXX -u CFLAGS -u CPPFLAGS -u LDFLAGS ./bootstrap.sh --with-libraries=filesystem >/dev/null &&
         { printf 'using gcc : 10.3 : %s :' "$TC/bin/$TRIPLET-g++"; printf ' <cxxflags>%s' -O2 -fPIC;
           for f in $LDFLAGS; do printf ' <linkflags>%s' "$f"; done; printf ' ;\n'; } > user-config.jam &&
         ./b2 -d0 -j"$JOBS" --user-config=user-config.jam toolset=gcc-10.3 target-os=linux link=shared variant=release \
            --layout=system --no-cmake-config --with-filesystem --prefix="$STAGE/usr" --libdir="$STAGE/usr/lib" install)
        ship_lib libboost_filesystem.so.1.71.0 ;;
    ltdl)   # build dependency only: pulseaudio's configure wants ltdl.h, the client libraries never reference it
        d=$(src libtool-2.4.7.tar.xz libtool-2.4.7)
        (cd "$d/libltdl" && ./configure --host=$TRIPLET --prefix=/usr --disable-static --enable-ltdl-install >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null) ;;
    speexdsp)   # libspeexdsp.so.1: the EasyRPG core links it (pulseaudio's configure wants it too)
        d=$(src speexdsp-1.2.1.tar.gz speexdsp-1.2.1)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --disable-static --disable-examples >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null)
        ship_lib libspeexdsp.so.1 ;;
    pulseaudio) # libpulse.so.0, libpulse-simple.so.0, libpulsecommon-13.99.so: the client set Moonlight's
                # binary links. The card carried Ubuntu 20.04's copies in spruce/flip/lib (and libpulse.so.0
                # again in Moonlight's own libs), which the Pixel 2 never lists; one lane-built set replaces them.
                # Client libraries only: no daemon, no modules, no X11/dbus/glib/alsa; 13.99 parses JSON itself
                # and the trio needs nothing beyond libsndfile at run time. The dist tarball's
                # configure insists on intltool even with --disable-nls; the stub answers its version probe.
        d=$(src pulseaudio-13.99.1.tar.xz pulseaudio-13.99.1)
        mkdir -p "$WORK/intltool-stub"
        for t in intltool-update intltool-merge intltool-extract; do
            printf '#!/bin/sh\ncase "$1" in --version) echo "%s (intltool) 0.51.0" ;; esac\nexit 0\n' "$t" > "$WORK/intltool-stub/$t"
            chmod +x "$WORK/intltool-stub/$t"
        done
        (cd "$d" && PATH="$WORK/intltool-stub:$PATH" ./configure --host=$TRIPLET --prefix=/usr --disable-static \
            --disable-nls --disable-x11 --disable-tests --disable-samplerate --disable-oss-output --disable-oss-wrapper \
            --disable-alsa --disable-solaris --disable-waveout --disable-glib2 --disable-gtk3 --disable-gsettings \
            --disable-gconf --disable-avahi --disable-jack --disable-asyncns --disable-tcpwrap --disable-lirc \
            --disable-dbus --disable-bluez5 --disable-udev --disable-hal-compat --disable-openssl --disable-orc \
            --disable-manpages --disable-systemd-daemon --disable-systemd-login --disable-systemd-journal \
            --disable-webrtc-aec --disable-adrian-aec --disable-neon-opt --without-caps --with-database=simple \
            --without-fftw --without-soxr --disable-default-build-tests >/dev/null &&
         make -j"$JOBS" -C src libpulsecommon-13.99.la libpulse.la libpulse-simple.la >/dev/null &&
         for l in libpulsecommon-13.99.so libpulse.so.0 libpulse-simple.so.0; do
             cp -f "src/.libs/$(readlink "src/.libs/$l" 2>/dev/null || echo "$l")" "$STAGE/usr/lib/$l"
         done)
        ship_lib libpulse.so.0 libpulse-simple.so.0 libpulsecommon-13.99.so ;;
    interpose)  # libinterpose.aarch64.so: PortMaster's LD_PRELOAD shim, linked by the gptokeyb2 builds spruce
                # ships in Emu/N64 and Emu/JAGUAR. Built from the gptokeyb2 sources (interpose/, one C file).
        d=$(src gptokeyb2-2026.02.28-2309.tar.gz gptokeyb2-2026.02.28-2309)
        (cd "$d/interpose" && $CC $CFLAGS -shared -fPIC -Wl,-soname,libinterpose.aarch64.so \
            -o "$STAGE/usr/lib/libinterpose.aarch64.so" interpose.c -lpthread -ldl $LDFLAGS)
        ship_lib libinterpose.aarch64.so ;;
    # ---- second pass, 2026-09-22 (fleet census over the 19 lab dumps): what the EasyRPG core, the Gallery
    # and the E-Reader still could not resolve on the TrimUI, Flip and MagicX rootfs.
    curl)   # libcurl.so.4 for consumers built against a curl newer than a firmware's (flycast wants the
            # curl_mime_* API of 7.56+, the TrimUI Brick/Brick Pro/Smart Pro rootfs has 7.54.1). Minimal:
            # the lane's OpenSSL 1.1.1, the floor zlib, nothing else - no idn2/psl/nghttp2/brotli/zstd/ldap.
        d=$(src curl-8.7.1.tar.xz curl-8.7.1)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --disable-static --with-openssl="$STAGE/usr" \
            --with-zlib="$STAGE/usr" --without-libpsl --without-libidn2 --without-nghttp2 --without-brotli --without-zstd \
            --without-librtmp --without-libssh2 --without-libgsasl --disable-ldap --disable-ldaps --disable-rtsp \
            --disable-manual --disable-docs --disable-verbose >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null && rm -f "$STAGE/usr/lib/libcurl.la")
        ship_lib libcurl.so.4 ;;
    libdrm) # libdrm.so.2: kmsgrab (spruce/bin64) asks for it and 31 of the lab boards' firmwares have none. Generic
            # ioctl wrapper over the kernel's DRM - not a GPU vendor library. 2.4.99 is the last autotools release.
        d=$(src libdrm-2.4.99.tar.bz2 libdrm-2.4.99)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --disable-static --disable-intel --disable-radeon \
            --disable-amdgpu --disable-nouveau --disable-vmwgfx --disable-omap-experimental-api --disable-exynos-experimental-api \
            --disable-freedreno --disable-tegra-experimental-api --disable-vc4 --disable-etnaviv-experimental-api \
            --disable-cairo-tests --disable-manpages --disable-valgrind --disable-udev >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null && rm -f "$STAGE/usr/lib/libdrm.la")
        ship_lib libdrm.so.2 ;;
    freetypefloor)  # FLOOR RULE: the oldest freetype a firmware serves ahead of the card (2.6.1 on TrimUI and
                    # MagicX). Staged FIRST so harfbuzz and SDL_ttf link against its API: harfbuzz built against
                    # 2.10 imports FT_Get_Var_Blend_Coordinates / FT_Done_MM_Var, which those boards lack
                    # (EasyRPG core, symbol pass 2026-09-23). Not shipped; the shipped 2.10.4 is built last and
                    # overwrites this copy in staging. A copy is kept for the floor gate at the end.
        d=$(src freetype-2.6.1.tar.bz2 freetype-2.6.1)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --disable-static --with-harfbuzz=no --with-bzip2=no \
            --with-png=no --with-zlib=no >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null &&
         sed -i "s|^prefix=.*|prefix=$STAGE/usr|" "$STAGE/usr/bin/freetype-config" &&
         rm -f "$STAGE/usr/lib/libfreetype.la" &&
         mkdir -p "$WORK/floor" && cp -f "$(readlink -f "$STAGE/usr/lib/libfreetype.so.6")" "$WORK/floor/libfreetype.so.6") ;;
    freetype)   # harfbuzz and SDL_ttf link it; shipped so the tree stays self-contained (every rootfs has one).
                # Built AFTER its consumers (see freetypefloor): they must not see this newer API.
        d=$(src freetype-2.10.4.tar.xz freetype-2.10.4)
        # freetype-config is kept (2.10 drops it by default) and pointed at the staging prefix: SDL_ttf's
        # configure knows no other way to find FreeType, and the .pc's /usr paths would name the host's
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --disable-static --with-harfbuzz=no --with-brotli=no \
            --with-bzip2=no --with-png=yes --with-zlib=yes --enable-freetype-config >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null &&
         sed -i "s|^prefix=.*|prefix=$STAGE/usr|" "$STAGE/usr/bin/freetype-config" &&
         rm -f "$STAGE/usr/lib/libfreetype.la")   # its dependency_libs name /usr/lib/libpng16.la, the host's
        ship_lib libfreetype.so.6 ;;
    harfbuzz)   # libharfbuzz.so.0: the EasyRPG core links it; no TrimUI, Flip or MagicX rootfs has it
        d=$(src harfbuzz-2.6.8.tar.xz harfbuzz-2.6.8)
        (cd "$d" && FREETYPE_CFLAGS="-I$STAGE/usr/include/freetype2" FREETYPE_LIBS="-L$STAGE/usr/lib -lfreetype" \
            ./configure --host=$TRIPLET --prefix=/usr --disable-static --with-glib=no --with-gobject=no \
            --with-cairo=no --with-icu=no --with-graphite2=no --with-fontconfig=no --with-freetype=yes >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null)
        ship_lib libharfbuzz.so.0 ;;
    libffi) # build dependency only (glib's gobject)
        d=$(src libffi-3.3.tar.gz libffi-3.3)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --disable-static --disable-docs >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null && rm -f "$STAGE/usr/lib/libffi.la") ;;
    glib)   # libglib-2.0.so.0 + libgthread-2.0.so.0: fluidsynth's only dependencies. 2.56 is the last release
            # whose tarball still carries a generated configure (2.58's ships only meson). Internal PCRE, no
            # libmount/selinux/xattr; the cross answers configure cannot test are the well-known glibc ones.
        d=$(src glib-2.56.4.tar.xz glib-2.56.4)
        # glib's gettext check insists on the host having msgfmt even when libc provides gettext; the
        # stub only creates the catalogue file it is asked for (empty), and no catalogue ships from here
        mkdir -p "$WORK/gettext-stub"
        printf '#!/bin/sh\nout=; while [ $# -gt 0 ]; do case "$1" in -o) out=$2; shift;; esac; shift; done; [ -n "$out" ] && : > "$out"; exit 0\n' > "$WORK/gettext-stub/msgfmt"
        chmod +x "$WORK/gettext-stub/msgfmt"
        (cd "$d" && PATH="$WORK/gettext-stub:$PATH" PKG_CONFIG_SYSROOT_DIR="$STAGE" glib_cv_stack_grows=no glib_cv_uscore=no \
            ac_cv_func_posix_getpwuid_r=yes ac_cv_func_posix_getgrgid_r=yes \
            ./configure --host=$TRIPLET --prefix=/usr --disable-static --with-pcre=internal --disable-libmount \
            --disable-selinux --disable-fam --disable-xattr --disable-libelf --disable-dtrace --disable-systemtap \
            --disable-man --disable-gtk-doc --disable-installed-tests --disable-always-build-tests >/dev/null &&
         PATH="$WORK/gettext-stub:$PATH" make -j"$JOBS" -C glib >/dev/null &&
         PATH="$WORK/gettext-stub:$PATH" make -j"$JOBS" -C gthread >/dev/null &&
         make -C glib DESTDIR="$STAGE" install >/dev/null && make -C gthread DESTDIR="$STAGE" install >/dev/null &&
         install -Dm644 glib-2.0.pc "$STAGE/usr/lib/pkgconfig/glib-2.0.pc" &&
         install -Dm644 gthread-2.0.pc "$STAGE/usr/lib/pkgconfig/gthread-2.0.pc" &&
         sed -i 's/ -lpcre//g' "$STAGE/usr/lib/pkgconfig/glib-2.0.pc" &&   # the internal PCRE is inside libglib
         rm -f "$STAGE"/usr/lib/libg*-2.0.la)   # glib and gthread only: gio does not build against glibc 2.33
                                               # with GCC 10, and nothing here needs gobject or gio
        ship_lib libglib-2.0.so.0 libgthread-2.0.so.0 ;;
    fluidsynth) # libfluidsynth.so.3: the EasyRPG core links it (RetroArch/.retroarch/cores64/easyrpg_libretro.so);
                # only Emu/EASYRPG/lib-Flip carried one, an Ubuntu build the Flip alone lists. Synth only: no audio
                # drivers, no MIDI drivers, no network, so it needs nothing beyond glib.
        d=$(src fluidsynth-2.3.7.tar.gz fluidsynth-2.3.7)
        # its FindGLib2 appends -lpcre whenever it cannot prove glib links pcre2; this glib carries its own
        # PCRE inside libglib and needs neither
        sed -i 's/list(APPEND _glib2_link_libraries "pcre")/true()/' "$d/cmake_admin/FindGLib2.cmake"
        export PKG_CONFIG_SYSROOT_DIR="$STAGE"
        cmake_cross "$d" -DBUILD_SHARED_LIBS=ON -Denable-libsndfile=OFF -Denable-alsa=OFF -Denable-pulseaudio=OFF \
            -Denable-pipewire=OFF -Denable-dbus=OFF -Denable-jack=OFF -Denable-readline=OFF -Denable-network=OFF \
            -Denable-ipv6=OFF -Denable-oss=OFF -Denable-sdl2=OFF -Denable-openmp=OFF -Denable-aufile=OFF \
            -Denable-threads=ON -Denable-ladspa=OFF -Denable-lash=OFF -Denable-portaudio=OFF -Denable-midishare=OFF \
            -Denable-systemd=OFF -Denable-dsound=OFF -Denable-wasapi=OFF -Denable-waveout=OFF -Denable-winmidi=OFF \
            -Denable-opensles=OFF -Denable-oboe=OFF -Denable-coreaudio=OFF -Denable-coremidi=OFF -Denable-dart=OFF \
            -Denable-libinstpatch=OFF -Denable-floats=OFF >/dev/null &&
        cmake_make "$d" -j"$JOBS" >/dev/null && cmake_make "$d" DESTDIR="$STAGE" install >/dev/null
        unset PKG_CONFIG_SYSROOT_DIR
        ship_lib libfluidsynth.so.3 ;;
    sdl12)  # SDL 1.2 (fbcon, ALSA): the Gallery and the E-Reader are SDL 1.2 programs, and their SDL_image
            # and SDL_ttf below need it. The MagicX rootfs has no SDL 1.2 at all; the others do, and win.
        d=$(src SDL-1.2.15.tar.gz SDL-1.2.15)
        cp "$WORK/freetype-2.6.1/builds/unix/config.sub" "$WORK/freetype-2.6.1/builds/unix/config.guess" "$d/build-scripts/"
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --disable-static --disable-video-x11 \
            --disable-video-directfb --enable-video-fbcon --disable-video-opengl --disable-pulseaudio --disable-esd \
            --disable-arts --disable-nas --enable-alsa --enable-alsa-shared --disable-rpath >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null &&
         sed -i "s|^prefix=.*|prefix=$STAGE/usr|" "$STAGE/usr/bin/sdl-config")
        ship_lib libSDL-1.2.so.0 ;;
    sdlimage12) # libSDL_image-1.2.so.0 for gallery64 and reader; PNG and JPEG linked, not dlopened
        d=$(src SDL_image-1.2.12.tar.gz SDL_image-1.2.12)
        cp "$WORK/freetype-2.6.1/builds/unix/config.sub" "$WORK/freetype-2.6.1/builds/unix/config.guess" "$d/"
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --disable-static --with-sdl-prefix="$STAGE/usr" \
            --disable-sdltest --disable-jpg-shared --disable-png-shared --disable-tif --disable-webp >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null)
        ship_lib libSDL_image-1.2.so.0 ;;
    sdlttf) # libSDL_ttf-2.0.so.0 for the same two programs
        d=$(src SDL_ttf-2.0.11.tar.gz SDL_ttf-2.0.11)
        cp "$WORK/freetype-2.6.1/builds/unix/config.sub" "$WORK/freetype-2.6.1/builds/unix/config.guess" "$d/"
        (cd "$d" && CFLAGS="$CFLAGS -I$STAGE/usr/include/freetype2" ./configure --host=$TRIPLET --prefix=/usr \
            --disable-static --with-sdl-prefix="$STAGE/usr" --disable-sdltest --with-freetype-prefix="$STAGE/usr" >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null)
        ship_lib libSDL_ttf-2.0.so.0 ;;
    libatomic)  # not built: the toolchain's own GCC 6.4 runtime library, against the same glibc 2.23.
                # libopenal needs it, and the H700 BaseOS rootfs has none (it came from h700/ports-lib64).
        cp -af "$TC_LIBDIR"/libatomic.so.1* "$STAGE/usr/lib/"
        ship_lib libatomic.so.1 ;;
    *) die "unknown package: $p" ;;
    esac
}

for p in $PKGS; do
    build_one "$p" > "$OUT/logs/$p.log" 2>&1 || { tail -30 "$OUT/logs/$p.log" >&2; die "$p failed (log: $OUT/logs/$p.log)"; }
    log "$p ok"
done

# ---- report -------------------------------------------------------------------
{
    echo "oakmoss=$(oakmoss_version)"
    echo "built=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "toolchain=$("$TC/bin/$TRIPLET-gcc" --version | head -1)"
    echo "toolchain_glibc=$(strings "$TC_LIBC" | grep -m1 'release version' | tr -d '\n')"
    echo "toolchain_lane=$PORTS_TOOLCHAIN"
    echo "packages=$PKGS"
} > "$OUT/BUILD-INFO"
( cd "$OUT" && find bin lib -type f | sort | xargs sha256sum > SHA256SUMS )

log "checking every shipped file loads on glibc 2.33 or older"
bad=0
for f in "$OUT"/bin/* "$OUT"/lib/*; do
    [ -f "$f" ] || continue
    v=$(readelf -V "$f" 2>/dev/null | grep -oE 'GLIBC_2\.[0-9]+' | sort -t. -k2 -n | tail -1)
    case "$v" in
        GLIBC_2.3[4-9]|GLIBC_2.[4-9][0-9]) echo "TOO NEW: $f needs $v" >&2; bad=1 ;;
    esac
done
[ "$bad" = 0 ] || die "some artifacts need a glibc newer than the TrimUI rootfs"

# FLOOR GATES. The firmware serves its own zlib and freetype ahead of the card on every board that has them,
# so what ships may import only what the OLDEST fleet copies export: zlib 1.2.8's version set and
# freetype 2.6.1's symbols (the floor copies built above). A symbol beyond that loads fine and kills the
# process at its first call - invisible to the glibc gate and to any DT_NEEDED check.
if [ -f "$STAGE/usr/lib/libz.so.1" ]; then
    log "checking zlib version needs against the floor zlib"
    zok=" $(readelf -V "$STAGE/usr/lib/libz.so.1" 2>/dev/null | grep -oE 'ZLIB_[0-9.]+' | sort -u | tr '\n' ' ') "
    bad=0
    for f in "$OUT"/bin/* "$OUT"/lib/*; do
        [ -f "$f" ] || continue
        for v in $(readelf -V "$f" 2>/dev/null | grep -oE 'ZLIB_[0-9.]+' | sort -u); do
            case "$zok" in *" $v "*) ;; *) echo "ABOVE THE ZLIB FLOOR: $(basename "$f") needs $v" >&2; bad=1 ;; esac
        done
    done
    [ "$bad" = 0 ] || die "a shipped file needs a zlib newer than the fleet's oldest firmware copy"
else
    warn "no staged zlib: the zlib floor gate did not run (partial build)"
fi
if [ -f "$WORK/floor/libfreetype.so.6" ]; then
    log "checking freetype imports against the floor freetype"
    ftok=" $(readelf -W --dyn-syms "$WORK/floor/libfreetype.so.6" 2>/dev/null | awk '$7 != "UND" && $8 ~ /^FT_/ {print $8}' | sort -u | tr '\n' ' ') "
    bad=0
    for f in "$OUT"/bin/* "$OUT"/lib/*; do
        [ -f "$f" ] || continue
        case "$(basename "$f")" in libfreetype.so.*) continue ;; esac
        for sym in $(readelf -W --dyn-syms "$f" 2>/dev/null | awk '$7 == "UND" && $8 ~ /^FT_/ {print $8}' | sed 's/@.*//' | sort -u); do
            case "$ftok" in *" $sym "*) ;; *) echo "ABOVE THE FREETYPE FLOOR: $(basename "$f") imports $sym" >&2; bad=1 ;; esac
        done
    done
    [ "$bad" = 0 ] || die "a shipped file imports a freetype symbol the fleet's oldest firmware copy lacks"
else
    warn "no floor freetype: the freetype floor gate did not run (partial build)"
fi

# elf-set-rpath.py is silent when a file has no rpath to rewrite (a package that ignored LDFLAGS on
# the armgnu103 lane, where nothing adds one for us). A binary without $ORIGIN/../lib falls back to
# the system copies of our own libraries, so that is fatal; a library without one is reported.
log "checking rpaths"
bad=0
for f in "$OUT"/bin/*; do
    [ -f "$f" ] || continue
    rp=$(readelf -d "$f" 2>/dev/null | sed -n 's/.*(R\(UN\)\{0,1\}PATH).*\[\(.*\)\]/\2/p')
    [ "$rp" = "$BIN_RPATH" ] && continue
    # No rpath at all is acceptable for exactly one kind of binary: one that asks for nothing this tree
    # ships (the prebuilt getconf needs libc alone), so there is no system copy for it to fall back to.
    # That is checked, not assumed: every DT_NEEDED must be absent from lib/.
    if [ -z "$rp" ]; then
        ours=""
        for n in $(readelf -d "$f" 2>/dev/null | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p'); do
            [ -e "$OUT/lib/$n" ] && ours="$ours $n"
        done
        [ -z "$ours" ] && continue
        echo "BAD RPATH: bin/$(basename "$f") has no rpath but needs$ours from this tree" >&2; bad=1; continue
    fi
    echo "BAD RPATH: bin/$(basename "$f") has '$rp', wants '$BIN_RPATH'" >&2; bad=1
done
for f in "$OUT"/lib/*; do
    [ -f "$f" ] || continue
    rp=$(readelf -d "$f" 2>/dev/null | sed -n 's/.*(R\(UN\)\{0,1\}PATH).*\[\(.*\)\]/\2/p')
    case "$rp" in
        "$LIB_RPATH") ;;
        "") warn "lib/$(basename "$f") has no rpath (fine only if it needs nothing from this tree)" ;;
        *) echo "BAD RPATH: lib/$(basename "$f") has '$rp'" >&2; bad=1 ;;
    esac
done
[ "$bad" = 0 ] || die "a shipped file has the wrong rpath"

# The glibc floor says nothing about WHICH libraries a file asks for: configure links whatever the
# sysroot offers. The Tina sysroot is lean, so this set never picked anything up - the armhf lane's
# Buildroot sysroot did (libcrypto.so.3, libxcb), which is where this check comes from.
# With a PARTIAL package list the siblings are not in $OUT/lib, so the check only runs on full builds.
if [ "$PKGS" = "$ALL_PKGS" ]; then
    log "checking that nothing needs a library outside this tree and the base system"
    SYSTEM_OK="libc.so.6 libm.so.6 libdl.so.2 libpthread.so.0 librt.so.1 ld-linux-aarch64.so.1 libgcc_s.so.1 libstdc++.so.6 libz.so.1"
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
fi
log "done: $OUT"
