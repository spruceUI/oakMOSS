#!/usr/bin/env bash
# The USB WiFi dongle modules spruce's usb_wifi_dongle.sh loads (8188eu.ko, 8812au.ko), built against
# this SDK's kernel tree once the image step's make has run: the compiler the kernel's own objects
# record, the in-tree modules' vermagic, and imports only from Module.symvers. Sources pinned in lib.sh.
#
#   scripts/build-usb-wifi.sh <out dir>        build.sh image runs it for boards with USB_WIFI=1
set -euo pipefail
. "$(dirname "$0")/lib.sh"
need_sdk
OUT=${1:?usage: scripts/build-usb-wifi.sh <out dir>}
K=$SDK_DIR/lichee/linux-4.9
[ -f "$K/Module.symvers" ] && [ -f "$K/init/.main.o.cmd" ] || die "no built kernel in $K (scripts/build.sh ext first)"
for pin in "$RTL8188EU_TARBALL $RTL8188EU_SHA256" "$RTL8812AU_TARBALL $RTL8812AU_SHA256"; do
    set -- $pin
    [ -f "$INPUTS_DIR/$1" ] && sha256_check "$INPUTS_DIR/$1" "$2" || die "no verified $INPUTS_DIR/$1 (scripts/fetch-inputs.sh)"
done
NM=$ARMGNU_DIR/bin/aarch64-none-linux-gnu-nm STRIP=$ARMGNU_DIR/bin/aarch64-none-linux-gnu-strip
[ -x "$NM" ] && [ -x "$STRIP" ] || die "no Arm toolchain at $ARMGNU_DIR (scripts/fetch-inputs.sh, scripts/prepare-toolchain.sh)"

# The kernel's compiler as kbuild recorded it (patch 011: the staging toolchain's gcc wrapper); the
# vendor binutils prefix it links with comes from run-in-sdk.sh (TINA_EXT_KERNEL_CROSS).
KCC=$(sed -n '1s/^cmd_init\/main\.o := \([^ ]*\) .*/\1/p' "$K/init/.main.o.cmd")
[ -n "$KCC" ] || die "cannot read the kernel's compiler from $K/init/.main.o.cmd"
REF=$(find "$K/drivers" -name '*.ko' -print -quit)
[ -n "$REF" ] || die "no in-tree module under $K/drivers to take the vermagic from"
vermagic() { tr '\0' '\n' < "$1" | sed -n 's/^vermagic=//p' | head -1; }
WANT=$(vermagic "$REF")

SRC=$BUILDS_DIR/usb-wifi-src
rm -rf "$SRC"; mkdir -p "$SRC" "$OUT"
tar -C "$SRC" -xzf "$INPUTS_DIR/$RTL8188EU_TARBALL"
tar -C "$SRC" -xzf "$INPUTS_DIR/$RTL8812AU_TARBALL"
patch -d "$SRC/rtl8188eu-$RTL8188EU_COMMIT" -p1 -s < "$OAKMOSS_ROOT/sdk-patches/usb-wifi/8188eu-0001-build-on-4.9-random-guard-typo-and-timer-shim.patch" ||
    die "8188eu: the 4.9 patch does not apply"

# In the container $BUILDS_DIR is /home/builder/builds and the SDK /home/builder/lichee.
mk() {  # mk <source dir> <make arguments...>
    local d=$1; shift
    log "building $d"
    "$OAKMOSS_ROOT/scripts/run-in-sdk.sh" "cd /home/builder/builds/usb-wifi-src/$d && make ARCH=arm64 CROSS_COMPILE=\${TINA_EXT_KERNEL_CROSS:?} CC=$KCC KSRC=/home/builder/lichee/lichee/linux-4.9 $* -j\$(nproc) modules > build.log 2>&1" ||
        { grep -E 'error|Error [0-9]' "$SRC/$d/build.log" | head -20 >&2; die "$d did not build (log: $SRC/$d/build.log)"; }
}
mk "rtl8188eu-$RTL8188EU_COMMIT" USER_EXTRA_CFLAGS=-DCONFIG_LITTLE_ENDIAN
mk "rtl8812au-$RTL8812AU_COMMIT" CONFIG_PLATFORM_I386_PC=n CONFIG_PLATFORM_ARM64_RPI=y CONFIG_RTL8814A=n

for m in "8188eu rtl8188eu-$RTL8188EU_COMMIT" "8812au rtl8812au-$RTL8812AU_COMMIT"; do
    set -- $m
    ko=$SRC/$2/$1.ko
    [ -f "$ko" ] || die "$1: the build made no $1.ko (made: $(cd "$SRC/$2" && ls ./*.ko 2>/dev/null | tr '\n' ' '))"
    got=$(vermagic "$ko")
    [ "$got" = "$WANT" ] || die "$1: vermagic '$got' is not the kernel's '$WANT'"
    missing=$(comm -23 <("$NM" -u "$ko" | awk '{print $NF}' | sort -u) <(awk '{print $2}' "$K/Module.symvers" | sort -u))
    [ -z "$missing" ] || die "$1: imports this kernel does not export: $(echo $missing | cut -c1-300)"
    "$STRIP" --strip-debug -o "$OUT/$1.ko" "$ko"
done
{
  echo "built=$(stamp) oakmoss=$(oakmoss_version)"
  echo "kernel=$K vermagic=$WANT compiler=$KCC"
  echo "8188eu: lwfinger/rtl8188eu $RTL8188EU_COMMIT (sha256 $RTL8188EU_SHA256) + sdk-patches/usb-wifi/8188eu-0001"
  echo "8812au: aircrack-ng/rtl8812au $RTL8812AU_COMMIT (sha256 $RTL8812AU_SHA256), CONFIG_PLATFORM_ARM64_RPI=y CONFIG_RTL8814A=n"
  ( cd "$OUT" && sha256sum 8188eu.ko 8812au.ko )
} > "$OUT/PROVENANCE.txt"
rm -rf "$SRC"
log "USB WiFi modules in $OUT: 8188eu.ko, 8812au.ko (vermagic $WANT)"
