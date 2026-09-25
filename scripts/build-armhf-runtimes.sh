#!/usr/bin/env bash
# Rebuild PortMaster's armhf Godot/FRT runtime squashfs images against the
# Miyoo A30's glibc 2.23 floor, with the same arm-a30 toolchain
# build-armhf-userland.sh uses (GCC 13.2, glibc 2.23 sysroot, inside the
# `cores-armhf:latest` image cores-experimental already builds).
#
#   scripts/build-armhf-runtimes.sh frt <godot-version> [frt-ref]
#   scripts/build-armhf-runtimes.sh godot4 <godot-version>
#
#   frt godot-version    e.g. 3.5.2 -- a godotengine/godot X.Y.Z-stable tag.
#                         PortMaster's frt_X.Y.Z runtimes are FRT's own
#                         "platform/frt" module dropped into that exact Godot
#                         3 tag and built with `scons platform=frt`.
#   frt-ref               git ref (tag/branch/commit) of efornara/frt to use
#                         as platform/frt. Default: a pinned commit of the
#                         CURRENT frt module (see FRT_REF_DEFAULT below).
#                         THIS IS A KNOWN GAP, not a pinned reproduction: the
#                         historical platform/frt source that shipped inside
#                         each PortMaster frt_X.Y.Z release (2017-2023) is
#                         preserved only in efornara's old SourceForge
#                         release archives (project "frt"), not in git tags -
#                         efornara/godot3's own "frt" branch history only
#                         goes back to the 3.6.x line. Building today's
#                         platform/frt against an old Godot tag is a
#                         best-effort compatibility bet, not a byte-identical
#                         rebuild. If it fails to compile against an old tag,
#                         that is exactly the kind of finding this script
#                         should surface, not paper over.
#
#   godot4 godot-version  e.g. 4.4.1 -- a godotengine/godot X.Y[.Z]-stable
#                         tag, built for `platform=linuxbsd` (the platform
#                         PortMaster's own godot_4.x.armhf.squashfs runtimes
#                         use - confirmed from the shipped binaries: they are
#                         "N.N.N.stable.official" export templates carrying
#                         DisplayServerX11/DisplayServerWayland strings and no
#                         framebuffer/DRM display server at all).
#
#                         KNOWN DEAD END ON THE A30, INDEPENDENT OF GLIBC:
#                         vanilla Godot 4's linuxbsd platform only ships X11
#                         and Wayland DisplayServer backends. There is no
#                         upstream "FRT for Godot 4". The A30 has neither an
#                         X server nor a Wayland compositor, and see PART 2
#                         below: no /dev/dri either, so even a hypothetical
#                         KMS-based DisplayServer has nothing to open. This
#                         track is kept in the script for completeness (it
#                         DOES get you a glibc-2.23 Godot 4 binary, which is
#                         useful e.g. for a future aarch64-with-X11 target)
#                         but will NOT display anything on the A30 as built.
#                         Do not run it expecting an A30 payoff; see the
#                         report this script's spec asked for.
#
# ---------------------------------------------------------------------------
# PART 1 -- WHY glibc 2.23 IS REACHABLE AT ALL (frt track)
#
# elfscan.py + readelf -V on the 13 shipped armhf runtimes
# (common/pm/runtimes/{frt,godot}_*.armhf.squashfs) show two different
# situations behind the same-looking "needs GLIBC_2.28/2.34" floor:
#
#  * frt_2.1.6 .. frt_3.5.3 (Godot 3, GLIBC_2.34 floor): EVERY GLIBC_2.34
#    symbol they import (dlopen/dlclose/dlerror/dlsym, __libc_start_main,
#    pthread_mutex_trylock, pthread_rwlock_{rd,wr}lock/unlock,
#    pthread_setname_np) is one of the functions glibc 2.34 merged out of
#    libpthread/libdl into libc itself. The merge is why the *default*
#    symbol version jumped to 2.34; none of these functions are new -
#    dlopen and pthread_rwlock_rdlock have existed since the 1990s. Rebuilt
#    against a pre-2.34, still-split glibc (2.23 here), the same calls
#    resolve to the old default versions and need nothing newer. (stat/
#    lstat show up at GLIBC_2.33 for the same reason - a Y2038 symbol-
#    versioning bump, not a new function.) NET: the 2.34 floor on the FRT
#    track is a linker artifact, not a real API dependency. A straight
#    rebuild against 2.23 is expected to resolve cleanly.
#
#  * frt_3.6 (GLIBC_2.28 floor): fcntl@GLIBC_2.28 is the same kind of
#    artifact (an LFS/large-file symbol-versioning bump). getentropy@2.25
#    is NOT: glibc 2.23 (2016) predates the getrandom(2) glibc wrapper
#    entirely (added in glibc 2.25, 2017), and the A30's own kernel (3.4.39,
#    ~2012-vintage) may predate the getrandom(2) SYSCALL too (added in
#    Linux 3.17, 2014 - unconfirmed on this exact kernel build; check before
#    relying on it). NUANCE FROM THE TRIAL BUILD: platform/frt/frt_godot.cc's
#    own OS::get_entropy() override reads /dev/urandom directly and does NOT
#    call glibc's getentropy() - so this specific symbol is NOT coming from
#    FRT's own code. It is somewhere else in Godot 3.6/4.x core (crypto_core,
#    RandomPCG seeding, or the bundled mbedtls's entropy source are the
#    likely places; not tracked down in this pass). Either way: if the call
#    survives being probed/optional, relinking against 2.23 fails to find
#    getentropy at all (not a version mismatch - the symbol does not exist),
#    which is a real gap, not a cosmetic one; find the call site before
#    assuming a plain relink clears it.
#
#  * godot_4.2.2 .. godot_4.5 (GLIBC_2.28 floor): fcntl64/fcntl/statx@2.28
#    are LFS/Y2038 artifacts (harmless to relink). getentropy/getrandom@2.25
#    and explicit_bzero@2.25 are the same real gap as frt_3.6's, and appear
#    to come from Godot's own core (crypto/OS entropy paths) and/or the
#    bundled mbedtls, not from a system library choice. This is on top of
#    the X11/Wayland-only display problem above, so the godot4 track needs
#    BOTH a source patch for entropy calls AND a new display backend before
#    it is a real A30 option; it is not attempted in this pass beyond
#    "does it compile".
#
# PART 2 -- CAN THE A30'S GRAPHICS STACK SERVE WHAT SURVIVES?
#
# From results/A30-*.json (round-9 audit dump), read straight off the
# device, not inferred:
#   - /usr/lib/libEGL.so -> libEGL.so.1 -> libEGL.so.1.4 -> libMali.so
#     /usr/lib/libGLESv2.so -> ... -> libMali.so
#     /usr/lib/libGLESv1_CM.so -> ... -> libMali.so
#     /usr/lib/libUMP.so.3 (ARM's Mali "UMP" memory allocator)
#     i.e. a real, vendor-shipped Mali EGL/GLES2/GLES1 stack IS present
#     system-wide (no per-app bundling needed) - this is an old
#     "UMP"-generation Mali-4xx blob (pre-DRM), not a modern Mali GBM/DRM one.
#   - meta.dri = "" (empty) and no libdrm.so anywhere on the device's own
#     rootfs (a libdrm.so.2 does exist, but only bundled inside one emulator's
#     own lib32/, not a system library) - there is NO /dev/dri node. KMSDRM
#     is off the table.
#   - FRT does not talk to fbdev/DRM directly: sdl2_adapter.h shows FRT's
#     windowing is 100% SDL_CreateWindow/SDL_GL_CreateContext - i.e.
#     whatever SDL2 it links is the WHOLE story for display. Checked upstream
#     SDL 2.28.x's own src/video/: there is no generic "fbdev" backend in
#     modern SDL2 at all (it was dropped years ago); the realistic options
#     for a DRM-less Mali-UMP board are x11/wayland (absent here) or a
#     board-specific driver (e.g. "pandora", written for a different Mali
#     fbdev variant) - none of which fit this device out of the box.
#   - BUT the device already runs real GLES2 content today: results/A30-*.json
#     shows /mnt/SDCARD/spruce/a30/sdl2/libSDL2-2.0.so.0, origin "shipped",
#     repo_path "miyoo/lib/libSDL2-2.0.so.0" - i.e. this is the ORIGINAL
#     MIYOO VENDOR FIRMWARE's own SDL2 (RetroArch, PPSSPP etc. run against
#     it on real hardware), not something oakMOSS builds. Whatever private
#     video driver it was built with talks to this exact Mali/UMP stack
#     successfully; we do not have its source. See DO NOT REBUILD SDL2 below.
#
# CONCLUSION: for the frt track, link against libSDL2-2.0.so.0 by SONAME
# only (headers + .so stub from the arm-a30 sysroot, which already carries a
# full SDL2 2.28.5 dev set - see the linking section). Do NOT bundle any
# SDL2 .so with the runtime, and do NOT try to rebuild SDL2 from upstream
# source: upstream SDL2 has nothing that drives this Mali-UMP glass without
# X11/Wayland/DRM, and the device's own vendor SDL2 already does. At runtime
# on the card, ordinary dynamic linking resolves libSDL2-2.0.so.0 against
# whatever is first on the port's LD_LIBRARY_PATH - today that is the
# device's proven-working vendor copy. SDL2's own ABI/symbol-versioning
# policy makes building against 2.28.5 headers while running against an
# older device .so a reasonable bet, but it is NOT verified in this pass -
# put it on the device round with LD_DEBUG=libs before trusting it.
#
# PART 3 -- THIS SCRIPT
#
# Same shape as build-armhf-userland.sh: everything past the re-exec block
# runs inside `docker run --rm cores-armhf:latest`, two bind mounts only
# (this checkout read-only, the output+inputs trees read-write), image never
# built or modified. Unlike that script, this one also needs network
# (cloning godotengine/godot and efornara/frt) and two tools the image does
# not carry: scons and squashfs-tools. Both are `apt-get install`ed INSIDE
# the throwaway container on every run - nothing is committed to the image,
# and if there is no network the script fails loudly instead of silently
# reusing a stale toolchain.
#
# PART 4 -- TRIAL RESULT (frt/3.5.2, 2026-09-21, this session)
#
# Ran this recipe for real. It does NOT succeed end to end yet; three real
# problems were found and worked through in order, each now folded into the
# script above:
#   1. sdl2-config not on PATH (it lives in $SYSROOT/usr/bin, not $TC/) -
#      fixed (PATH line below).
#   2. git "dubious ownership" silently discarding a local patch to a
#      fetched tree and falling back to a fresh re-clone, no error printed -
#      fixed (safe.directory line below). Found the hard way: a one-line
#      compat patch to platform/frt/detect.py got silently reverted twice
#      before this was diagnosed.
#   3. GLES3/gl3.h missing from the sysroot - fixed (GLES3 header fetch
#      below).
# Past those three, scons reached real compilation: hundreds of Godot core,
# Bullet physics and FreeType object files built cleanly against the arm-a30
# 2.23 toolchain with no glibc-related errors at all - i.e. the PART 1
# thesis (the floor is mostly a linker artifact) held up as far as the
# compiler is concerned. It then failed for a NEW, genuine reason, not a
# glibc one and not anticipated above:
#
#   platform/frt/frt_godot.cc:194:15: error: 'Error
#   frt::Godot3_OS::get_entropy(uint8_t*, int)' marked 'override', but does
#   not override
#
# efornara/frt's CURRENT platform/frt module (this script's FRT_REF_DEFAULT)
# implements an OS::get_entropy() override that Godot 3.5.2's own core/os/os.h
# does not declare - that virtual was added to Godot's OS interface at some
# later 3.x point (present by the time of the 3.6.x line frt/master now
# tracks; the exact version it landed was not pinned down in this pass). This
# is precisely the "best-effort, not pinned" gap the FRT_REF documentation
# above warns about, now with a concrete example: HEAD's platform/frt is not
# source-compatible with every historical Godot 3 tag PortMaster's frt_X.Y.Z
# runtimes were built against, and the incompatibility is API drift in
# Godot's OS class, not anything toolchain- or glibc-related.
#
# NOT reached this pass (blocked by the above): a completed link, a squashfs,
# or running the binary against anything. The SDL2-SONAME-only linking
# approach (PART 2) and the use_static_cpp=yes libstdc++ approach are
# therefore also still unverified - they were never exercised.
#
# Output: $OUT/<track>_<version>.armhf.squashfs, BUILD-INFO, logs/.
# Sources: fetched into $INPUTS_DIR/runtimes-armhf/{godot,frt}-<ref>/ and
# reused across runs (git clone --reuse, not re-fetched if already present
# and clean).
. "$(dirname "$0")/lib.sh"

