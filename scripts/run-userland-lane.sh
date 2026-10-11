#!/usr/bin/env bash
# Run a userland lane (build-ports-userland.sh) inside docker/userland-lane, whose image carries the build-host
# programs (cmake, meson, autotools, bison...) so no build host needs them installed.
#
#   scripts/run-userland-lane.sh [package ...]     (environment as for build-ports-userland.sh, e.g.
#                                                   PORTS_SET=flip PORTS_TOOLCHAIN=armgnu103)
#
# LANE_IMAGE and LANE_CONTAINER name the image and the container (oakmoss-lane-build:bookworm and
# oakmoss-lane-<stamp> by default); the image is built from docker/userland-lane when it is missing.
# The checkout, the toolchains and the inputs are mounted read-only at their own paths, $BUILDS_DIR read-write.
. "$(dirname "$0")/lib.sh"
IMG=${LANE_IMAGE:-oakmoss-lane-build:bookworm}
NAME=${LANE_CONTAINER:-oakmoss-lane-$(stamp)}
docker image inspect "$IMG" >/dev/null 2>&1 || docker build -t "$IMG" "$OAKMOSS_ROOT/docker/userland-lane" ||
    die "could not build $IMG"
mkdir -p "$BUILDS_DIR"
args=(-v "$OAKMOSS_ROOT:$OAKMOSS_ROOT:ro" -v "$TOOLCHAINS_DIR:$TOOLCHAINS_DIR:ro" -v "$INPUTS_DIR:$INPUTS_DIR:ro"
      -v "$BUILDS_DIR:$BUILDS_DIR")
[ -d "$SDK_DIR" ] && args+=(-v "$SDK_DIR:$SDK_DIR:ro")    # the default lane's toolchain lives in the SDK
for v in OUT WORK SRC_DIR; do [ -n "${!v:-}" ] && args+=(-e "$v=${!v}"); done
exec docker run --rm --name "$NAME" --user "$(id -u):$(id -g)" -e HOME=/tmp -e JOBS="$JOBS" \
    -e PORTS_TOOLCHAIN="${PORTS_TOOLCHAIN:-tina}" -e PORTS_SET="${PORTS_SET:-card}" \
    -e OAKMOSS_WORK="$OAKMOSS_WORK" -e INPUTS_DIR="$INPUTS_DIR" -e TOOLCHAINS_DIR="$TOOLCHAINS_DIR" \
    -e OAKMOSS_DESCRIBE="$(oakmoss_version)" \
    -e BUILDS_DIR="$BUILDS_DIR" -e SDK_DIR="$SDK_DIR" "${args[@]}" "$IMG" \
    "$OAKMOSS_ROOT/scripts/build-ports-userland.sh" "$@"
