#!/usr/bin/env bash
# Collect every input the build needs into $INPUTS_DIR.
#
#   scripts/fetch-inputs.sh [--with-phase2]
#
# Public inputs are downloaded and checksum-verified: the Arm GNU toolchain,
# ncurses 6.2, Shaun Inman's main-zero40 release image (Zero 40 hybrid), and
# with --with-phase2 the GCC 7.5.0 / binutils 2.28 sources for the fallback
# from-source toolchain.
#
# Two inputs are proprietary and NOT downloadable from a public place. Put them
# in $INPUTS_DIR yourself, or export a URL (plus INPUTS_AUTH_HEADER if it needs
# one) and this script fetches them:
#   TINA_SDK_URL       -> inputs/Linux_SDK.zip      (MagicX's Tina SDK drop)
#   ZERO40_LICHEE_URL  -> inputs/Zero40-lichee.zip  (Zero 40 sunxi_encrypt object, 100 KB)
#   TSP_USR_URL        -> inputs/SDK_usr_tg5040_a133p.tgz (TrimUI Smart Pro SDK /usr, 185 MB;
#                         its PowerVR 1.11 userland is what the XU20 image needs)
# Without the SDK nothing can be built; without the Zero 40 object only the
# Zero 28 image can be built; without the TrimUI /usr tree no XU20 image.
# The XU20 and Zero 40 stock firmwares are public GitHub releases and are fetched.
. "$(dirname "$0")/lib.sh"
WITH_PHASE2=0
for a in "$@"; do case $a in --with-phase2) WITH_PHASE2=1 ;; *) die "unknown option $a" ;; esac; done
mkdir -p "$INPUTS_DIR"

fetch "$ARMGNU_URL" "$INPUTS_DIR/$ARMGNU_TARBALL" "$ARMGNU_SHA256"
fetch "$NCURSES_URL" "$INPUTS_DIR/$NCURSES_TARBALL" "$NCURSES_SHA256"
fetch "$MAINZERO40_URL" "$INPUTS_DIR/$MAINZERO40_ZIP" "$MAINZERO40_ZIP_SHA256"
fetch "$XU20_STOCK_URL" "$INPUTS_DIR/$XU20_STOCK_ZIP" "$XU20_STOCK_ZIP_SHA256"
fetch "$ZERO40_STOCK_URL" "$INPUTS_DIR/$ZERO40_STOCK_XZ" "$ZERO40_STOCK_XZ_SHA256"
if [ "$WITH_PHASE2" = 1 ]; then
    fetch "$GCC750_URL" "$INPUTS_DIR/$GCC750_TARBALL" "$GCC750_SHA256"
    fetch "$BINUTILS228_URL" "$INPUTS_DIR/$BINUTILS228_TARBALL" "$BINUTILS228_SHA256"
fi

# --- proprietary inputs ---
sdk=$INPUTS_DIR/$TINA_SDK_ZIP
if [ ! -f "$sdk" ]; then
    [ -n "${TINA_SDK_URL:-}" ] || die "missing $sdk and TINA_SDK_URL is unset: obtain the Tina SDK (mplus_a133_tina_v1.0, 'Linux_SDK.zip') from MagicX and place it there. See inputs/README.md."
    fetch "$TINA_SDK_URL" "$sdk"
fi
if ! sha256_check "$sdk" "$TINA_SDK_ZIP_SHA256"; then
    warn "$TINA_SDK_ZIP differs from the copy this repo was developed with; the inner tarball's md5 is checked at unpack time"
fi

z40=$INPUTS_DIR/$ZERO40_LICHEE_ZIP
if [ ! -f "$z40" ] && [ -n "${ZERO40_LICHEE_URL:-}" ]; then fetch "$ZERO40_LICHEE_URL" "$z40"; fi
if [ -f "$z40" ]; then
    sha256_check "$z40" "$ZERO40_LICHEE_SHA256" || die "$ZERO40_LICHEE_ZIP is not the expected archive"
else
    warn "no $ZERO40_LICHEE_ZIP: the Zero 40 image cannot be built (Zero 28 can)"
fi
tsp=$INPUTS_DIR/$TSP_USR_TGZ
if [ ! -f "$tsp" ] && [ -n "${TSP_USR_URL:-}" ]; then fetch "$TSP_USR_URL" "$tsp"; fi
if [ -f "$tsp" ]; then
    sha256_check "$tsp" "$TSP_USR_TGZ_SHA256" || die "$TSP_USR_TGZ is not the expected archive"
else
    warn "no $TSP_USR_TGZ (TrimUI Smart Pro SDK /usr): the XU20 image cannot be built (the Zero boards can)"
fi
log "inputs ready in $INPUTS_DIR"; ls -la "$INPUTS_DIR" >&2