TRACK=${1:?"usage: $0 <frt|godot4> <godot-version> [frt-ref]"}
GODOT_VERSION=${2:?"usage: $0 <frt|godot4> <godot-version> [frt-ref]"}
FRT_REF_DEFAULT=01e53178e8aabd515bf327b27f847e3bb8b15251   # efornara/frt master, captured 2026-09-21
FRT_REF=${3:-$FRT_REF_DEFAULT}

case $TRACK in
    frt|godot4) ;;
    *) die "unknown track: $TRACK (expected frt or godot4)" ;;
esac

SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
DOCKER_IMAGE_ARMHF=${DOCKER_IMAGE_ARMHF:-cores-armhf:latest}

RUNTIME_NAME=${TRACK}_${GODOT_VERSION}
OUT=${OUT:-$BUILDS_DIR/$(stamp)-armhf-runtime-$RUNTIME_NAME}
SRC_DIR=${SRC_DIR:-$INPUTS_DIR/runtimes-armhf}
mkdir -p "$OUT"/{logs,work} "$SRC_DIR"

# ---- re-exec inside the A30 toolchain image, same pattern as
# build-armhf-userland.sh (see that script's header for why the mounts are
# shaped this way). This lane ALSO mounts SRC_DIR read-write (sources are
# fetched fresh over the network, not staged from a pinned tarball set) and
# needs network on, which build-armhf-userland.sh's lane does not.
if [ "${OAKMOSS_IN_ARMHF_IMAGE:-}" != 1 ]; then
    command -v docker >/dev/null || die "docker not found on host"
    docker image inspect "$DOCKER_IMAGE_ARMHF" >/dev/null 2>&1 \
        || die "no local image $DOCKER_IMAGE_ARMHF (build it in cores-experimental: docker build -f Dockerfile.armhf.base -t $DOCKER_IMAGE_ARMHF .)"
    log "re-exec inside $DOCKER_IMAGE_ARMHF (out: $OUT)"
    exec docker run --rm \
        -e OAKMOSS_IN_ARMHF_IMAGE=1 -e JOBS="$JOBS" -e OUT="$OUT" \
        -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
        -v "$OAKMOSS_ROOT:$OAKMOSS_ROOT:ro" \
        -v "$OUT:$OUT" \
        -v "$SRC_DIR:$SRC_DIR" \
        "$DOCKER_IMAGE_ARMHF" \
        bash "$SELF" "$TRACK" "$GODOT_VERSION" "$FRT_REF"
