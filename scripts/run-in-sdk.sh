#!/usr/bin/env bash
# Run a shell command inside the Ubuntu 18.04 build container with the SDK tree
# mounted at /home/builder/lichee (Moss-zero28's notes assume ~/lichee).
#
#   scripts/run-in-sdk.sh 'source build/envsetup.sh; lunch a133_aw3-tina; make -j8'
#
# The container image (docker/Dockerfile) is built on first use with the caller's
# UID/GID so the SDK tree stays owned by the caller. Mounts:
#   $SDK_DIR           -> /home/builder/lichee        (rw)
#   $CCACHE_HOST_DIR   -> /home/builder/.ccache       (rw)
#   $OAKMOSS_ROOT      -> /home/builder/oakmoss       (ro)
#   $BUILDS_DIR        -> /home/builder/builds        (rw)
#   $TOOLCHAINS_DIR    -> /home/builder/toolchains    (ro)
# TOOLCHAIN=armgnu13 (default) exports the Tina external-toolchain override
# variables (docs/toolchain.md); the kernel keeps the vendor GCC 6.4 through
# KERNEL_CROSS. TOOLCHAIN=vendor runs the SDK exactly as shipped (phase1/phase2).
. "$(dirname "$0")/lib.sh"
need_sdk
mkdir -p "$CCACHE_HOST_DIR" "$BUILDS_DIR" "$TOOLCHAINS_DIR"
if ! docker image inspect "$DOCKER_IMAGE" >/dev/null 2>&1; then
    log "building container image $DOCKER_IMAGE"
    docker build -t "$DOCKER_IMAGE" --build-arg UID="$(id -u)" --build-arg GID="$(id -g)" "$OAKMOSS_ROOT/docker"
fi
VENDOR_BIN=/home/builder/lichee/prebuilt/gcc/linux-x86/aarch64/toolchain-sunxi-glibc/toolchain/bin
EXT_ENV=()
case "$TOOLCHAIN" in
  vendor) ;;
  armgnu13)
    [ -x "$ARMGNU_DIR/wrap/aarch64-none-linux-gnu-gcc" ] || die "toolchain not prepared (scripts/prepare-toolchain.sh)"
    R=/home/builder/toolchains/arm-gnu-13.3-aarch64
    EXT_ENV=(-e "TINA_EXT_TOOLCHAIN_ROOT=$R" -e TINA_EXT_TOOLCHAIN_PREFIX=aarch64-none-linux-gnu- \
             -e TINA_EXT_TOOLCHAIN_TARGET_NAME=aarch64-none-linux-gnu -e "TINA_EXT_TOOLCHAIN_SYSROOT=$R/tina-sysroot" \
             -e "TINA_EXT_KERNEL_CROSS=$VENDOR_BIN/aarch64-openwrt-linux-gnu-" -e "TINA_EXT_PATH_APPEND=$VENDOR_BIN") ;;
  *) die "unknown TOOLCHAIN=$TOOLCHAIN (armgnu13|vendor)" ;;
esac
TTY=(); [ -t 0 ] && TTY=(-t)
exec docker run --rm -i "${TTY[@]}" \
  -v "$SDK_DIR:/home/builder/lichee" \
  -v "$CCACHE_HOST_DIR:/home/builder/.ccache" \
  -v "$OAKMOSS_ROOT:/home/builder/oakmoss:ro" \
  -v "$BUILDS_DIR:/home/builder/builds" \
  -v "$TOOLCHAINS_DIR:/home/builder/toolchains:ro" \
  "${EXT_ENV[@]}" \
  -w /home/builder/lichee \
  -e TERM=dumb \
  "$DOCKER_IMAGE" bash -lc '[ -n "$TINA_EXT_PATH_APPEND" ] && export PATH="$PATH:$TINA_EXT_PATH_APPEND"; '"$*"
