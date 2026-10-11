#!/usr/bin/env bash
# Build card-side userland (binaries and shared libraries) for spruce's PortMaster
# port environment. By default with the SDK's own vendor toolchain; a second toolchain
# at the fleet's glibc ceiling is selectable (PORTS_TOOLCHAIN, see the block below lib.sh).
#
#   scripts/build-ports-userland.sh [package ...]      (no args = every package)
#   PORTS_TOOLCHAIN=armgnu103 scripts/build-ports-userland.sh [package ...]
#   PORTS_SET=flip PORTS_TOOLCHAIN=armgnu103 scripts/build-ports-userland.sh [package ...]
#
# PORTS_SET=flip builds a second set from the same recipes: the libraries of spruce/flip/lib, for
# the oakMOSS image rather than the card (docs/flip-set.md). It runs in docker/userland-lane.
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
PORTS_SET=${PORTS_SET:-card}
case "$PORTS_SET" in
    card) ;;
    flip) [ "$PORTS_TOOLCHAIN" = armgnu103 ] || die "PORTS_SET=flip builds with PORTS_TOOLCHAIN=armgnu103"
          OUT_SUFFIX="-flipset" ;;
    *) die "unknown PORTS_SET=$PORTS_SET (card | flip)" ;;
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
HOST=$WORK/host                            # build-host tools some packages need (wayland-scanner, ICU's)
if [ "$PORTS_SET" = flip ]; then
    # Only here, so the card set stays byte-identical: .pc paths point into staging (X.org and Wayland
    # put theirs under share/), C++ gets the C flags, and host tools built here are found last on PATH.
    export PKG_CONFIG_SYSROOT_DIR="$STAGE" CXXFLAGS="$CFLAGS"
    export PKG_CONFIG_PATH="$PKG_CONFIG_PATH:$STAGE/usr/share/pkgconfig" PKG_CONFIG_LIBDIR="$PKG_CONFIG_LIBDIR:$STAGE/usr/share/pkgconfig"
    export PATH="$PATH:$HOST/usr/bin"
fi

# The toolchain wrapper appends its own absolute path to every link's rpath and
# has no switch to stop it, so each artifact is rewritten after the fact: a
# binary looks beside itself for its libraries, a library looks next to its
# siblings, and the builder's directory never ships. See elf-set-rpath.py.
BIN_RPATH='$ORIGIN/../lib'          # spruce/aarch64/bin looks in spruce/aarch64/lib
LIB_RPATH='$ORIGIN'
set_rpath() { "$OAKMOSS_ROOT/scripts/elf-set-rpath.py" "$1" "$2"; }

CU_TOOLS="env sort mv cp stat timeout shuf tac sha1sum sha256sum md5sum${EXTRA_CU_TOOLS:+ $EXTRA_CU_TOOLS}"
ALL_PKGS="zlib xz zstd libbsd pcre2 grep tar unzip coreutils findutils lame libvpx ffmpeg libjpegturbo libjpegturbo8 libpng libwebp libogg libvorbis libsndfile libevdev libuuid alsa flac theora modplug physfs openal mpg123 libatomic libgomp pcre openssl ncurses boost ltdl speexdsp pulseaudio interpose curl libdrm freetypefloor harfbuzz libffi glib fluidsynth sdl12 sdlimage12 sdlttf freetype${EXTRA_PKGS:+ $EXTRA_PKGS}"
# The flip set in build order. Build-only packages stage what a later one links and the image already
# carries (zlib, expat, sqlite, SDL2, OpenSSL, GnuTLS...); FLIP_SHIP below is what ships.
FLIP_PKGS="zlib bzip2 xz zstd lz4 libbsd libuuid expat sqlite libffi alsa freetypefloor openssl \
libogg libvorbis theora modplug mpg123 lame opus opusfile speex speexdsp libsndfile ltdl pulseaudio openal \
libvpx libvpx16 libvpx18 libvpx111 dav1d libavif faad2 wavpack libxmp a52dec libmpeg2 gme tremor libopenmpt \
ffmpegflip libpng libjpegturbo8flip libwebp103 giflib tiff pixman fontconfig fribidi \
xorgproto xtrans libXau libXdmcp xcbproto libxcb libX11 libXext libXfixes libXrender libXcursor libXi libXrandr \
libXScrnSaver libICE libSM cairo wayland waylandprotocols libxkbcommon libdecor waylandpp \
sdl2 sdl2gfx sdl2net sdl2image sdl2mixer sdl2ttf mikmod icu liblcf python310 tcl tk glib speechd boost libzip \
libasyncns libwrap libapparmor libcap libmount systemd \
gmp libgpgerror libgcrypt nettle35 nettle37 libtasn1 libunistring libidn2 libpsl p11kit gnutls keyutils comerr krb5 heimdal cyrussasl openldap \
nghttp2 brotli libxcrypt"
[ "$PORTS_SET" = flip ] && SET_PKGS=$FLIP_PKGS || SET_PKGS=$ALL_PKGS
PKGS=${*:-$SET_PKGS}

mkdir -p "$OUT"/{bin,lib,logs} "$WORK" "$STAGE/usr/lib"   # usr/lib: the toolchain-copy packages run alone too