fi
# Everything the container writes lands root:root on the host (it runs as
# root; see build-armhf-userland.sh's header for the same tradeoff). Hand it
# back at the very end, on every exit path, so a human - or the next run of
# this script, editing a fetched tree between attempts, as the 2026-09-21
# trial run needed - is not immediately hit by git's "dubious ownership"
# refusal (see the safe.directory line above; that fixes git INSIDE this
# container, not host-side access afterwards).
trap '[ "${OAKMOSS_IN_ARMHF_IMAGE:-}" = 1 ] && [ -n "${HOST_UID:-}" ] && chown -R "$HOST_UID:$HOST_GID" "$OUT" "$SRC_DIR" 2>/dev/null; true' EXIT

# ---- from here on we are inside the container -----------------------------
# scons + squashfs-tools are not in cores-armhf:latest (checked: neither is
# installed, and mksquashfs/unsquashfs are absent even on the oakMOSS host -
# 7z reads these squashfs images for inspection, but nothing here can WRITE
# one without this). Installed fresh into the throwaway container only.
log "installing scons + squashfs-tools (container-local, not baked into the image)"
apt-get update -qq > "$OUT/logs/apt.log" 2>&1 \
    && apt-get install -y --no-install-recommends scons squashfs-tools git-core \
        >> "$OUT/logs/apt.log" 2>&1 \
    || die "apt-get install failed (no network in the container? see $OUT/logs/apt.log)"
