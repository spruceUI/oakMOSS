# shellcheck shell=bash
# Shared settings for the oakMOSS build scripts. Sourced, never executed.
#
# Layout (all overridable through the environment):
#   OAKMOSS_ROOT   the git checkout (this file's grandparent)
#   OAKMOSS_WORK   where the big untracked trees live (default: the checkout;
#                  CI points it at a large scratch disk)
#     inputs/      downloaded archives (SDK zip, toolchain, Zero 40 object, main-zero40 image)
#     sdk/lichee   the unpacked Tina SDK (18 GB clean, ~30 GB built)
#     toolchains/  Arm GNU 13.3 + the Tina sysroot shim
#     tools/       OpenixCard built from source
#     builds/      outputs: <stamp>-<board>/ and logs/
set -euo pipefail

OAKMOSS_ROOT=${OAKMOSS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
OAKMOSS_WORK=${OAKMOSS_WORK:-$OAKMOSS_ROOT}
INPUTS_DIR=${INPUTS_DIR:-$OAKMOSS_WORK/inputs}
SDK_DIR=${SDK_DIR:-$OAKMOSS_WORK/sdk/lichee}
CCACHE_HOST_DIR=${CCACHE_HOST_DIR:-$OAKMOSS_WORK/sdk/.ccache}
TOOLCHAINS_DIR=${TOOLCHAINS_DIR:-$OAKMOSS_WORK/toolchains}
ARMGNU_DIR=$TOOLCHAINS_DIR/arm-gnu-13.3-aarch64
TOOLS_DIR=${TOOLS_DIR:-$OAKMOSS_WORK/tools}
BUILDS_DIR=${BUILDS_DIR:-$OAKMOSS_WORK/builds}
OPENIXCARD_BIN=${OPENIXCARD_BIN:-$TOOLS_DIR/openixcard/bin/OpenixCard}
DOCKER_IMAGE=${DOCKER_IMAGE:-oakmoss-tina-build:ubuntu18}
JOBS=${JOBS:-$(nproc)}
TOOLCHAIN=${TOOLCHAIN:-armgnu13}          # armgnu13 (supported) | vendor (phase1/phase2 fallback)

# ---- pinned inputs -------------------------------------------------------------
# Tina SDK from MagicX (proprietary, never in this repo). Linux_SDK.zip holds
# mplus_a133_tina_v1.0.tar.gz split in three parts; the md5 of the joined
# tarball is printed in the zip's own README and is the authoritative check.
TINA_SDK_ZIP=Linux_SDK.zip
TINA_SDK_ZIP_SHA256=5c731ae0b7fca6bb821982c2fa9963c5f8167ca8f33b02922435ba1540477b04   # advisory: the copy used here
TINA_SDK_TAR_MD5=957e9383dbfd7bcae98a4766bc1011bd                                     # authoritative (SDK README)
TINA_SDK_TAR_GLOB='mplus_a133_tina_v1.0.tar.gz.*'
SDK_ENCRYPT_ZERO28_MD5=f28d35ebe4929e4c916ab7095dffeae7   # the SDK's own sunxi_encrypt/encrypt object (Zero 28)

# Zero 40 kernel object from MagicX (proprietary, never in this repo).
ZERO40_LICHEE_ZIP=Zero40-lichee.zip
ZERO40_LICHEE_SHA256=63a29e2401b9124a6e1700ff7a33e20c80c95f178c8c7b83084aae22683ae72b
ZERO40_ENCRYPT_PATH=lichee/linux-4.9/drivers/char/sunxi_encrypt/encrypt
ZERO40_ENCRYPT_MD5=33a0a6d729e24ae34877a7cbdb479cbe

# Arm GNU Toolchain 13.3.Rel1 (public; checksum from Arm's .sha256asc).
ARMGNU_TARBALL=arm-gnu-toolchain-13.3.rel1-x86_64-aarch64-none-linux-gnu.tar.xz
ARMGNU_URL=https://developer.arm.com/-/media/Files/downloads/gnu/13.3.rel1/binrel/$ARMGNU_TARBALL
ARMGNU_SHA256=322f0b4482fc0d9fa0bb468134841f08d8c554c54ff5aa29a13a7a24bf7e1eb5

# GNU sources the SDK cannot fetch itself any more (dropped into sdk/lichee/dl).
NCURSES_TARBALL=ncurses-6.2.tar.gz
NCURSES_URL=https://ftp.gnu.org/gnu/ncurses/$NCURSES_TARBALL
NCURSES_SHA256=30306e0c76e0f9f1f0de987cf1c82a5c21e1ce6568b9227f7da5b71cbea86c9d
GCC750_TARBALL=gcc-7.5.0.tar.xz                     # phase-2 fallback toolchain only
GCC750_URL=https://ftp.gnu.org/gnu/gcc/gcc-7.5.0/$GCC750_TARBALL
GCC750_SHA256=b81946e7f01f90528a1f7352ab08cc602b9ccc05d4e44da4bd501c5a189ee661
BINUTILS228_TARBALL=binutils-2.28.tar.gz            # phase-2 fallback toolchain only
BINUTILS228_URL=https://ftp.gnu.org/gnu/binutils/$BINUTILS228_TARBALL
BINUTILS228_SHA256=cd717966fc761d840d451dbd58d44e1e5b92949d2073d75b73fccb476d772fcf

# Shaun Inman's main-zero40 release: the Zero 40 boot chain for the hybrid image.
MAINZERO40_VERSION=20260202-1
MAINZERO40_ZIP=main-zero40-$MAINZERO40_VERSION.img.zip
MAINZERO40_URL=https://github.com/dedicated-os/main-zero40/releases/download/v$MAINZERO40_VERSION/$MAINZERO40_ZIP
MAINZERO40_ZIP_SHA256=c34d24695b95188061d072e936b6bd6dbae237a78c39cc31bfff05e21f65e81f
MAINZERO40_IMG=main-zero40-$MAINZERO40_VERSION.img
MAINZERO40_IMG_SHA256=0790880fdc08bbbcb5bb4dcbe39ef7c436a7013994031aead31f95af906babe6

# OpenixCard (GPL-2.0), built from source at a pinned commit.
OPENIXCARD_REPO=https://github.com/YuzukiTsuru/OpenixCard
OPENIXCARD_COMMIT=b5a6ffccb2492a3f238d628089d9acd1f44ec7a0   # 1.1.8-13-gb5a6ffc, 2026-06-28

# ---- XU20 V32 (scripts/make-hybrid-xu20.sh) ----------------------------------------
# The stock firmware, published by MagicX for developers as a PhoenixSuit image
# (public GitHub release). Its boot chain, kernel, device tree and vendor modules
# are what the XU20 card reuses; none of it is redistributed here.
XU20_STOCK_ZIP=XU20_V32-user.zip
XU20_STOCK_URL=https://github.com/Magicx-Breeze/XU20_V32/releases/download/Developers/user.zip
XU20_STOCK_ZIP_SHA256=9b0c414d3f9f065a6c52e699301807103d22c4eb106e6825cdd3bfa167c85dd0
XU20_STOCK_IMG=user.img                                                                # inside the zip
XU20_STOCK_IMG_SHA256=99a3ccdab8eecbb7cfbb53e8736f4427a33bf8ebaeb33a6fab8cb1ac9b50f19d
XU20_STOCK_DIR=$INPUTS_DIR/xu20-stock                                                  # unpack-xu20-stock.sh output
# ---- Zero 40 stock firmware (scripts/make-hybrid-stock.sh zero40) ------------------
# MagicX's public "Static Adb Firmware" for the Zero 40: a raw 8 GB card image
# of the board's native Android (kernel 4.9.170 with MODVERSIONS, PowerVR DDK
# 1.11, XR829 radio), the same BSP as the XU20's developer release. Its boot0,
# boot package, boot image, device tree and vendor modules are what the
# zero40-stock card reuses; none of it is redistributed here.
ZERO40_STOCK_XZ=Zero40_V1-adb.img.xz
ZERO40_STOCK_URL=https://github.com/Magicx-Breeze/Zero40/releases/download/Zero40_V1/adb.img.xz
ZERO40_STOCK_XZ_SHA256=5ee40ba1449e47ddf545b289c5963545a1f7162078b396e3236ed876a910e5c5
ZERO40_STOCK_IMG=adb.img                                                               # decompressed, 8 000 000 000 bytes
ZERO40_STOCK_IMG_SHA256=5219dc6b9251a351c937427726185dc3798819b0b14d8d08e68fe505f6209646
ZERO40_STOCK_DIR=$INPUTS_DIR/zero40-stock                                              # unpack-zero40-stock.sh output
# awutils (GPL-2.0) unpacks that image: OpenixCard refuses its 0x0415 header
# version; tools-patches/awutils-imagewty-0x415.patch treats it as the 0x0300 layout.
AWUTILS_REPO=https://github.com/Ithamar/awutils
AWUTILS_COMMIT=3f1cbb2c67752b392a88b252c51158d13d8809b5    # "awflash: more work on Livesuit emulation"
# lpunpack (Python) splits the Android dynamic "super" partition into vendor.img.
LPUNPACK_REPO=https://github.com/unix3dgforce/lpunpack
LPUNPACK_COMMIT=c59b8f3b069c5a8aa438a049fa4a091177172434   # 2025-03-02
# PowerVR GE8300 DDK 1.11 userland that matches the stock kernel's pvrsrvkm 1.11
# (ours is 1.19). It is the /usr tree of TrimUI's Smart Pro SDK (proprietary
# Imagination blobs, never in this repo). Only the nine libraries listed in
# inputs/xu20-pvr-1.11.sha256 are taken out of it.
TSP_USR_TGZ=SDK_usr_tg5040_a133p.tgz
TSP_USR_TGZ_SHA256=b6b615d03204e9d9bb1a91c31de0c3402434f6b8fc780743fa88a5f1da6f3c79

# ---- helpers ---------------------------------------------------------------------
log()  { printf '\033[1;34m[oakMOSS]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[oakMOSS] warning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[oakMOSS] error:\033[0m %s\n' "$*" >&2; exit 1; }

# Builders unpack a rootfs and assemble partitions under ${TMPDIR:-/tmp}, which
# is often a tmpfs of a few GB; run out half-way and mke2fs/mksquashfs produce
# a short filesystem that may still pass the later checks. Ask before starting.
need_tmp_space() {  # need_tmp_space <MiB> : die unless that much is free on the work tmp
    local dir=${TMPDIR:-/tmp} have
    have=$(df -Pk "$dir" 2>/dev/null | awk 'NR==2 {print int($4/1024)}')
    [ -n "$have" ] || die "cannot stat $dir"
    [ "$have" -ge "$1" ] || die "only $have MiB free on $dir, this step needs about $1 MiB: free it (a tmpfs empties on reboot) or export TMPDIR to a larger place"
    log "tmp: $have MiB free on $dir (need $1)"
}

sha256_of() { sha256sum "$1" | cut -c1-64; }
md5_of()    { md5sum "$1" | cut -c1-32; }

# sha256_check <file> <expected>  -> 0 if it matches, 1 (with a message) if not
sha256_check() {
    local got; got=$(sha256_of "$1")
    [ "$got" = "$2" ] && return 0
    warn "sha256 mismatch for $1: got $got, expected $2"; return 1
}

# fetch <url> <dest> [sha256]  -> download (resumable, retried) then verify.
# INPUTS_AUTH_HEADER, when set, is passed to curl as an extra request header,
# for locations that need one.
fetch() {
    local url=$1 dest=$2 sum=${3:-}
    if [ -f "$dest" ] && { [ -z "$sum" ] || sha256_check "$dest" "$sum"; }; then
        log "have $(basename "$dest")"; return 0
    fi
    mkdir -p "$(dirname "$dest")"
    log "fetching $(basename "$dest")"
    local -a hdr=()
    [ -n "${INPUTS_AUTH_HEADER:-}" ] && hdr=(-H "$INPUTS_AUTH_HEADER")
    curl -fL --retry 5 --retry-delay 10 -C - "${hdr[@]}" -o "$dest.part" "$url"
    if [ -n "$sum" ]; then sha256_check "$dest.part" "$sum" || die "refusing $(basename "$dest")"; fi
    mv -f "$dest.part" "$dest"
}

need_sdk() { [ -f "$SDK_DIR/build/envsetup.sh" ] || die "no Tina SDK at $SDK_DIR (run scripts/unpack-sdk.sh)"; }
need_mods() { [ -f "$SDK_DIR/.oakmoss-mods" ] || die "SDK modifications not applied (run scripts/apply-sdk-mods.sh)"; }

# squashfs tools: the SDK builds its own (out/host/bin); the host's squashfs-tools 4.x take the same flags.
squashfs_tools() {
    if [ -x "$SDK_DIR/out/host/bin/unsquashfs4" ] && [ -x "$SDK_DIR/out/host/bin/mksquashfs4" ]; then
        UNSQUASHFS=$SDK_DIR/out/host/bin/unsquashfs4; MKSQUASHFS=$SDK_DIR/out/host/bin/mksquashfs4
    else
        UNSQUASHFS=$(command -v unsquashfs || true); MKSQUASHFS=$(command -v mksquashfs || true)
        [ -n "$UNSQUASHFS" ] && [ -n "$MKSQUASHFS" ] || die "need squashfs-tools (unsquashfs/mksquashfs) or a built SDK"
    fi
}

# flush_file <file>: make sure a file we just wrote is on disk, and say so if the
# machine cannot do that. Never call a bare `sync` from a build step: it flushes
# every mounted filesystem, so one wedged mount anywhere blocks it for good (on
# 2026-09-16 two dozen sync processes sat behind a dead mount, unkillable even
# with SIGKILL, and the packer hung behind them with nothing left to write).
# `sync FILE` flushes only that file's filesystem. This wrapper also names the
# condition instead of leaving a silent stall: it counts sync processes blocked
# for over a minute (the signature of a wedged mount) and warns, then bounds the
# flush with a timeout and fails the build with cause and remedy if even the
# single-file flush cannot complete.
flush_file() {
    local f=$1 limit=${FLUSH_TIMEOUT:-120} stale
    stale=$(ps -eo etimes=,comm= 2>/dev/null | awk '$2=="sync" && $1>60 {n++} END {print n+0}')
    if [ "${stale:-0}" -gt 0 ]; then
        warn "$stale sync process(es) have been blocked for over a minute: a mount on this machine is wedged. Only $f is being flushed; if the build stalls here, that is why (under WSL, 'wsl --shutdown' clears it)."
    fi
    if ! timeout "$limit" sync "$f"; then
        die "flushing $f did not finish in ${limit}s. The bytes were written, but the kernel cannot complete the flush: a mount is wedged (see the blocked sync processes above). Restart the machine (WSL: wsl --shutdown) and rebuild."
    fi
}

# mkenvimage: the SDK builds one (out/host/bin); u-boot-tools ships the same.
mkenvimage_tool() {
    if [ -x "$SDK_DIR/out/host/bin/mkenvimage" ]; then MKENVIMAGE=$SDK_DIR/out/host/bin/mkenvimage
    else MKENVIMAGE=$(command -v mkenvimage || true); [ -n "$MKENVIMAGE" ] || die "need mkenvimage (u-boot-tools) or a built SDK"; fi
}

stamp() { date +%Y%m%d-%H%M; }
oakmoss_version() { git -C "$OAKMOSS_ROOT" describe --always --dirty --tags 2>/dev/null || echo untracked; }