src() {  # src <tarball> <unpacked-dir> : verify, unpack into $WORK, echo the dir
    local glob=$1 dir=$2 tb
    tb=$SRC_DIR/$glob
    [ -f "$tb" ] || die "source missing: $tb (see inputs/userland/urls.txt)"
    # the checksums this checkout carries, not a copy beside the tarballs (SRC_DIR may be shared)
    (cd "$SRC_DIR" && grep " $(basename "$tb")\$" "$OAKMOSS_ROOT/inputs/userland/SHA256SUMS" | sha256sum -c --status -) \
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
        # a recipe's failed build step does not stop it (errexit is off here); an older staged copy must not ship
        if [ "$PORTS_SET" = flip ] && [ ! "$real" -nt "$WORK/.package-start" ]; then die "$so was not rebuilt by $p"; fi
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

mlist() { local a out=""; for a in "$@"; do out="$out${out:+, }'$a'"; done; printf '%s' "$out"; }
meson_cross() {  # meson_cross <srcdir> [-D...] : configure into <srcdir>/build, same toolchain as cmake_cross
    local src=$1; shift
    # shellcheck disable=SC2086  # the flag strings are word lists on purpose
    cat > "$WORK/meson-cross.ini" <<EOF
[binaries]
c = '$TC/bin/$TRIPLET-gcc'
cpp = '$TC/bin/$TRIPLET-g++'
ar = '$TC/bin/$TRIPLET-ar'
strip = '$TC/bin/$TRIPLET-strip'
pkg-config = 'pkg-config'
[built-in options]
c_args = [$(mlist $CFLAGS)]
cpp_args = [$(mlist $CFLAGS)]
c_link_args = [$(mlist $LDFLAGS)]
cpp_link_args = [$(mlist $LDFLAGS)]
[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
EOF
    env -u CC -u CXX -u AR -u RANLIB -u LD -u NM -u STRIP -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS \
        meson setup "$src/build" "$src" --cross-file "$WORK/meson-cross.ini" --prefix=/usr --libdir=lib \
        --buildtype=release -Ddefault_library=shared --wrap-mode=nodownload "$@"
}
meson_make() {  # meson_make <srcdir> [install] : build, or install into staging
    if [ "${2:-}" = install ]; then DESTDIR="$STAGE" ninja -C "$1/build" install
    else ninja -C "$1/build" -j"$JOBS"; fi
}

native() {  # native <command...> : run a build-host step without the cross environment
    env -u CC -u CXX -u AR -u RANLIB -u LD -u NM -u STRIP -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS \
        -u PKG_CONFIG_PATH -u PKG_CONFIG_LIBDIR -u PKG_CONFIG_SYSROOT_DIR PATH="$HOST/usr/bin:$PATH" "$@"
}

fresh_config() {  # fresh_config <dir> : current config.sub/config.guess wherever a tree older than aarch64 has them
    find "$1" -name config.sub -exec cp -f /usr/share/misc/config.sub {} \;
    find "$1" -name config.guess -exec cp -f /usr/share/misc/config.guess {} \;
}
ac_build() {  # ac_build <dir> [configure args] : the common autotools case, installed into staging
    local d=$1; shift
    (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --disable-static "$@" >/dev/null &&
     make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null) || die "$(basename "$d"): configure or make failed"
}

src_into() {  # src_into <tarball> <dir> : verify a package's second tarball (patches) and unpack it into <dir>
    local tb=$SRC_DIR/$1
    [ -f "$tb" ] || die "source missing: $tb (see inputs/userland/urls.txt)"
    (cd "$SRC_DIR" && grep " $1\$" "$OAKMOSS_ROOT/inputs/userland/SHA256SUMS" | sha256sum -c --status -) \
        || die "sha256 mismatch: $tb"
    tar -C "$2" -xf "$tb"
}

build_one() {
    local p=$1 d
    log "=== $p"
    if [ "$PORTS_SET" = flip ]; then touch "$WORK/.package-start"; sleep 1; fi   # for ship_lib's freshness test
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
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null && rm -f "$STAGE/usr/lib/libffi.la")
        # the flip set ships it: the Flip's copy has symbol versions (LIBFFI_BASE_7.0...) the image's lacks
        if [ "$PORTS_SET" = flip ]; then ship_lib libffi.so.7; fi ;;
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
    libgomp)    # not built either: the toolchain's OpenMP runtime. AdvanceMAME and EasyRPG's fluidsynth need it,
                # and neither the H700 BaseOS rootfs nor oakMOSS up to v0.5.0-beta.2 has one.
        cp -af "$TC_LIBDIR"/libgomp.so.1* "$STAGE/usr/lib/"
        ship_lib libgomp.so.1 ;;
    # ---- the flip set (PORTS_SET=flip, 2026-10-11): the libraries of spruce/flip/lib, for the oakMOSS image.
    # Versions follow the Flip's copies where the soname or the C++ ABI pins them (docs/flip-set.md).
    bzip2)  # build dependency only (ffmpeg, libzip): the image has libbz2.so.1.0
        d=$(src bzip2-1.0.8.tar.gz bzip2-1.0.8)
        (cd "$d" && make -f Makefile-libbz2_so CC="$CC" CFLAGS="$CFLAGS -D_FILE_OFFSET_BITS=64" >/dev/null &&
         install -Dm644 bzlib.h "$STAGE/usr/include/bzlib.h" && cp -af libbz2.so.1.0* "$STAGE/usr/lib/" &&
         ln -sfn libbz2.so.1.0 "$STAGE/usr/lib/libbz2.so") || die "bzip2: build failed" ;;
    lz4)
        d=$(src lz4-1.9.4.tar.gz lz4-1.9.4)
        (cd "$d/lib" && make -j"$JOBS" CC="$CC" BUILD_STATIC=no PREFIX=/usr >/dev/null &&
         make BUILD_STATIC=no PREFIX=/usr DESTDIR="$STAGE" install >/dev/null)
        ship_lib liblz4.so.1 ;;
    expat)  # build dependency only, at the image's version: fontconfig and liblcf must not import newer exports
        d=$(src expat-2.1.0.tar.gz expat-2.1.0)
        fresh_config "$d"
        ac_build "$d" ;;
    sqlite) # build dependency only (Heimdal), at the image's version
        d=$(src sqlite-autoconf-3120200.tar.gz sqlite-autoconf-3120200)
        fresh_config "$d"
        ac_build "$d" --disable-readline --disable-dynamic-extensions ;;
    opus)
        d=$(src opus-1.4.tar.gz opus-1.4)
        ac_build "$d" --disable-doc --disable-extra-programs
        ship_lib libopus.so.0 ;;
    opusfile)   # ogg and opus only, as the Flip's: no HTTP, which would pull in OpenSSL
        d=$(src opusfile-0.12.tar.gz opusfile-0.12)
        ac_build "$d" --disable-http --disable-examples --disable-doc
        ship_lib libopusfile.so.0 ;;
    speex)  # the codec; its DSP half is speexdsp
        d=$(src speex-1.2.1.tar.gz speex-1.2.1)
        ac_build "$d" --disable-binaries
        ship_lib libspeex.so.1 ;;
    faad2)  # 2.10.1, the last autotools release; the tag archive carries no configure
        d=$(src faad2-2.10.1.tar.gz faad2-2.10.1)
        (cd "$d" && autoreconf -fi >/dev/null 2>&1) || die "faad2: autoreconf failed"
        ac_build "$d"
        ship_lib libfaad.so.2 ;;
    wavpack)
        d=$(src wavpack-5.6.0.tar.xz wavpack-5.6.0)
        ac_build "$d" --disable-apps
        ship_lib libwavpack.so.1 ;;
    libxmp)
        d=$(src libxmp-4.6.0.tar.gz libxmp-4.6.0)
        ac_build "$d"
        ship_lib libxmp.so.4 ;;
    fribidi)
        d=$(src fribidi-1.0.8.tar.bz2 fribidi-1.0.8)
        ac_build "$d" --disable-docs
        ship_lib libfribidi.so.0 ;;
    giflib) # plain Makefile; its default target also wants the documentation tools
        d=$(src giflib-5.2.1.tar.gz giflib-5.2.1)
        (cd "$d" && make -j"$JOBS" CC="$CC" CFLAGS="$CFLAGS" libgif.so libgif.a >/dev/null &&
         make PREFIX=/usr DESTDIR="$STAGE" install-include install-lib >/dev/null)
        ship_lib libgif.so.7 ;;
    tiff)   # libtiff.so.5 alone, as the Flip's: no JPEG, zlib, LZMA, ZSTD, WebP or JBIG codecs and no C++
        d=$(src tiff-4.2.0.tar.gz tiff-4.2.0)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --disable-static --disable-cxx --disable-jpeg \
            --disable-old-jpeg --disable-zlib --disable-pixarlog --disable-lzma --disable-zstd --disable-webp \
            --disable-jbig >/dev/null && make -j"$JOBS" -C port >/dev/null && make -j"$JOBS" -C libtiff >/dev/null &&
         make -C libtiff DESTDIR="$STAGE" install >/dev/null)
        ship_lib libtiff.so.5 ;;
    pixman)
        d=$(src pixman-0.42.2.tar.xz pixman-0.42.2)
        ac_build "$d" --disable-gtk --disable-libpng
        ship_lib libpixman-1.so.0 ;;
    libvpx16|libvpx18|libvpx111)    # the Flip's three older sonames. Only the libraries enter staging, so
                                    # the headers stay the 1.13.1 ones (libvpx.so.8) that ffmpeg links.
        case $p in libvpx16) v=1.6.1 so=4 ;; libvpx18) v=1.8.2 so=6 ;; *) v=1.11.0 so=7 ;; esac
        d=$(src libvpx-$v.tar.gz libvpx-$v)
        # without the staging include path, where the 1.13.1 headers would shadow the tree's own
        (cd "$d" && export CFLAGS="-O2 -fPIC" CPPFLAGS="" &&
         LDFLAGS="$LDFLAGS -lpthread" CROSS=$TRIPLET- ./configure --target=arm64-linux-gcc --prefix=/usr \
            --enable-pic --enable-shared --disable-static --disable-examples --disable-tools --disable-docs \
            --disable-unit-tests >/dev/null && make -j"$JOBS" >/dev/null && cp -af libvpx.so.$so* "$STAGE/usr/lib/")
        ship_lib libvpx.so.$so ;;
    dav1d)
        d=$(src dav1d-1.2.1.tar.xz dav1d-1.2.1)
        meson_cross "$d" -Denable_tools=false -Denable_tests=false >/dev/null &&
        meson_make "$d" >/dev/null && meson_make "$d" install >/dev/null
        ship_lib libdav1d.so.6 ;;
    libavif)    # decoding through dav1d only, as the Flip's
        d=$(src libavif-1.0.4.tar.gz libavif-1.0.4)
        (cmake_cross "$d" -DBUILD_SHARED_LIBS=ON -DAVIF_CODEC_DAV1D=ON -DAVIF_BUILD_APPS=OFF -DAVIF_BUILD_TESTS=OFF \
            -DAVIF_BUILD_EXAMPLES=OFF >/dev/null &&
         cmake_make "$d" -j"$JOBS" >/dev/null && cmake_make "$d" DESTDIR="$STAGE" install >/dev/null)
        ship_lib libavif.so.16 ;;
    a52dec) # Debian's liba52-0.7.4.so, the name the Flip's copy has: the soname carries the version, so the
            # PIC objects are linked by hand
        d=$(src a52dec-0.7.4.tar.gz a52dec-0.7.4)
        fresh_config "$d"
        # its 2002 libtool does not know aarch64 and builds the objects static only; they are PIC from CFLAGS
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr >/dev/null && make -j"$JOBS" -C liba52 CFLAGS="$CFLAGS" >/dev/null &&
         objs=$(ls liba52/.libs/*.o 2>/dev/null || ls liba52/*.o) &&
         $CC -shared -Wl,-soname,liba52-0.7.4.so -o "$STAGE/usr/lib/liba52-0.7.4.so" $objs -lm $LDFLAGS &&
         install -Dm644 include/a52.h "$STAGE/usr/include/a52dec/a52.h" &&
         install -Dm644 include/attributes.h "$STAGE/usr/include/a52dec/attributes.h")
        ship_lib liba52-0.7.4.so ;;
    libmpeg2)
        d=$(src libmpeg2-0.5.1.tar.gz libmpeg2-0.5.1)
        fresh_config "$d"
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --disable-static --disable-sdl --without-x >/dev/null &&
         make -j"$JOBS" -C libmpeg2 >/dev/null && make -C libmpeg2 DESTDIR="$STAGE" install >/dev/null &&
         make -C include DESTDIR="$STAGE" install >/dev/null)
        ship_lib libmpeg2.so.0 ;;
    gme)
        d=$(src game-music-emu-0.6.3.tar.gz game-music-emu-0.6.3)
        (cmake_cross "$d" -DBUILD_SHARED_LIBS=ON -DENABLE_UBSAN=OFF >/dev/null &&
         cmake_make "$d" -j"$JOBS" >/dev/null && cmake_make "$d" DESTDIR="$STAGE" install >/dev/null)
        ship_lib libgme.so.0 ;;
    tremor) # libvorbisidec.so.1 for aarch64: the Flip's copy is an armhf file no 64-bit program can load
        d=$(src libvorbisidec_1.2.1+git20180316.orig.tar.gz libvorbisidec-1.2.1+git20180316)
        # its configure.ac uses XIPH_PATH_OGG, from the ogg.m4 libogg installed into staging
        (cd "$d" && ACLOCAL_PATH="$STAGE/usr/share/aclocal" autoreconf -fi >/dev/null 2>&1) || die "tremor: autoreconf failed"
        ac_build "$d"
        ship_lib libvorbisidec.so.1 ;;
    libopenmpt) # 0.4.11, the Flip's: zlib, mpg123 and Vorbis for its compressed samples
        d=$(src libopenmpt-0.4.11+release.autotools.tar.gz libopenmpt-0.4.11+release.autotools)
        ac_build "$d" --disable-openmpt123 --disable-examples --disable-tests --disable-doxygen-doc \
            --with-zlib --with-mpg123 --with-ogg --with-vorbis --with-vorbisfile --without-portaudio \
            --without-portaudiocpp --without-pulseaudio --without-sndfile --without-flac
        ship_lib libopenmpt.so.0 ;;
    libjpegturbo8flip)  # 2.1.5 with the jpeg8 ABI, as the Flip's, whose LIBJPEGTURBO_8.0 versions 1.5.3 lacks
        d=$(src libjpeg-turbo-2.1.5.tar.gz libjpeg-turbo-2.1.5)
        # absolute directories: its own GNUInstallDirs turns lib into /lib, outside the /usr prefix
        (cmake_cross "$d" -DWITH_JPEG8=ON -DENABLE_STATIC=OFF -DWITH_TURBOJPEG=OFF -DCMAKE_INSTALL_LIBDIR=/usr/lib \
            -DCMAKE_INSTALL_INCLUDEDIR=/usr/include >/dev/null &&
         cmake_make "$d" -j"$JOBS" >/dev/null && cmake_make "$d" DESTDIR="$STAGE" install >/dev/null)
        ship_lib libjpeg.so.8 ;;
    libwebp103) # libwebp.so.7 and libwebpdemux.so.2 (1.0.3, the Flip's version); its odd names become links
        d=$(src libwebp-1.0.3.tar.gz libwebp-1.0.3)
        LDFLAGS="$LDFLAGS -lm" ac_build "$d" --enable-libwebpdemux --disable-libwebpmux --disable-libwebpdecoder \
            --disable-libwebpextras --disable-gl --disable-sdl --disable-png --disable-jpeg --disable-tiff --disable-gif
        ship_lib libwebp.so.7 libwebpdemux.so.2 ;;
    libzip) # libzip.so.5 for the PixelReader: zlib, bzip2 and OpenSSL, as the Flip's
        d=$(src libzip-1.5.2.tar.xz libzip-1.5.2)
        (cmake_cross "$d" -DBUILD_SHARED_LIBS=ON -DENABLE_GNUTLS=OFF -DENABLE_MBEDTLS=OFF -DENABLE_OPENSSL=ON \
            -DENABLE_COMMONCRYPTO=OFF -DENABLE_BZIP2=ON -DBUILD_TOOLS=OFF -DBUILD_REGRESS=OFF -DBUILD_EXAMPLES=OFF \
            -DBUILD_DOC=OFF >/dev/null &&
         cmake_make "$d" -j"$JOBS" >/dev/null && cmake_make "$d" DESTDIR="$STAGE" install >/dev/null)
        ship_lib libzip.so.5 ;;
    libasyncns) # one of the extras Ubuntu's PulseAudio links in the Flip set
        d=$(src libasyncns-0.8.tar.gz libasyncns-0.8)
        fresh_config "$d"
        ac_build "$d" --disable-lynx
        ship_lib libasyncns.so.0 ;;
    keyutils)   # libkeyutils.so.1: MIT Kerberos's keyring credential cache
        d=$(src keyutils-1.6.1.tar.bz2 keyutils-1.6.1)
        (cd "$d" && make -j"$JOBS" CC="$CC" CFLAGS="$CFLAGS" NO_ARLIB=1 >/dev/null &&
         cp -af libkeyutils.so.1* "$STAGE/usr/lib/" && ln -sfn libkeyutils.so.1 "$STAGE/usr/lib/libkeyutils.so" &&
         install -Dm644 keyutils.h "$STAGE/usr/include/keyutils.h")
        ship_lib libkeyutils.so.1 ;;
    nghttp2)
        d=$(src nghttp2-1.40.0.tar.xz nghttp2-1.40.0)
        ac_build "$d" --enable-lib-only
        ship_lib libnghttp2.so.14 ;;
    brotli)
        d=$(src brotli-1.0.9.tar.gz brotli-1.0.9)
        (cmake_cross "$d" -DBROTLI_DISABLE_TESTS=ON >/dev/null &&
         cmake_make "$d" -j"$JOBS" >/dev/null && cmake_make "$d" DESTDIR="$STAGE" install >/dev/null)
        ship_lib libbrotlicommon.so.1 libbrotlidec.so.1 ;;
    libunistring)
        d=$(src libunistring-0.9.10.tar.xz libunistring-0.9.10)
        ac_build "$d"
        ship_lib libunistring.so.2 ;;
    libtasn1)
        d=$(src libtasn1-4.16.0.tar.gz libtasn1-4.16.0)
        ac_build "$d" --disable-doc --disable-valgrind-tests
        ship_lib libtasn1.so.6 ;;
    gmp)    # nettle's hogweed and GnuTLS link it; the image's libgmp.so.10 lacks 18 of the Flip copy's exports
        d=$(src gmp-6.2.1.tar.xz gmp-6.2.1)
        ac_build "$d" --disable-cxx
        ship_lib libgmp.so.10 ;;
    nettle35)   # libnettle.so.7 / libhogweed.so.5, the pair GnuTLS 3.6 links (the image's and the Flip's)
        d=$(src nettle-3.5.1.tar.gz nettle-3.5.1)
        ac_build "$d" --libdir=/usr/lib --disable-documentation
        ship_lib libnettle.so.7 libhogweed.so.5 ;;
    nettle37)   # the Flip's second pair (libnettle.so.8 / libhogweed.so.6); only the libraries enter staging
        d=$(src nettle-3.7.3.tar.gz nettle-3.7.3)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --libdir=/usr/lib --disable-static \
            --disable-documentation >/dev/null && make -j"$JOBS" >/dev/null &&
         cp -af .lib/libnettle.so.8* .lib/libhogweed.so.6* "$STAGE/usr/lib/")
        ship_lib libnettle.so.8 libhogweed.so.6 ;;
    libidn2)    # against the shipped libunistring, as Ubuntu's
        d=$(src libidn2-2.3.0.tar.gz libidn2-2.3.0)
        ac_build "$d" --disable-doc --disable-nls --with-libunistring-prefix="$STAGE/usr"
        ship_lib libidn2.so.0 ;;
    libpsl)     # libidn2 + libunistring, as Ubuntu's
        d=$(src libpsl-0.21.0.tar.gz libpsl-0.21.0)
        ac_build "$d" --disable-man --disable-gtk-doc --enable-runtime=libidn2 --enable-builtin=libidn2
        ship_lib libpsl.so.5 ;;
    ffmpegflip) # LGPL (no postproc, so no --enable-gpl) with the codecs the Flip's copy links, and TLS through the
                # image's OpenSSL 1.1 where the Flip's wanted OpenSSL 3. Only the five libraries the Flip set has.
        d=$(src ffmpeg-4.4.5.tar.xz ffmpeg-4.4.5)
        (cd "$d" && ./configure --enable-cross-compile --arch=aarch64 --target-os=linux --cross-prefix=$TRIPLET- \
            --prefix=/usr --enable-shared --disable-static --disable-programs --disable-doc --disable-debug \
            --disable-avdevice --disable-avfilter --disable-postproc --enable-libmp3lame --enable-libvpx \
            --enable-libopus --enable-libspeex --enable-libtheora --enable-libvorbis --enable-libmodplug --enable-bzlib \
            --enable-lzma --enable-zlib --enable-openssl --pkg-config=pkg-config \
            --extra-cflags="-I$STAGE/usr/include" --extra-ldflags="-L$STAGE/usr/lib" --extra-libs="-lpthread -lm" \
            >/dev/null && make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null)
        ship_lib libavcodec.so.58 libavformat.so.58 libavutil.so.56 libswresample.so.3 libswscale.so.5 ;;
    fontconfig) # cairo links it. The floor FreeType and the image's expat; the image has no fonts.conf, so it runs on
                # built-in defaults. 2.12: 2.13 and later want FreeType 2.8.1.
        d=$(src fontconfig-2.12.6.tar.bz2 fontconfig-2.12.6)
        ac_build "$d" --sysconfdir=/etc --localstatedir=/var --disable-docs --disable-cache-build \
            --with-default-fonts=/usr/share/fonts
        ship_lib libfontconfig.so.1 ;;
    xorgproto|xtrans)   # headers only
        case $p in xorgproto) v=2023.2 ;; *) v=1.5.0 ;; esac
        d=$(src $p-$v.tar.xz $p-$v)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --disable-docs >/dev/null &&
         make DESTDIR="$STAGE" install >/dev/null) || die "$p: build failed" ;;
    xcbproto)   # build dependency only: the XML protocol description and the Python module libxcb generates from
        d=$(src xcb-proto-1.16.0.tar.xz xcb-proto-1.16.0)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr >/dev/null && make DESTDIR="$STAGE" install >/dev/null) ||
            die "xcbproto: build failed" ;;
    libxcb)     # every extension builds; libxcb, -render and -shm ship (what cairo and the Flip set link)
        d=$(src libxcb-1.16.tar.xz libxcb-1.16)
        py=$(dirname "$(find "$STAGE/usr/lib" -type d -name xcbgen | head -1)")
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --disable-static --disable-devel-docs --without-doxygen \
            >/dev/null && make -j"$JOBS" XCBPROTO_XCBINCLUDEDIR="$STAGE/usr/share/xcb" XCBPROTO_XCBPYTHONDIR="$py" \
            PYTHONPATH="$py" >/dev/null && make DESTDIR="$STAGE" install >/dev/null)
        ship_lib libxcb.so.1 libxcb-render.so.0 libxcb-shm.so.0 ;;
    libX11)
        d=$(src libX11-1.8.7.tar.xz libX11-1.8.7)
        ac_build "$d" --disable-specs --without-xmlto --without-fop --without-xsltproc --enable-malloc0returnsnull
        ship_lib libX11.so.6 ;;
    libXau|libXdmcp|libXext|libXfixes|libXrender|libXcursor|libXi|libXrandr|libXScrnSaver|libICE|libSM)
        case $p in
            libXau) v=1.0.11 so=libXau.so.6 ;;       libXdmcp) v=1.1.4 so=libXdmcp.so.6 ;;
            libXext) v=1.3.5 so=libXext.so.6 ;;      libXfixes) v=6.0.1 so=libXfixes.so.3 ;;
            libXrender) v=0.9.11 so=libXrender.so.1 ;; libXcursor) v=1.2.1 so=libXcursor.so.1 ;;
            libXi) v=1.8.1 so=libXi.so.6 ;;          libXrandr) v=1.5.4 so=libXrandr.so.2 ;;
            libXScrnSaver) v=1.2.4 so=libXss.so.1 ;; libICE) v=1.1.1 so=libICE.so.6 ;;
            libSM) v=1.2.4 so=libSM.so.6 ;;
        esac
        d=$(src $p-$v.tar.xz $p-$v)
        ac_build "$d" --disable-specs --disable-docs --without-xmlto --without-fop --without-xsltproc \
            --enable-malloc0returnsnull
        ship_lib $so ;;
    cairo)  # xlib, xcb, PNG and FreeType/fontconfig, as the Flip's: no GL, GObject, trace or script interpreter
        d=$(src cairo-1.16.0.tar.xz cairo-1.16.0)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --disable-static --enable-xlib --enable-xlib-xrender \
            --enable-xcb --enable-xcb-shm --enable-ft --enable-fc --enable-png --disable-gl --disable-glesv2 --disable-egl \
            --disable-gobject --disable-trace --disable-interpreter --disable-symbol-lookup --disable-full-testing \
            --disable-gtk-doc --disable-valgrind >/dev/null &&
         make -j"$JOBS" -C src >/dev/null && make -C src DESTDIR="$STAGE" install >/dev/null)
        ship_lib libcairo.so.2 ;;
    wayland)    # against libffi 3.3, the image's libffi.so.7: the Flip's copy wants libffi.so.8, which nothing in the
                # set or the image provides. wayland-scanner is built for the build host first.
        d=$(src wayland-1.22.0.tar.xz wayland-1.22.0)
        native meson setup "$d/build-host" "$d" --prefix="$HOST/usr" -Dlibraries=false -Dtests=false \
            -Ddocumentation=false -Ddtd_validation=false >/dev/null &&
        native ninja -C "$d/build-host" install >/dev/null &&
        meson_cross "$d" -Dscanner=false -Dtests=false -Ddocumentation=false -Ddtd_validation=false >/dev/null &&
        meson_make "$d" >/dev/null && meson_make "$d" install >/dev/null
        ship_lib libwayland-client.so.0 libwayland-cursor.so.0 libwayland-egl.so.1 ;;
    waylandprotocols)   # build dependency only (libdecor): protocol XML
        d=$(src wayland-protocols-1.32.tar.xz wayland-protocols-1.32)
        meson_cross "$d" -Dtests=false >/dev/null && meson_make "$d" install >/dev/null || die "waylandprotocols: build failed" ;;
    libxkbcommon)   # the keymap library alone: no X11 or Wayland tools, no registry (libxml2)
        d=$(src libxkbcommon-1.6.0.tar.xz libxkbcommon-1.6.0)
        meson_cross "$d" -Denable-x11=false -Denable-wayland=false -Denable-docs=false -Denable-tools=false \
            -Denable-xkbregistry=false -Denable-bash-completion=false >/dev/null &&
        meson_make "$d" >/dev/null && meson_make "$d" install >/dev/null
        ship_lib libxkbcommon.so.0 ;;
    libdecor)   # the core library alone, as the Flip's (its plugins are loaded at run time and are not in the set)
        d=$(src libdecor-0.2.2.tar.xz libdecor-0.2.2)
        meson_cross "$d" -Ddemo=false -Dinstall_demo=false -Ddbus=disabled -Dgtk=disabled >/dev/null &&
        meson_make "$d" >/dev/null && meson_make "$d" install >/dev/null
        ship_lib libdecor-0.so.0 ;;
    waylandpp)  # libwayland-egl++.so.1. wayland-scanner++ is built for the build host first.
        d=$(src waylandpp-1.0.0.tar.gz waylandpp-1.0.0)
        (native cmake -S "$d" -B "$d/build-host" -DCMAKE_INSTALL_PREFIX="$HOST/usr" -DBUILD_LIBRARIES=OFF \
            -DBUILD_SCANNER=ON -DBUILD_DOCUMENTATION=OFF -DBUILD_EXAMPLES=OFF >/dev/null &&
         native make -C "$d/build-host" -j"$JOBS" install >/dev/null) &&
        (cmake_cross "$d" -DBUILD_SCANNER=OFF -DBUILD_LIBRARIES=ON -DBUILD_DOCUMENTATION=OFF -DBUILD_EXAMPLES=OFF \
            -DWAYLAND_SCANNERPP="$HOST/usr/bin/wayland-scanner++" >/dev/null &&
         cmake_make "$d" -j"$JOBS" >/dev/null && cmake_make "$d" DESTDIR="$STAGE" install >/dev/null)
        ship_lib libwayland-egl++.so.1 ;;
    sdl2)   # build dependency only, at the image's version (the vendor's 2.26.1): SDL headers and a libSDL2 to link
        d=$(src SDL2-2.26.1.tar.gz SDL2-2.26.1)
        ac_build "$d" --disable-video-x11 --disable-video-wayland --disable-video-kmsdrm --disable-video-vulkan \
            --disable-video-opengl --disable-video-opengles --disable-pulseaudio --disable-pipewire --disable-jack \
            --disable-esd --disable-arts --disable-nas --disable-sndio --enable-alsa --enable-alsa-shared
        sed -i "s|^prefix=.*|prefix=$STAGE/usr|" "$STAGE/usr/bin/sdl2-config" ;;
    sdl2gfx)
        d=$(src SDL2_gfx-1.0.4.tar.gz SDL2_gfx-1.0.4)
        fresh_config "$d"
        ac_build "$d" --disable-mmx --with-sdl-prefix="$STAGE/usr"
        ship_lib libSDL2_gfx-1.0.so.0 ;;
    sdl2net)
        d=$(src SDL2_net-2.2.0.tar.gz SDL2_net-2.2.0)
        ac_build "$d" --disable-examples --disable-gui
        ship_lib libSDL2_net-2.0.so.0 ;;
    mikmod) # SDL2, OpenAL and PulseAudio drivers, as the Flip's libmikmod.so.3
        d=$(src libmikmod-3.3.11.1.tar.gz libmikmod-3.3.11.1)
        ac_build "$d" --enable-sdl2 --enable-openal --enable-pulseaudio --enable-alsa --disable-oss --disable-esd \
            --disable-nas --disable-doc
        ship_lib libmikmod.so.3 ;;
    icu)    # ICU 63, the major liblcf and the EasyRPG core were built against (its symbols carry the _63 suffix).
            # A build-host ICU first: the cross build runs its tools to package the data.
        d=$(src icu4c-63_2-src.tgz icu)
        mkdir -p "$d/build-host" "$d/build-cross"
        (cd "$d/build-host" && native ../source/runConfigureICU Linux --prefix="$HOST/usr" --disable-tests \
            --disable-samples >/dev/null && native make -j"$JOBS" >/dev/null) &&
        (cd "$d/build-cross" && ../source/configure --host=$TRIPLET --prefix=/usr --disable-static --disable-tests \
            --disable-samples --with-cross-build="$d/build-host" >/dev/null &&
         make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null)
        ship_lib libicudata.so.63 libicuuc.so.63 libicui18n.so.63 ;;
    liblcf) # 0.8: the EasyRPG core's 46 lcf:: imports are all among the Flip copy's exports; expat and ICU 63
        d=$(src liblcf-0.8.tar.xz liblcf-0.8)
        ac_build "$d" --disable-tools --disable-update-mimedb
        ship_lib liblcf.so.0 ;;
    python310)  # libpython3.10.so.1.0 and libpython3.so at the card's version (spruce/flip/lib/python3.10 is 3.10.19's;
                # the Flip's interpreter links Python statically). A build-host 3.10 drives the cross build.
        d=$(src Python-3.10.19.tar.xz Python-3.10.19)
        mkdir -p "$d/build-host" "$d/build-cross"
        (cd "$d/build-host" && native ../configure --prefix="$HOST/usr" --without-ensurepip >/dev/null &&
         native make -j"$JOBS" >/dev/null && native make install >/dev/null) &&
        (cd "$d/build-cross" && PATH="$HOST/usr/bin:$PATH" ../configure --host=$TRIPLET --build=x86_64-pc-linux-gnu \
            --prefix=/usr --enable-shared --without-ensurepip ac_cv_file__dev_ptmx=yes ac_cv_file__dev_ptc=no \
            ac_cv_buggy_getaddrinfo=no >/dev/null &&
         PATH="$HOST/usr/bin:$PATH" make -j"$JOBS" libpython3.10.so libpython3.so >/dev/null &&
         cp -af libpython3.10.so* libpython3.so "$STAGE/usr/lib/")
        ship_lib libpython3.10.so.1.0 libpython3.so ;;
    tcl)    # 8.6.14, the Flip's. The library alone; Tk builds against this tree.
        d=$(src tcl8.6.14-src.tar.gz tcl8.6.14)
        (cd "$d/unix" && ac_cv_func_strtod=yes tcl_cv_strtod_buggy=1 tcl_cv_strtod_unbroken=ok \
            ./configure --host=$TRIPLET --prefix=/usr --enable-shared --enable-threads >/dev/null &&
         make -j"$JOBS" binaries >/dev/null && make DESTDIR="$STAGE" install-binaries install-headers >/dev/null)
        ship_lib libtcl8.6.so ;;
    tk)     # 8.6.14 on the shipped X11 (the Flip's has X11 linked into itself); no Xft
        d=$(src tk8.6.14-src.tar.gz tk8.6.14)
        (cd "$d/unix" && ./configure --host=$TRIPLET --prefix=/usr --enable-shared --enable-threads \
            --with-tcl="$WORK/tcl8.6.14/unix" --x-includes="$STAGE/usr/include" --x-libraries="$STAGE/usr/lib" \
            --disable-xft >/dev/null &&
         make -j"$JOBS" binaries >/dev/null && make DESTDIR="$STAGE" install-binaries install-headers >/dev/null)
        ship_lib libtk8.6.so ;;
    speechd)    # libspeechd.so.2, the client library alone (ScummVM's text-to-speech), against glib
        d=$(src speech-dispatcher-0.11.5.tar.gz speech-dispatcher-0.11.5)
        ac_build "$d" --disable-python --without-pulse --without-libao --without-oss --without-nas --without-alsa \
            --without-espeak --without-espeak-ng --without-flite --without-ibmtts --without-voxin --without-pico \
            --without-kali --without-baratinoo
        ship_lib libspeechd.so.2 ;;
    libapparmor)    # one of the extras Ubuntu's PulseAudio links in the Flip set
        d=$(src apparmor-3.0.13.tar.gz apparmor-3.0.13)
        ac_build "$d/libraries/libapparmor" --without-perl --without-python --without-ruby
        ship_lib libapparmor.so.1 ;;
    libwrap)    # tcp_wrappers 7.6 with Debian's patches (7.6.q-31), which add the shared libwrap.so.0
        d=$(src tcp-wrappers_7.6.q.orig.tar.gz tcp_wrappers_7.6)
        src_into tcp-wrappers_7.6.q-31.debian.tar.xz "$d"
        (cd "$d" && while read -r pt; do case $pt in ''|'#'*) continue ;; esac; patch -p1 -s < "debian/patches/$pt" || exit 1
         done < debian/patches/series && make CC="$CC" AR="$AR" RANLIB="$RANLIB" COPTS="$CFLAGS" LDOPTS="$LDFLAGS" \
            linux >/dev/null && cp -af shared/libwrap.so.0* "$STAGE/usr/lib/") || die "libwrap: build failed"
        ship_lib libwrap.so.0 ;;
    libcap) # build dependency only (systemd's configure)
        d=$(src libcap-2.69.tar.xz libcap-2.69)
        (cd "$d/libcap" && make -j"$JOBS" CROSS_COMPILE=$TRIPLET- BUILD_CC=gcc lib=lib prefix=/usr GOLANG=no >/dev/null &&
         make CROSS_COMPILE=$TRIPLET- BUILD_CC=gcc lib=lib prefix=/usr GOLANG=no DESTDIR="$STAGE" install >/dev/null) ||
            die "libcap: build failed" ;;
    libmount)   # build dependency only: systemd's configure wants libmount 2.30 or later
        d=$(src util-linux-2.39.4.tar.xz util-linux-2.39.4)
        ac_build "$d" --disable-all-programs --enable-libmount --enable-libblkid --disable-nls --without-python \
            --without-systemd --without-udev --disable-bash-completion --disable-makeinstall-chown \
            --disable-makeinstall-setuid --disable-asciidoc
        for f in "$STAGE"/lib/libmount.so.1* "$STAGE"/lib/libblkid.so.1*; do [ -e "$f" ] && cp -af "$f" "$STAGE/usr/lib/"; done ;;
    systemd)    # libsystemd.so.0 alone, with xz and lz4 as the Flip's; every optional dependency off
        d=$(src systemd-stable-249.17.tar.gz systemd-stable-249.17)
        meson_cross "$d" -Dtests=false -Dman=false -Dhtml=false -Dtranslations=false -Dseccomp=false -Dselinux=false \
            -Dapparmor=false -Dpolkit=false -Dacl=false -Daudit=false -Dblkid=false -Dfdisk=false -Dkmod=false -Dpam=false \
            -Dpwquality=false -Dmicrohttpd=false -Dlibcryptsetup=false -Dlibcurl=false -Didn=false -Dlibidn2=false \
            -Dlibidn=false -Dlibiptc=false -Dqrencode=false -Dgcrypt=false -Dgnutls=false -Dopenssl=false -Dp11kit=false \
            -Dlibfido2=false -Dtpm2=false -Delfutils=false -Dzlib=false -Dbzip2=false -Dxz=true -Dlz4=true -Dzstd=false \
            -Dxkbcommon=false -Dpcre2=false -Dglib=false -Ddbus=false -Dgnu-efi=false -Dbpf-framework=false -Dhomed=false \
            -Dimportd=false -Dremote=false -Drepart=false -Dnss-mymachines=false -Dnss-resolve=false \
            -Ddns-over-tls=false >/dev/null &&
        ninja -C "$d/build" -j"$JOBS" libsystemd.so.0.32.0 >/dev/null &&
        cp -af "$d/build"/libsystemd.so.0* "$STAGE/usr/lib/" || die "systemd: build failed"
        ship_lib libsystemd.so.0 ;;
    p11kit) # libp11-kit.so.0 against the image's libffi 3.3, without the trust module (the Flip set has none)
        d=$(src p11-kit-0.23.22.tar.xz p11-kit-0.23.22)
        ac_build "$d" --disable-trust-module --disable-doc --disable-nls --without-systemd --without-bash-completion \
            --with-module-path=/usr/lib/pkcs11
        ship_lib libp11-kit.so.0 ;;
    gnutls) # 3.6.16: the image's 3.6.5 lacks the GNUTLS_3_6_6..13 versions of the Flip's copy, which ports on the
            # port path got. Against nettle 3.5, as the image's and the Flip's are.
        d=$(src gnutls-3.6.16.tar.xz gnutls-3.6.16)
        ac_build "$d" --disable-doc --disable-tools --disable-cxx --disable-tests --disable-guile --without-tpm \
            --disable-libdane --without-included-libtasn1 --without-included-unistring --disable-nls
        ship_lib libgnutls.so.30 ;;
    comerr) # libcom_err.so.2 from e2fsprogs, which both Kerberos builds in the Flip set link (as Ubuntu's), and its
            # compile_et, a shell script, for the build host
        d=$(src e2fsprogs-1.47.0.tar.xz e2fsprogs-1.47.0)
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --with-root-prefix=/usr --enable-elf-shlibs \
            --disable-nls --disable-libuuid --disable-libblkid --disable-uuidd --disable-fsck --disable-fuse2fs \
            >/dev/null && make -j"$JOBS" -C lib/et >/dev/null && make -C lib/et DESTDIR="$STAGE" install >/dev/null) ||
            die "comerr: build failed"
        mkdir -p "$HOST/usr/bin"
        printf '#!/bin/sh\nDIR=%s exec sh %s "$@"\n' "$STAGE/usr/share/et" "$STAGE/usr/bin/compile_et" > "$HOST/usr/bin/compile_et"
        chmod +x "$HOST/usr/bin/compile_et"
        ship_lib libcom_err.so.2 ;;
    krb5)   # MIT Kerberos 1.17 (the Flip's is krb5-1.17-final) with e2fsprogs' com_err and keyutils, as Ubuntu builds
            # it; its run-time configure tests are answered for glibc
        d=$(src krb5-1.17.2.tar.gz krb5-1.17.2)
        (cd "$d/src" && krb5_cv_attr_constructor_destructor=yes,yes ac_cv_func_regcomp=yes ac_cv_printf_positional=yes \
            ac_cv_file__etc_environment=yes ac_cv_file__etc_TIMEZONE=no ./configure --host=$TRIPLET --prefix=/usr \
            --sysconfdir=/etc --localstatedir=/var --with-system-et --without-system-ss --without-ldap --without-tcl \
            --disable-pkinit --without-libedit --without-readline --with-crypto-impl=builtin --with-tls-impl=no \
            --without-lmdb --disable-nls >/dev/null && make -j"$JOBS" >/dev/null && make DESTDIR="$STAGE" install >/dev/null) ||
            die "krb5: build failed"
        ship_lib libgssapi_krb5.so.2 libkrb5.so.3 libk5crypto.so.3 libkrb5support.so.0 ;;
    heimdal)    # Heimdal 7.7.1's nine libraries (Ubuntu's OpenLDAP links Heimdal's gssapi). asn1_compile and slc are
                # built for the build host first; com_err is e2fsprogs', sqlite the image's. Installed apart from
                # staging, which keeps MIT's headers, and only the libraries copied in.
        d=$(src heimdal-7.7.1.tar.gz heimdal-7.7.1)
        hopts="--disable-otp --disable-pk-init --disable-kx509 --disable-afs-support --without-libedit --without-readline
            --without-berkeley-db --disable-mdb-db --without-openssl --without-openldap --disable-heimdal-documentation"
        mkdir -p "$d/build-host" "$HOST/heimdal"
        # shellcheck disable=SC2086  # hopts is a word list
        (cd "$d/build-host" && native ../configure --prefix="$HOST/usr" --disable-shared --enable-static $hopts >/dev/null &&
         for sub in include lib/roken lib/vers lib/com_err; do native make -C $sub >/dev/null || exit 1; done &&
         native make -C lib/asn1 asn1_compile >/dev/null && native make -C lib/sl slc >/dev/null &&
         cp -f lib/asn1/asn1_compile lib/sl/slc "$HOST/heimdal/" && cp -f "$HOST/usr/bin/compile_et" "$HOST/heimdal/") ||
            die "heimdal: build-host tools failed"
        # shellcheck disable=SC2086
        (cd "$d" && ./configure --host=$TRIPLET --prefix=/usr --sysconfdir=/etc --disable-static \
            --with-cross-tools="$HOST/heimdal/" --with-sqlite3="$STAGE/usr" $hopts >/dev/null &&
         make -j"$JOBS" -C include >/dev/null && make -j"$JOBS" -C lib >/dev/null &&
         make -C lib DESTDIR="$WORK/heimdal-dest" install >/dev/null &&
         cp -af "$WORK"/heimdal-dest/usr/lib/lib{asn1,gssapi,hcrypto,heimbase,heimntlm,hx509,krb5,roken,wind}.so.* \
            "$STAGE/usr/lib/") || die "heimdal: build failed"
        ship_lib libasn1.so.8 libgssapi.so.3 libhcrypto.so.4 libheimbase.so.1 libheimntlm.so.0 libhx509.so.5 \
                 libkrb5.so.26 libroken.so.18 libwind.so.0 ;;
    cyrussasl)  # libsasl2.so.2 alone, as the Flip's: its mechanisms are plugins loaded at run time, none in the set
        d=$(src cyrus-sasl-2.1.28.tar.gz cyrus-sasl-2.1.28)
        ac_build "$d" --disable-sample --disable-cram --disable-digest --disable-scram --disable-otp --disable-gssapi \
            --disable-plain --disable-anon --with-dblib=none --without-openssl --without-saslauthd --without-authdaemond \
            --without-pwcheck --disable-macos-framework
        ship_lib libsasl2.so.2 ;;
    openldap)   # liblber-2.4.so.2 and libldap_r-2.4.so.2 with Cyrus SASL and GnuTLS (the image's), libraries only
        d=$(src openldap-2.4.59.tgz openldap-2.4.59)
        fresh_config "$d"
        (cd "$d" && ac_cv_func_memcmp_working=yes ./configure --host=$TRIPLET --prefix=/usr --sysconfdir=/etc \
            --disable-static --disable-slapd --with-tls=gnutls --with-cyrus-sasl --with-threads \
            --with-yielding-select=yes --enable-ipv6 >/dev/null && make depend >/dev/null &&
         make -j"$JOBS" -C libraries >/dev/null && make -C libraries DESTDIR="$STAGE" install >/dev/null &&
         make -C include DESTDIR="$STAGE" install >/dev/null) || die "openldap: build failed"
        ship_lib liblber-2.4.so.2 libldap_r-2.4.so.2 ;;
    libgpgerror)
        d=$(src libgpg-error-1.47.tar.bz2 libgpg-error-1.47)
        ac_build "$d" --disable-doc --disable-tests --disable-nls --disable-languages
        ship_lib libgpg-error.so.0 ;;
    libgcrypt)  # the 1.8 line (libgcrypt.so.20, the Flip's 1.8.5), against the shipped libgpg-error
        d=$(src libgcrypt-1.8.11.tar.bz2 libgcrypt-1.8.11)
        ac_build "$d" --disable-doc --with-libgpg-error-prefix="$STAGE/usr"
        ship_lib libgcrypt.so.20 ;;
    sdl2image)  # 2.8: the Flip's has the 2.6 API (AVIF, animations) the vendor's 2.0 lacks. stb_image for PNG and
                # JPEG as upstream builds it; WebP, AVIF and TIFF through the shipped libraries, loaded at run time
        d=$(src SDL2_image-2.8.2.tar.gz SDL2_image-2.8.2)
        ac_build "$d" --disable-sdltest --disable-jxl --disable-qoi-shared
        ship_lib libSDL2_image-2.0.so.0 ;;
    sdl2mixer)  # 2.8 with its built-in decoders (stb_vorbis, dr_flac, minimp3, timidity); libxmp, opusfile,
                # wavpack and libgme loaded at run time, as upstream builds it
        d=$(src SDL2_mixer-2.8.0.tar.gz SDL2_mixer-2.8.0)
        ac_build "$d" --disable-sdltest --disable-music-midi-fluidsynth
        ship_lib libSDL2_mixer-2.0.so.0 ;;
    sdl2ttf)    # 2.22 with its bundled FreeType and HarfBuzz, as the Flip's, so the image's FreeType 2.6.1 does not
                # cap its API (its exports come from the bundled copies too)
        d=$(src SDL2_ttf-2.22.0.tar.gz SDL2_ttf-2.22.0)
        ac_build "$d" --disable-sdltest --enable-freetype-builtin --enable-harfbuzz-builtin
        ship_lib libSDL2_ttf-2.0.so.0 ;;
    libxcrypt)  # libcrypt.so.1 with libxcrypt's XCRYPT_* versions, which the Flip's has and glibc's lacks. Built
                # last, so nothing in the set links it: a process that already holds glibc's libcrypt.so.1 would
                # then fail on those versions. Its GLIBC_2.17 compatibility versions serve the rest.
        d=$(src libxcrypt-4.4.36.tar.xz libxcrypt-4.4.36)
        ac_build "$d" --enable-obsolete-api=glibc --enable-hashes=all --disable-werror
        ship_lib libcrypt.so.1 ;;
    *) die "unknown package: $p" ;;
    esac
}

for p in $PKGS; do
    build_one "$p" > "$OUT/logs/$p.log" 2>&1 || { tail -30 "$OUT/logs/$p.log" >&2; die "$p failed (log: $OUT/logs/$p.log)"; }
    # libtool archives name /usr/lib, which a later cross link would resolve on the build host
    if [ "$PORTS_SET" = flip ]; then find "$STAGE" -name '*.la' -delete; fi
    log "$p ok"
done

# FLIP SET: exactly FLIP_SHIP ships: the Flip's libraries, less five the image has in equal form (libatomic, libbz2,
# libmad, libnsl, libpcre), plus what they need that it lacks. FLIP_LINKS adds the Flip's other file names.
FLIP_SHIP="libavcodec.so.58 libavformat.so.58 libavutil.so.56 libswresample.so.3 libswscale.so.5
libboost_filesystem.so.1.71.0 libjpeg.so.8 liblzma.so.5 libmodplug.so.1 libmp3lame.so.0 libmpg123.so.0 libogg.so.0
libopenal.so.1 libpng16.so.16 libpulse-simple.so.0 libpulse.so.0 libpulsecommon-13.99.so libtheoradec.so.1
libvorbis.so.0 libvorbisfile.so.3 libvpx.so.8 libwebp.so.7 libzstd.so.1
libapparmor.so.1 libasyncns.so.0 libsystemd.so.0 libwrap.so.0
libasn1.so.8 libbrotlicommon.so.1 libbrotlidec.so.1 libcom_err.so.2 libgssapi.so.3 libgssapi_krb5.so.2
libhcrypto.so.4 libheimbase.so.1 libheimntlm.so.0 libhogweed.so.5 libhogweed.so.6 libhx509.so.5 libidn2.so.0
libk5crypto.so.3 libkeyutils.so.1 libkrb5.so.26 libkrb5.so.3 libkrb5support.so.0 liblber-2.4.so.2
libldap_r-2.4.so.2 libnettle.so.7 libnettle.so.8 libnghttp2.so.14 libp11-kit.so.0 libpsl.so.5 libroken.so.18
libsasl2.so.2 libtasn1.so.6 libunistring.so.2 libwind.so.0
libICE.so.6 libSDL2_gfx-1.0.so.0 libSDL2_net-2.0.so.0 libSM.so.6 libX11.so.6 libXau.so.6 libXcursor.so.1
libXdmcp.so.6 libXext.so.6 libXfixes.so.3 libXi.so.6 libXrandr.so.2 libXrender.so.1 libXss.so.1 liba52-0.7.4.so
libavif.so.16 libcairo.so.2 libdav1d.so.6 libdecor-0.so.0 libfaad.so.2 libfribidi.so.0 libgif.so.7 libgme.so.0
libicudata.so.63 libicui18n.so.63 libicuuc.so.63 liblcf.so.0 liblz4.so.1 libmikmod.so.3 libmpeg2.so.0
libopenmpt.so.0 libopus.so.0 libopusfile.so.0 libpixman-1.so.0 libpython3.10.so.1.0 libpython3.so
libspeechd.so.2 libspeex.so.1 libtcl8.6.so libtiff.so.5 libtk8.6.so libvorbisidec.so.1 libvpx.so.4 libvpx.so.6
libvpx.so.7 libwavpack.so.1 libwayland-client.so.0 libwayland-cursor.so.0 libwayland-egl++.so.1
libwayland-egl.so.1 libwebpdemux.so.2 libxcb-render.so.0 libxcb-shm.so.0 libxcb.so.1 libxkbcommon.so.0
libxmp.so.4 libzip.so.5
libbsd.so.0 libfontconfig.so.1 libtheoraenc.so.1 libvorbisenc.so.2
libSDL2_image-2.0.so.0 libSDL2_mixer-2.0.so.0 libSDL2_ttf-2.0.so.0 libcrypt.so.1 libgnutls.so.30 libssl.so.1.1
libcrypto.so.1.1 libgcrypt.so.20 libgpg-error.so.0 libgmp.so.10 libffi.so.7"
FLIP_LINKS="libwebp.so.7.5.0=libwebp.so.7 libwebp.so.1.0.3=libwebp.so.7 libwebpdemux.so.2.6.0=libwebpdemux.so.2"
# what the set may need from the image beyond the base system (checked against the real rootfs by build.sh)
IMAGE_OK="libexpat.so.1 libglib-2.0.so.0 libsqlite3.so.0 libsndfile.so.1 libuuid.so.1 libbz2.so.1.0 libcrypt.so.1
libnsl.so.1 libresolv.so.2 libutil.so.1 libfreetype.so.6 libasound.so.2 libSDL2-2.0.so.0 libatomic.so.1"
if [ "$PORTS_SET" = flip ]; then
    for f in "$OUT"/lib/*; do
        case " $(echo $FLIP_SHIP) " in *" $(basename "$f") "*) ;; *) rm -f "$f" ;; esac
    done
    for l in $FLIP_LINKS; do
        if [ -e "$OUT/lib/${l#*=}" ]; then ln -sfn "${l#*=}" "$OUT/lib/${l%%=*}"; fi
    done
fi

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
if [ "$PKGS" = "$SET_PKGS" ]; then
    log "checking that nothing needs a library outside this tree and the base system"
    SYSTEM_OK="libc.so.6 libm.so.6 libdl.so.2 libpthread.so.0 librt.so.1 ld-linux-aarch64.so.1 libgcc_s.so.1 libstdc++.so.6 libz.so.1"
    if [ "$PORTS_SET" = flip ]; then SYSTEM_OK="$SYSTEM_OK $(echo $IMAGE_OK)"; fi
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