command -v scons >/dev/null || die "scons still not on PATH after install"
command -v mksquashfs >/dev/null || die "mksquashfs still not on PATH after install"

# The container runs as root; $SRC_DIR is a host bind mount that git (2.35+)
# treats as "dubious ownership" once anything outside the container has
# chowned it back to the host user (e.g. for inspecting/patching a fetched
# tree between runs) - without this, every later `git` call in that tree
# fails closed and fetch_ref/fetch_tag fall back to a fresh clone,
# SILENTLY CLOBBERING any such local changes (confirmed: this is not
# hypothetical, it ate a one-line compat patch mid-trial the first time).
# git's safe.directory list does NOT glob ("dir/*" matches nothing); only a
# bare "*" trusts every path, which is fine in a throwaway, --rm container.
git config --global --add safe.directory '*'

TC=/opt/a30/bin
TRIPLET=arm-a30-linux-gnueabihf
SYSROOT=/opt/a30/$TRIPLET/sysroot
[ -x "$TC/$TRIPLET-gcc" ] || die "no A30 toolchain at $TC (expected inside $DOCKER_IMAGE_ARMHF)"
# sdl2-config lives in the SYSROOT's own usr/bin (it is a target-side dev
# tool the toolchain ships inside the sysroot, not a $TC/ cross-binary), so
# it needs its own PATH entry -- easy to miss since every other tool this
# script calls is a $TC/$TRIPLET-* prefixed binary.
export PATH="$TC:$SYSROOT/usr/bin:$PATH"

