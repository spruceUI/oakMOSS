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
# bluez-alsa 4.0.0 (tree patch 133): the GitHub tag archive, byte-identical to tag v4.0.0.
BLUEZALSA_TARBALL=bluez-alsa-4.0.0.tar.gz
BLUEZALSA_URL=https://github.com/arkq/bluez-alsa/archive/refs/tags/v4.0.0.tar.gz
BLUEZALSA_SHA256=ce5e060e61669d61d44f5f9bad34a7b88378376e9d49d31482406a68127a6b29
# zlib 1.3.1 (tree patch 135): zlib.net's release archive (GitHub's v1.3.1 asset is byte-identical),
# signed by Mark Adler (5ED4 6A67 21D3 6558 7791  E2AA 783F CD8E 58BC AFBA).
ZLIB_TARBALL=zlib-1.3.1.tar.gz
ZLIB_URL=https://zlib.net/fossils/$ZLIB_TARBALL
ZLIB_SHA256=9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23
# OpenSSL 1.1.1w (sdk-patches/openssl-1.1.1w): openssl.org's archive (GitHub's OpenSSL_1_1_1w asset is
# byte-identical), signed with the OpenSSL OMC key (EFC0 A467 D613 CB83 C7ED  6D30 D894 E2CE 8B3D 79F5).
OPENSSL_TARBALL=openssl-1.1.1w.tar.gz
OPENSSL_URL=https://www.openssl.org/source/old/1.1.1/$OPENSSL_TARBALL
OPENSSL_SHA256=cf3098950cb4d853ad95c0841f1f9c6d3dc102dccfcacd521d93925208b76ac8
# BatteryPlus (docs/batteryplus.md): Mikhailzrick's knubat.components at the last commit to BatteryPlus/,
# GitHub's archive of that commit (GPL-2.0).
BATTERYPLUS_COMMIT=1c31e89ec1828d51710ad35a607bdfad7e18464e
BATTERYPLUS_TARBALL=knubat.components-$BATTERYPLUS_COMMIT.tar.gz
BATTERYPLUS_URL=https://github.com/Mikhailzrick/knubat.components/archive/$BATTERYPLUS_COMMIT.tar.gz
BATTERYPLUS_SHA256=1619da9e945746ea589edb70efd1095b07d21207be3fa43a4c1598be5c2a2089
# USB WiFi dongle drivers for spruce's usb_wifi_dongle.sh (8188eu: RTL8188EU(S); 8812au: RTL8811AU/
# 8812AU/8821AU): the wrapper's tools/a133-usb-wifi sources, built on our kernel by build-usb-wifi.sh.
RTL8188EU_COMMIT=f42fc9c45d2086c415dce70d3018031b54a7beef
RTL8188EU_TARBALL=rtl8188eu-$RTL8188EU_COMMIT.tar.gz
RTL8188EU_URL=https://github.com/lwfinger/rtl8188eu/archive/$RTL8188EU_COMMIT.tar.gz
RTL8188EU_SHA256=507d32eb91d3d407c7758319c81a36a9dc69e2b89378cabcd382411153927b7b
RTL8812AU_COMMIT=734485506a30d6237c2deaad666a19f8ca5379f2
RTL8812AU_TARBALL=rtl8812au-$RTL8812AU_COMMIT.tar.gz
RTL8812AU_URL=https://github.com/aircrack-ng/rtl8812au/archive/$RTL8812AU_COMMIT.tar.gz
RTL8812AU_SHA256=ab9d257758ec55a352a5671e3b96c0d73795c5ccea01173d4412dad35fd70d7e

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
# ---- Powkiddy V90S / V20 stock cards (scripts/make-own-kernel-stock.sh v90s|v20) ---
# V90S: Tina Linux behind a boot0 for its DDR3 (576 MHz) and a U-Boot package. Its boot0, package,
# env and v0 boot image (whose header ours reuses) are public in Knulli's board files, pinned here
# by commit and checksum; none of it is redistributed here. unpack-powkiddy-stock.sh also takes a
# local copy (e.g. read off a card). Knulli ships the same files for the V20, but a real V20 card
# has its own chain (below).
POWKIDDY_STOCK_REF=6b33506613d0a661d190e9bc3afc898440bcbb14                               # knulli-cfw/knulli-linux, 2025-10-23
POWKIDDY_STOCK_URL=https://raw.githubusercontent.com/knulli-cfw/knulli-linux/$POWKIDDY_STOCK_REF/board/allwinner/a133/powkiddy-v90s/partitions
POWKIDDY_STOCK_BOOT0_SHA256=638d5d75f9d348a4fbcadb901a2c102fd88148900c3d186acc7ae6d4095784c4
POWKIDDY_STOCK_PKG_SHA256=9138e92d06a77a2844fb101ec2b2fa15ef11770a901b917ccafd82275b35114e
POWKIDDY_STOCK_ENV_SHA256=e53c8673bd5bde392310b6076eef08a3d06abe3941395fac8ab3351d8e648526
POWKIDDY_STOCK_BOOTIMG_SHA256=93695c7fb3d9ce8b48466f5ac2c99270f64bdf664e3cfa81b71f4724f6b757d2
POWKIDDY_STOCK_DIR=$INPUTS_DIR/powkiddy-stock                                          # unpack-powkiddy-stock.sh output
POWKIDDY_STOCK_SHA256="boot0 $POWKIDDY_STOCK_BOOT0_SHA256, package $POWKIDDY_STOCK_PKG_SHA256"
# V20: its own boot0 (DDR3 at 504 MHz), U-Boot (2018.05-00025), SCP and tree, read off another
# developer's stock card (2026-10-25); not public, so `unpack-powkiddy-stock.sh v20 <dir>` takes a
# local copy (boot0.img, boot_package.fex, the 128 KiB env.img, boot.img), checked against these pins.
POWKIDDY_V20_STOCK_BOOT0_SHA256=af7b1d2e2a885a5c22a0175549d0b1d32241e22455eb9c9909014b38539ed8ab
POWKIDDY_V20_STOCK_PKG_SHA256=3deea3cc43e4b0bcd0b339f5298953894bbda108a8ac740b49f0d89b0af81ee3
POWKIDDY_V20_STOCK_ENV_SHA256=9e12f02d432dd58feab5a71075fd0ca5cd5b4f4063aee62910412e0f2d9b2fb5
POWKIDDY_V20_STOCK_BOOTIMG_SHA256=ab521b0db5c2561d4fb973791a495c912a0ec9997ad67cf3d102cce56036cb8b
POWKIDDY_V20_STOCK_DIR=$INPUTS_DIR/powkiddy-v20-stock                                  # unpack-powkiddy-stock.sh v20 output
POWKIDDY_V20_STOCK_SHA256="boot0 $POWKIDDY_V20_STOCK_BOOT0_SHA256, package $POWKIDDY_V20_STOCK_PKG_SHA256"
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

