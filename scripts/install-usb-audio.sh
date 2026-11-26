#!/usr/bin/env bash
# USB audio (DACs, headsets) for the image: the kernel builds SND_USB_AUDIO, SND_HWDEP and SND_RAWMIDI
# as modules (sdk-patches/tree/020), but Tina has no kmod package for them (its Sound Support menu is
# kmod-sound-core, -hwdep and kmod-sunxi-sound; its USB menu has no audio entry), so no image shipped
# them: a USB DAC enumerated and never became a sound card. This copies the four modules the kernel
# build has already made into the image's /lib/modules and autoloads them. There is no second build,
# so the compiler and the vermagic are the kernel's own by construction.
#
#   scripts/install-usb-audio.sh <rootfs dir>     build.sh image runs it for boards with USB_AUDIO=1
#
# <rootfs dir> is the tree the image is made from (package/add-rootfs-demo): lib/modules/<release>/
# gets the .ko files and etc/modules.d/usb-audio their names, in dependency order.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
need_sdk
DEST=${1:?usage: scripts/install-usb-audio.sh <rootfs dir>}
K=$SDK_DIR/lichee/linux-4.9
STRIP=$ARMGNU_DIR/bin/aarch64-none-linux-gnu-strip
[ -x "$STRIP" ] || die "no Arm toolchain at $ARMGNU_DIR (scripts/fetch-inputs.sh, scripts/prepare-toolchain.sh)"
[ -f "$K/Module.symvers" ] || die "no built kernel in $K (scripts/build.sh ext first)"
KREL=$(sed -n 's/^#define UTS_RELEASE "\(.*\)"/\1/p' "$K/include/generated/utsrelease.h")
[ -n "$KREL" ] || die "cannot read the kernel release from $K/include/generated/utsrelease.h"
REF=$(find "$K/drivers" -name '*.ko' -print -quit)
[ -n "$REF" ] || die "no in-tree module under $K/drivers to take the vermagic from"
vermagic() { tr '\0' '\n' < "$1" | sed -n 's/^vermagic=//p' | head -1; }
WANT=$(vermagic "$REF")

# In load order: usb-audio needs usbmidi-lib, which needs rawmidi.
MODS="sound/core/snd-hwdep sound/core/snd-rawmidi sound/usb/snd-usbmidi-lib sound/usb/snd-usb-audio"
MD=$DEST/lib/modules/$KREL
rm -rf "$MD"/snd-hwdep.ko "$MD"/snd-rawmidi.ko "$MD"/snd-usbmidi-lib.ko "$MD"/snd-usb-audio.ko "$DEST/etc/modules.d/usb-audio"
mkdir -p "$MD" "$DEST/etc/modules.d"
: > "$DEST/etc/modules.d/usb-audio"
for m in $MODS; do
    ko=$K/$m.ko; n=$(basename "$m")
    [ -f "$ko" ] || die "$n: the kernel build made no $m.ko (CONFIG_SND_USB_AUDIO=m, SND_HWDEP=m, SND_RAWMIDI=m?)"
    got=$(vermagic "$ko")
    [ "$got" = "$WANT" ] || die "$n: vermagic '$got' is not the kernel's '$WANT'"
    "$STRIP" --strip-debug -o "$MD/$n.ko" "$ko"
    echo "$n" >> "$DEST/etc/modules.d/usb-audio"
done
log "USB audio: $(echo $MODS | wc -w) modules into lib/modules/$KREL, autoloaded by etc/modules.d/usb-audio ($WANT)"