BUILD_ALIAS=/build                          # fixed, neutral path -- see build-armhf-userland.sh
mkdir -p "$OUT/work"
ln -sfn "$OUT/work" "$BUILD_ALIAS"
WORK=$BUILD_ALIAS

# ---- fetch sources (shallow, pinned by tag or ref; reused across runs) ----
fetch_tag() {  # fetch_tag <dest> <repo-url> <tag>
    local dest=$1 url=$2 tag=$3
    if [ -d "$dest/.git" ]; then
        log "reusing $dest"
        return
    fi
    rm -rf "$dest"
    log "cloning $url @ $tag -> $dest"
    git clone --depth 1 --branch "$tag" "$url" "$dest" \
        || die "clone failed: $url @ $tag (tag typo? network down? check the tag exists: git ls-remote --tags $url)"
}

fetch_ref() {  # fetch_ref <dest> <repo-url> <ref-or-sha> : full clone, then checkout (a bare sha is not a fetchable ref on most servers without --depth games)
    local dest=$1 url=$2 ref=$3
    if [ -d "$dest/.git" ] && git -C "$dest" cat-file -e "$ref^{commit}" 2>/dev/null; then
        log "reusing $dest @ $ref"
        git -C "$dest" checkout -q "$ref"
        return
    fi
    rm -rf "$dest"
    log "cloning $url -> $dest, checking out $ref"
    git clone -q "$url" "$dest" || die "clone failed: $url"
    git -C "$dest" checkout -q "$ref" || die "no such ref in $url: $ref"
}