# kdebug_patch_state <patch> : where a debug patch (sdk-patches/debug/) stands on $SDK_DIR -
# "applied" when it reverse-applies exactly, "absent" when it forward-applies exactly,
# "mismatch" otherwise (the tree carries debug edits the patch does not describe, or only
# part of it). Dry runs only, no fuzz and never -f: a forced partial apply duplicates hunks
# (2026-09-29: seven kernel files had to be restored from pristine copies).
kdebug_patch_state() {
    if ( cd "$SDK_DIR" && patch -p1 -R --dry-run -s -F0 < "$1" >/dev/null 2>&1 ); then echo applied
    elif ( cd "$SDK_DIR" && patch -p1 -N --dry-run -s -F0 < "$1" >/dev/null 2>&1 ); then echo absent
    else echo mismatch; fi
}
# The level apply-sdk-mods.sh stamps (docs/sdk-mods.md, `mods_version`). A tree stamped lower
# lacks later rounds, so build.sh refuses it.
# 28 = feat/trimui-a133p round 33 (26 is bundle/20261024's): whoever merges second renumbers.
OAKMOSS_MODS_VERSION=28
need_mods() {
    local v
    [ -f "$SDK_DIR/.oakmoss-mods" ] || die "SDK modifications not applied (run scripts/apply-sdk-mods.sh)"
    v=$(sed -n 's/^oakmoss_mods_version=//p' "$SDK_DIR/.oakmoss-mods")
    [ "${v:-0}" -ge "$OAKMOSS_MODS_VERSION" ] 2>/dev/null ||
        die "the SDK has modifications version ${v:-none}, this checkout needs $OAKMOSS_MODS_VERSION (scripts/kdebug.sh revert, then scripts/apply-sdk-mods.sh)"
}

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