GODOT_TAG=${GODOT_VERSION}-stable
GODOT_SRC=$SRC_DIR/godot-$GODOT_TAG
fetch_tag "$GODOT_SRC" https://github.com/godotengine/godot "$GODOT_TAG"

if [ "$TRACK" = frt ]; then
    FRT_SRC=$SRC_DIR/frt-${FRT_REF}
    fetch_ref "$FRT_SRC" https://github.com/efornara/frt "$FRT_REF"
    rm -rf "$GODOT_SRC/platform/frt"
    cp -a "$FRT_SRC" "$GODOT_SRC/platform/frt"
    rm -rf "$GODOT_SRC/platform/frt/.git"
fi

# ---- GLES3 headers: the sysroot ships GLES/GLES1/GLES2 (matching the task's
# framing: FRT on these boards targets GLES2) but NOT GLES3, and FRT's own
# SCsub unconditionally compiles a GLES3 dlopen-stub file alongside the GLES2
# one regardless of platform. These are the plain public Khronos headers
# (type/enum/prototype declarations only, no ABI link against a real
# libGLESv3 - the dlopen stub resolves symbols at runtime, if at all) fetched
# once and dropped into the sysroot's include tree for this container only;
# nothing is added to the persisted image. Confirmed necessary and
# sufficient by trial (2026-09-21, frt/3.5.2): without this the build fails
# at platform/frt/dl/gles3.gen.h:10: fatal error: GLES3/gl3.h: No such file.
GLES3_DIR=$SYSROOT/usr/include/GLES3
if [ ! -f "$GLES3_DIR/gl3.h" ]; then
    mkdir -p "$GLES3_DIR"
    for h in gl3.h gl3platform.h; do
        wget -q -T 30 "https://raw.githubusercontent.com/KhronosGroup/OpenGL-Registry/main/api/GLES3/$h" \
            -O "$GLES3_DIR/$h" \
            || die "could not fetch Khronos GLES3/$h (network down in the container? cores-armhf:latest has wget, not curl)"
    done
fi

# ---- SDL2 for the frt track: headers + SONAME stub only, from the
# toolchain's own sysroot (2.28.5). Deliberately NOT rebuilt -- see PART 2
# above for why upstream SDL2 has no usable video backend for this board and
# the device's own vendor SDL2 does. `sdl2-config` in the sysroot already
# points at $SYSROOT, which is exactly what frt's SCsub calls
# (`frt_env.ParseConfig('sdl2-config --cflags --libs')`), so nothing extra
# is needed on PATH beyond what $TC already provides.
[ -x "$SYSROOT/usr/bin/sdl2-config" ] || die "no sdl2-config in $SYSROOT (toolchain image changed?)"

# ---- build -----------------------------------------------------------------
case $TRACK in
frt)
    log "building FRT platform=frt godot=$GODOT_VERSION frt_ref=$FRT_REF"
    # use_static_cpp=yes: the device's stock /lib/libstdc++.so.6 is only
    # GLIBCXX_3.4.22 (from results/A30-*.json); the toolchain's own libstdc++
    # is 13.2 / GLIBCXX_3.4.32. Rather than betting on spruce/a30/lib's newer
    # libstdc++.so.6 being first on every port's path (build list #8, not
    # shipped yet), statically link libgcc/libstdc++ into the binary and
    # remove that dependency entirely -- one fewer axis of "does the path
    # order happen to be right" risk for a first build.
    (cd "$GODOT_SRC" && scons \
        platform=frt tools=no target=release \
        triple=$TRIPLET arch=arm32 bits=32 \
        use_static_cpp=yes \
        verbose=yes warnings=no progress=no production=yes \
        LINKFLAGS=-s \
        -j"$JOBS") 2>&1 | tee "$OUT/logs/scons.log"
    BIN=$(find "$GODOT_SRC/bin" -maxdepth 1 -type f -name 'godot.frt.*' | head -1)
    [ -n "$BIN" ] && [ -f "$BIN" ] || die "scons did not produce bin/godot.frt.* (see $OUT/logs/scons.log)"
    ;;
godot4)
    log "building official linuxbsd platform godot=$GODOT_VERSION (WILL NOT DISPLAY ON THE A30 -- see PART 1/2 above)"
    (cd "$GODOT_SRC" && scons \
        platform=linuxbsd tools=no target=template_release \
        arch=arm32 \
        use_static_cpp=yes \
        production=yes \
        LINKFLAGS=-s \
        -j"$JOBS") 2>&1 | tee "$OUT/logs/scons.log"
    BIN=$(find "$GODOT_SRC/bin" -maxdepth 1 -type f -name 'godot.linuxbsd.*' | head -1)
    [ -n "$BIN" ] && [ -f "$BIN" ] || die "scons did not produce bin/godot.linuxbsd.* (see $OUT/logs/scons.log)"
    ;;
esac

# ---- glibc floor check, same convention as build-armhf-userland.sh --------
log "glibc floor of the built binary (>2.23 means the rebuild did not do its job)"
GLIBC_FLOOR=$(readelf -V "$BIN" 2>/dev/null | grep -oE 'GLIBC_2\.[0-9]+' | sort -t. -k2 -n | tail -1)
printf '%-40s %s\n' "$(basename "$BIN")" "${GLIBC_FLOOR:-none}" | tee "$OUT/logs/glibc-version.txt"
case "$GLIBC_FLOOR" in
    ""|GLIBC_2.0|GLIBC_2.1*|GLIBC_2.2[0-3]) : ;;   # at or under 2.23, good
    *) warn "binary still needs $GLIBC_FLOOR > 2.23 -- rebuild did not clear the floor; see $OUT/logs/scons.log and re-run the symbol analysis (readelf --dyn-syms --wide \"$BIN\" | grep 'GLIBC_2\\.[3-9]')" ;;
esac

# ---- package: strip, rpath (frt only -- links a real .so), gzip squashfs --
STRIP=$TRIPLET-strip
"$STRIP" --strip-unneeded "$BIN" || true
if [ "$TRACK" = frt ]; then
    # FRT's binary has no bundled .so beside it (SDL2/z/pthread/dl/c/m all
    # come from the port's system/lib path at runtime -- see PART 2), so
    # there is nothing to rpath here; keep whatever the toolchain set (it
    # sets none, per build-armhf-userland.sh's header comment) rather than
    # inventing one with nothing to point at.
    :
fi

PKG_DIR=$OUT/pkg
mkdir -p "$PKG_DIR"
OUT_NAME=$RUNTIME_NAME.armhf
cp -f "$BIN" "$PKG_DIR/$OUT_NAME"
mksquashfs "$PKG_DIR/$OUT_NAME" "$OUT/$RUNTIME_NAME.armhf.squashfs" \
    -comp gzip -no-xattrs -all-root -noappend \
    > "$OUT/logs/mksquashfs.log" 2>&1 \
    || die "mksquashfs failed (see $OUT/logs/mksquashfs.log)"

{
    echo "oakmoss=$(oakmoss_version)"
    echo "built=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "track=$TRACK godot_version=$GODOT_VERSION frt_ref=${FRT_REF:-n/a}"
    echo "toolchain=$("$TC/$TRIPLET-gcc" --version | head -1)"
    echo "toolchain_glibc=$(strings "$SYSROOT/lib/libc-2.23.so" | grep -m1 'release version' | tr -d '\n')"
    echo "binary_glibc_floor=${GLIBC_FLOOR:-none}"
    echo "binary_size=$(stat -c%s "$BIN")"
    echo "squashfs=$RUNTIME_NAME.armhf.squashfs"
} > "$OUT/BUILD-INFO"

log "done: $OUT/$RUNTIME_NAME.armhf.squashfs"
log "NOT verified on hardware: SDL2 resolution (PART 2), and (frt_3.6+/godot4 only) the getentropy/getrandom/explicit_bzero gap (PART 1)."