# OAKMOSS_CLEAN_REBUILD: the human-facing remedy for a stale kernel tree, printed by
# check_shipped_modules and run by wipe_kernel_build_tree. Runs inside the container, through
# the same lunch preamble every other kernel-touching step uses, so it resolves the compiler the
# same way a real build does (not a bare host `make`).
OAKMOSS_CLEAN_REBUILD='source build/envsetup.sh; lunch a133_aw3-tina; rm -f lichee/linux-4.9/.configured lichee/linux-4.9/vmlinux lichee/linux-4.9/System.map; make -C lichee/linux-4.9 ARCH=arm64 clean'

# wipe_kernel_build_tree: force every kernel module to recompile and relink, keeping .config.
# $SDK_DIR/lichee/linux-4.9 is Tina's real kbuild tree (LINUX_DIR, build/kernel-build.mk's
# STAMP_CONFIGURED) - an out/.../linux-a133-aw3 package dir elsewhere does not hold kbuild's own
# object cache (2026-10-10, a validation build: wiping that dir forced a full `ext` but the same stale
# vin_v4l2.ko came back). `make clean` keeps .config.
wipe_kernel_build_tree() {
    "$OAKMOSS_ROOT/scripts/run-in-sdk.sh" "$OAKMOSS_CLEAN_REBUILD" >/dev/null 2>&1
}

# check_shipped_modules <board>: refuse a module the current build did not actually
# recompile. The `ext` step's kbuild dependency tracking lives entirely in-tree at
# $SDK_DIR/lichee/linux-4.9, so a .ko whose own inputs are untouched is never relinked - even
# across an SDK-mods upgrade that should invalidate it (2026-10-10: one build host's vin_v4l2.ko
# survived from 2026-10-08 that way). The final rootfs copy is re-stamped at install time, so
# this checks the ipkg-sunxi per-package copy instead, which preserves the module's own kbuild
# link time (modpost batches many modules together, so several sharing one identical second,
# confirmed on two build hosts, is normal - it is still each module's real link time).
# Compared against $SDK_DIR/.oakmoss-mods' own "applied=" stamp - the SDK's own declared current
# state. 2026-10-11: a producer-string/compiler-flag check was tried and dropped - one host's stale
# vin_v4l2.ko and another's freshly rebuilt one carry the IDENTICAL compiler and flags (verified
# across every linked sub-object on both hosts), and some legitimate modules (the GE8300 GPU km,
# sdk-patches/tree/040) are vendor-GCC-6.4 by design on a healthy build - a compiler-identity
# check would have refused those on every build. Timestamp is the only signal that discriminated
# correctly in practice (validation builds: the stale tree refused, fresh ones passed). Prints what it found; returns 1 so the
# caller can clean up its half-built output and die.
OAKMOSS_KVER=4.9.191
check_shipped_modules() {
    local board=$1 modsfile=$SDK_DIR/.oakmoss-mods applied applied_epoch bad=0
    local rootfs_mods=$SDK_DIR/out/a133-aw3/compile_dir/target/rootfs/lib/modules/$OAKMOSS_KVER
    local stage=$SDK_DIR/out/a133-aw3/compile_dir/target/linux-a133-aw3/packages/ipkg-sunxi
    [ -f "$modsfile" ] || die "no $modsfile (need_mods should have caught this)"
    applied=$(sed -n 's/^applied=//p' "$modsfile")
    applied_epoch=$(date -u -d "$applied" +%s) || die "cannot parse applied= '$applied' in $modsfile"
    [ -d "$rootfs_mods" ] || { warn "no $rootfs_mods: nothing to check for $board"; return 0; }
    local ko base src
    for ko in "$rootfs_mods"/*.ko; do
        [ -e "$ko" ] || continue
        base=$(basename "$ko")
        src=$(find "$stage" -path "*/lib/modules/$OAKMOSS_KVER/$base" -print -quit 2>/dev/null)
        if [ -z "$src" ]; then warn "$base: no ipkg-sunxi staging copy to check, skipping"; continue; fi
        if [ "$(stat -c %Y "$src")" -lt "$applied_epoch" ]; then
            warn "STALE: $base linked $(stat -c %y "$src" | cut -d. -f1), mods applied $applied ($modsfile)"
            bad=1
        fi
    done
    if [ "$bad" = 1 ]; then
        warn "clean-rebuild: scripts/run-in-sdk.sh '$OAKMOSS_CLEAN_REBUILD' && scripts/build.sh ext && scripts/build.sh image $board"
        return 1
    fi
    return 0
}

# apply_mods_stamp <changed>: write $SDK_DIR/.oakmoss-mods for this apply-sdk-mods.sh run.
# applied= only moves forward when <changed>=1 (something was actually patched, copied, moved
# or staged this run) or the tree's recorded version differs from OAKMOSS_MODS_VERSION - never
# on a no-op re-run, because build.sh's pack-time check (check_shipped_modules) refuses any .ko
# linked before applied=, and advancing it without a matching rebuild would make the next image
# refuse modules that are actually fine. Whenever applied= does move, also wipes the kernel
# build tree (wipe_kernel_build_tree) so the next ext/image recompiles everything it now claims
# is current.
apply_mods_stamp() {
    local changed=$1 modsfile=$SDK_DIR/.oakmoss-mods old_version old_applied new_applied
    old_version=$(sed -n 's/^oakmoss_mods_version=//p' "$modsfile" 2>/dev/null || true)
    old_applied=$(sed -n 's/^applied=//p' "$modsfile" 2>/dev/null || true)
    if [ "$changed" = 1 ] || [ "$old_version" != "$OAKMOSS_MODS_VERSION" ]; then
        new_applied=$(date -u +%FT%TZ)
        wipe_kernel_build_tree
        warn "cleared the kernel build tree (changed=$changed, mods $old_version -> $OAKMOSS_MODS_VERSION)"
    else
        new_applied=$old_applied
    fi
    { echo "oakmoss_mods_version=$OAKMOSS_MODS_VERSION"; echo "applied=$new_applied"; echo "oakmoss=$(oakmoss_version)"; } > "$modsfile"
}

stamp() { date +%Y%m%d-%H%M; }
# OAKMOSS_DESCRIBE: run-userland-lane.sh passes the host's, since a container may not see a linked worktree's .git
oakmoss_version() { [ -n "${OAKMOSS_DESCRIBE:-}" ] && echo "$OAKMOSS_DESCRIBE" && return; git -C "$OAKMOSS_ROOT" describe --always --dirty --tags 2>/dev/null || echo untracked; }
# The commit time, which an update must exceed to be installed (docs/updates.md).
oakmoss_build() { git -C "$OAKMOSS_ROOT" log -1 --format=%ct 2>/dev/null || echo 0; }
