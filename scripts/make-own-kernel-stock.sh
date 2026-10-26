#!/usr/bin/env bash
# OWN-KERNEL image on the STOCK boot chain, for the boards whose Android developer
# firmware is the only stock chain we have (XU20 V32) or whose own chain has no
# panel driver in the SDK drop (Zero 40): the device's boot0 and U-Boot package
# (proven on the unit with two cards), OUR kernel from scripts/build.sh image
# <board> wrapped as the Android boot image that U-Boot boots, OUR device tree
# both inside that image and in place of the package's (whichever copy U-Boot
# hands the kernel, it is ours), and OUR rootfs squashfs in the rootfs partition
# - the same kernel, modules, PowerVR 1.19 stack and userland the Zero 28 runs.
#
#   scripts/make-own-kernel-stock.sh <board> <build dir> [out dir]     board: xu20 | zero40 | v90s | v20 | brick
#
# The Powkiddy V90S and V20 each boot their own stock card's chain (Tina Linux, not Android): its boot0
# (DDR3 at 576 MHz on the V90S, 504 on the V20; the SDK's boot0 is set up for neither), its U-Boot
# package and its v0 boot image header. No dtbo or vbmeta exist there; the partitions keep their places, blank.
#
# The TrimUI Brick (Tina Linux) keeps TrimUI's boot0, U-Boot package and boot-resource byte-identical,
# its device tree included (board.conf OWN_STOCK_DT=1): TrimUI's recovery lives in that U-Boot, and our
# kernel reads the stock tree (docs/trimui.md). The card boots beside the stock eMMC (OWN_EMMC=1).
#
# Why not the Android kernel (scripts/make-hybrid-stock.sh): its 1.11 GPU driver
# exports no display-class API, so no Linux GPU userland can initialize on it
# (docs/hardware-notes.md, "EGL"). Why not our own boot0/U-Boot: the stock ones
# carry the board's DRAM and panel init and are known to work; ours are the Zero 28's.
#
# Inputs: the board's stock firmware unpacked (unpack-xu20-stock.sh /
# unpack-zero40-stock.sh) and a build of THIS board (boards/<board>/board.dts gives
# it the board's panel, pad, radio and battery; sdk-patches/tree/070-* the panel
# drivers). DIAG=1 (default; OWN_DIAG in board.conf sets a board's own) installs the
# diagnostic hand-off and, with EARLY_PROBE=1, the init= probe; EXPERIMENTS="..." adds
# diag/experiments. board.conf OWN_AUTOLOAD_DROP names /etc/modules.d files to remove.
# A card to run rather than to diagnose (what the bench units run):
#   DIAG=0 EARLY_PROBE=0 CONSOLE=tty0 BOOTRES=builds/bootres-<board>.fex \
#       scripts/make-own-kernel-stock.sh <board> builds/<stamp>-<board> [out dir]
# with BOOTRES from scripts/make-boot-resource.py (panel-sized bootloader screens and
# the boot logo) and a kernel built without KDEBUG_*. tty0 because every validated
# boot since the touch fix used it; the options below are all diagnostic.
# CONSOLE="tty0" replaces the stock console list, for a kernel built with
# build.sh KDEBUG_FBCON=1: together they put the kernel log on the panel.
# EXTRA_BOOTARGS="fbcon=rotate:2" appends raw bootargs (the XU20 panel is upside down).
# PSTORE=1 captures panics/oopses to the card's pstore partition, readable after the
# next good boot with: mount -t pstore pstore /sys/fs/pstore; cat /sys/fs/pstore/*
. "$(dirname "$0")/lib.sh"
BOARD=${1:?board: xu20 | zero40 | v90s | v20 | brick}; shift || true
STOCK=android
case "$BOARD" in
    xu20)   STOCK_DIR=$XU20_STOCK_DIR;   DUMP=$STOCK_DIR/$XU20_STOCK_IMG.dump;   CHAIN_SHA=$XU20_STOCK_IMG_SHA256;   UNPACKER=unpack-xu20-stock.sh
            CHAIN="XU20 V32 stock firmware (github.com/Magicx-Breeze/XU20_V32, Developers release)" ;;
    zero40) STOCK_DIR=$ZERO40_STOCK_DIR; DUMP=$STOCK_DIR/$ZERO40_STOCK_IMG.dump; CHAIN_SHA=$ZERO40_STOCK_IMG_SHA256; UNPACKER=unpack-zero40-stock.sh
            CHAIN="Zero 40 stock firmware (github.com/Magicx-Breeze/Zero40, release Zero40_V1, adb.img)" ;;
    v90s) STOCK_DIR=$POWKIDDY_STOCK_DIR; DUMP=$STOCK_DIR/items; CHAIN_SHA=$POWKIDDY_STOCK_SHA256; UNPACKER=unpack-powkiddy-stock.sh; STOCK=tina
            CHAIN="Powkiddy V90S stock card (Tina Linux; Knulli's V90S files)" ;;
    v20)  STOCK_DIR=$POWKIDDY_V20_STOCK_DIR; DUMP=$STOCK_DIR/items; CHAIN_SHA=$POWKIDDY_V20_STOCK_SHA256; UNPACKER="unpack-powkiddy-stock.sh v20"; STOCK=tina
          CHAIN="Powkiddy V20 stock card (Tina Linux; its own boot0 at 504 MHz, U-Boot, SCP and tree, read off another developer's card)" ;;
    brick) STOCK_DIR=$TRIMUI_BRICK_STOCK_DIR; DUMP=$STOCK_DIR/items; CHAIN_SHA=$TRIMUI_BRICK_STOCK_SHA256; UNPACKER="unpack-trimui-stock.sh brick"; STOCK=tina
           CHAIN="TrimUI Brick stock firmware 1.1.1 (github.com/trimui/firmware_brick, trimui_tg3040.awimg)" ;;
    *) die "unknown board $BOARD (xu20 | zero40 | v90s | v20 | brick)" ;;
esac
BUILD=${1:?build directory (builds/<stamp>-$BOARD)}; shift || true
ST=$(stamp); OUT=${1:-$BUILDS_DIR/$ST-$BOARD-own}
bconf() { { sed -n "s/^$1=\"\{0,1\}\([^\"#]*\)\"\{0,1\}.*/\1/p" "$OAKMOSS_ROOT/boards/$BOARD/board.conf" 2>/dev/null || true; } | sed 's/[[:space:]]*$//'; }
OWN_DIAG=$(bconf OWN_DIAG); OWN_AUTOLOAD_DROP=$(bconf OWN_AUTOLOAD_DROP); OWN_BOOTRES_FILES=$(bconf OWN_BOOTRES_FILES)
# TrimUI (docs/trimui.md): OWN_STOCK_DT keeps the stock package whole, OWN_EMMC roots the card past the
# eMMC, OWN_TRIMUI_INPUTD adds TrimUI's input daemon (a local image), OWN_TRIMUI_GPIO the lines stock sets.
OWN_STOCK_DT=$(bconf OWN_STOCK_DT); OWN_EMMC=$(bconf OWN_EMMC); OWN_TRIMUI_INPUTD=$(bconf OWN_TRIMUI_INPUTD); OWN_TRIMUI_GPIO=$(bconf OWN_TRIMUI_GPIO)
[ "${OWN_STOCK_DT:-0}" != 1 ] || [ "$STOCK" = tina ] || die "OWN_STOCK_DT=1 needs a Tina stock chain (a v0 boot image takes the tree from the package)"
[ "${OWN_STOCK_DT:-0}" != 1 ] || { [ "${OWN_BOOTRES_FILES:-0}" != 1 ] && [ -z "${BOOTRES:-}" ]; } ||
    die "OWN_STOCK_DT=1 keeps the stock boot-resource: no OWN_BOOTRES_FILES or BOOTRES"
[ "${OWN_STOCK_DT:-0}" != 1 ] || [ "${OMUPD_BOOTCHAIN:-0}" != 1 ] || die "OWN_STOCK_DT=1: no OMUPD_BOOTCHAIN (the card refuses it)"
# AB=1 (board.conf OWN_AB): slot B for updates (docs/updates.md), and the update file beside the image.
AB=${AB:-$(bconf OWN_AB)}; AB=${AB:-0}
DIAG=${DIAG:-${OWN_DIAG:-1}}; EARLY_PROBE=${EARLY_PROBE:-1}; EXPERIMENTS=${EXPERIMENTS:-}
# PSTORE=1 points the kernel's pstore block backend at the card's own pstore
# partition, so a panic or an oops is written to the CARD and survives both the
# failure and the cold power-off needed to recover from it - which is what a
# reboot loop demands and what a RAM-backed log (ramoops) cannot give, since the
# power cycle that ends the loop also clears the RAM. max_reason 6 = up to
# KMSG_DUMP_POWEROFF (include/linux/kmsg_dump.h); 5 stopped at HALT and missed a
# poweroff. PARTUUID, not /dev/mmcblkNpM:
# pstore_blk runs at late_initcall, long before anything creates /dev/by-name.
PSTORE=${PSTORE:-0}
PSTORE_PARTUUID=7b5f0e2a-9c41-4d68-9f3a-0ac5f0e5d001
if [ "${KMARK:-0}" = 1 ]; then
    [ "${BOOTMARK:-0}" = 1 ] || die "KMARK=1 needs BOOTMARK=1"
    EXTRA_BOOTARGS="${EXTRA_BOOTARGS:-} oakmoss_mark=0x07000114"
fi
if [ "$PSTORE" = 1 ]; then
    EXTRA_BOOTARGS="${EXTRA_BOOTARGS:-} pstore_blk.blkdev=PARTUUID=$PSTORE_PARTUUID pstore_blk.kmsg_size=64 pstore_blk.max_reason=6 pstore_blk.best_effort=Y"
fi
ROOTFS=$(ls "$BUILD"/*.img.dump/rootfs.fex 2>/dev/null | head -1)
OURBOOT=$(ls "$BUILD"/*.img.dump/boot.fex 2>/dev/null | head -1)
OURPKG=$(ls "$BUILD"/*.img.dump/boot_package.fex 2>/dev/null | head -1)
[ -f "$ROOTFS" ] && [ -f "$OURBOOT" ] && [ -f "$OURPKG" ] || die "no rootfs.fex / boot.fex / boot_package.fex under $BUILD (scripts/build.sh image $BOARD)"
grep -q "^device=$BOARD" "$BUILD/BUILD-INFO.txt" 2>/dev/null || die "$BUILD is not a $BOARD build"
[ -d "$DUMP" ] || die "stock firmware not unpacked at $STOCK_DIR (scripts/$UNPACKER)"
squashfs_tools; mkenvimage_tool
# Debian keeps mke2fs in /usr/sbin, which a non-login shell's PATH lacks (B169, 2026-10-23).
MKE2FS=$(command -v mke2fs || command -v /usr/sbin/mke2fs || command -v /sbin/mke2fs || true); [ -n "$MKE2FS" ] || die "need mke2fs (e2fsprogs)"
D=$OAKMOSS_ROOT/diag
FBFILL=$BUILDS_DIR/fbfill
if [ "$DIAG" = 1 ] && [ ! -x "$FBFILL" ]; then
    CC=$ARMGNU_DIR/bin/aarch64-none-linux-gnu-gcc
    [ -x "$CC" ] || die "need the Arm toolchain to build fbfill (scripts/prepare-toolchain.sh)"
    mkdir -p "$BUILDS_DIR"; "$CC" -static -Os -s -o "$FBFILL" "$D/fbfill.c"; log "built fbfill"
fi
f() { p="$DUMP/$1"; [ -f "$p" ] || die "image item missing: $1"; printf '%s' "$p"; }
BOOT0=$(f '12345678_1234567890BOOT_0'); BOOT0_NAND=$DUMP/'BOOT    _BOOT0_0000000000'
# BOOTRES=<file> replaces the stock boot-resource partition (bootloader, p1): the
# output of scripts/make-boot-resource.py, whose bootloader screens fit this panel.
BOOTPKG=$(f '12345678_BOOTPKG-00000000'); BOOTIMG=$(f 'RFSFAT16_BOOT_FEX00000000')
if [ -n "${BOOTRES:-}" ]; then [ -f "$BOOTRES" ] || die "BOOTRES=$BOOTRES: no such file"; log "boot-resource: $BOOTRES (board-sized bootloader screens)"
elif [ "$STOCK" = tina ] && [ ! -f "$DUMP/RFSFAT16_BOOT-RESOURCE_FE" ]; then
    # the Tina stock chain is public without its logo partition: take this build's (our logo)
    BOOTRES=$(ls "$BUILD"/*.img.dump/boot-resource.fex 2>/dev/null | head -1); [ -f "$BOOTRES" ] || die "no boot-resource.fex under $BUILD"
    log "boot-resource: this build's ($BOOTRES)"
else BOOTRES=$(f 'RFSFAT16_BOOT-RESOURCE_FE'); fi
# OWN_BOOTRES_FILES=1 (board.conf): the board's own bootloader pictures (boards/<board>/boot-resource:
# the boot logo and the charge pictures, scripts/make-charge-screens.py) go into a COPY of that
# partition with mtools, nothing mounted; the rest of it (fonts, wavefiles, the panel index) stays.
BOOTRES_NOTE=
if [ "${OWN_BOOTRES_FILES:-0}" = 1 ]; then
    BRD=$OAKMOSS_ROOT/boards/$BOARD/boot-resource
    MCOPY=${MCOPY:-$SDK_DIR/out/host/bin/mcopy}; [ -x "$MCOPY" ] || MCOPY=$(command -v mcopy || true)
    [ -x "$MCOPY" ] || die "OWN_BOOTRES_FILES: need mcopy (the SDK's out/host/bin, or mtools)"
    [ -f "$BRD/bootlogo.bmp" ] || die "OWN_BOOTRES_FILES: no $BRD/bootlogo.bmp (scripts/make-charge-screens.py $BOARD)"
fi
ENVSTOCK=$(f 'RFSFAT16_ENV_FEX000000000')
if [ "$STOCK" = android ]; then
    DTBO=$(f 'RFSFAT16_DTBO_FEX00000000')
    VBMETA=$(f 'RFSFAT16_VBMETA_FEX000000'); VBMETA_SYS=$(f 'RFSFAT16_VBMETA_SYSTEM_FE'); VBMETA_VEN=$(f 'RFSFAT16_VBMETA_VENDOR_FE')
else
    DTBO=; VBMETA=; VBMETA_SYS=; VBMETA_VEN=      # Tina stock: these stay blank
fi
[ "$(head -c 8 "$BOOT0" | tail -c 4)" = "eGON" ] || die "boot0 magic missing"
[ "$(basename "$BOOT0")" = "12345678_1234567890BOOT_0" ] || die "wrong boot0 item: need the card one"
if [ -f "$BOOT0_NAND" ] && cmp -s "$BOOT0" "$BOOT0_NAND"; then die "boot0 sanity check failed: the card and NAND boot0 items are identical"; fi
mkdir -p "$OUT"
need_tmp_space 2048
W=$(mktemp -d "${TMPDIR:-/tmp}/oakmoss-own.XXXX"); trap 'rm -rf "$W"' EXIT

if [ "${OWN_BOOTRES_FILES:-0}" = 1 ]; then
    # Allwinner's fsbuild leaves the BPB's geometry fields at zero, which mtools refuses unless told not to.
    export MTOOLS_SKIP_CHECK=1
    cp "$BOOTRES" "$W/bootres.fex"; n=0
    while IFS= read -r -d '' src; do
        rel=${src#"$BRD"/}
        "$MCOPY" -o -i "$W/bootres.fex" "$src" "::$rel" || die "mcopy $rel into the boot-resource failed"
        "$MCOPY" -n -i "$W/bootres.fex" "::$rel" "$W/bootres-check" && cmp -s "$src" "$W/bootres-check" || die "$rel reads back different"
        n=$((n + 1))
    done < <(find "$BRD" -type f -print0 | sort -z)
    rm -f "$W/bootres-check"
    BOOTRES_NOTE=" + $n pictures from boards/$BOARD/boot-resource"
    log "boot-resource: $BOOTRES$BOOTRES_NOTE (read back)"
    BOOTRES=$W/bootres.fex
fi

log "rootfs: our $BOARD squashfs, hand-off and probe added"
"$UNSQUASHFS" -n -d "$W/root" "$ROOTFS" >/dev/null 2>"$W/unsq.err" || true
[ -f "$W/root/usr/magicx/bin/runmagicx.sh" ] || { echo "unsquash failed"; head -3 "$W/unsq.err"; exit 1; }
R=$W/root
[ "$(tr -d '\r\n' < "$R/usr/magicx/device")" = "$BOARD" ] || die "rootfs marker is not $BOARD"
echo "    modules: $(ls "$R"/lib/modules/*/ | wc -l) ($(ls "$R"/lib/modules/)), PVR userland: $(strings "$R/usr/lib/libGLESv2.so" | grep -m1 -oE '[0-9]+\.[0-9]+@[0-9]+')"
# Radios the board lacks: their modules stay, only the boot-time autoload goes.
for m in $OWN_AUTOLOAD_DROP; do
    [ -f "$R/etc/modules.d/$m" ] || die "OWN_AUTOLOAD_DROP: the rootfs has no /etc/modules.d/$m"
    rm -f "$R/etc/modules.d/$m"
done
[ -z "$OWN_AUTOLOAD_DROP" ] || echo "    autoload dropped: $OWN_AUTOLOAD_DROP"
# oakmoss-update.sh installs only updates of the card's own lane: this one boots the stock chain.
printf 'own\n' > "$R/usr/magicx/lane"
# A card whose vendor chain stays byte-identical: oakmoss-update.sh refuses packages that would write it.
if [ "${OWN_STOCK_DT:-0}" = 1 ]; then
    printf '%s\n' "boot0, the U-Boot package and the boot-resource are the vendor's, byte-identical" > "$R/usr/magicx/keep-boot-chain"
fi
# TrimUI's input daemon (overlay/etc/init.d/trimui-inputd starts it): a LOCAL image from here on (user,
# 2026-10-25), marked so in the rootfs and in BUILD-INFO. The GPIO lines are the ones stock sets first.
if [ "${OWN_TRIMUI_INPUTD:-0}" = 1 ]; then
    [ -f "$STOCK_DIR/trimui_inputd" ] || die "OWN_TRIMUI_INPUTD: no $STOCK_DIR/trimui_inputd (scripts/$UNPACKER)"
    [ -x "$R/etc/init.d/trimui-inputd" ] && [ -L "$R/etc/rc.d/S14trimui-inputd" ] ||
        die "OWN_TRIMUI_INPUTD: this build has no trimui-inputd init script (overlay/etc/init.d)"
    install -D -m 0755 "$STOCK_DIR/trimui_inputd" "$R/usr/trimui/bin/trimui_inputd"
    printf '%s\n' "carries TrimUI's closed trimui_inputd: local images only, never published (user, 2026-10-25)" > "$R/usr/magicx/local-only"
    echo "    trimui_inputd: TrimUI's, from the stock rootfs (a LOCAL image)"
fi
if [ -n "${OWN_TRIMUI_GPIO:-}" ]; then
    printf '%s\n' $OWN_TRIMUI_GPIO > "$R/usr/magicx/trimui-gpio"; echo "    GPIO lines set at boot: $OWN_TRIMUI_GPIO"
fi
# /dev/by-name follows the disk the root is on (two cards, probe order): as make-hybrid-stock.sh
python3 - "$R/etc/init.d/boot" <<'PY'
import sys
p = sys.argv[1]; s = open(p, newline='').read()
old = ('\t\tif [ -n "${parts}" ]; then\n\t\t\twhile [ "$part" != "$parts" ]\n\t\t\tdo\n'
       '\t\t\t\t\tpart=${parts%%:*}\n\t\t\t\t\tln -s "/dev/${part#*@}" "/dev/by-name/${part%@*}"\n\t\t\t\t\tparts=${parts#*:}\n\t\t\tdone\n')
new = ('\t\tif [ -n "${parts}" ]; then\n'
       '\t\t\t_rootmm="$(awk \'$5=="/" {print $3; exit}\' /proc/self/mountinfo 2>/dev/null)"\n\t\t\t_rootdisk=""\n'
       '\t\t\tfor _b in /sys/class/block/mmcblk*p*; do\n\t\t\t\t[ -e "$_b/dev" ] || continue\n'
       '\t\t\t\tif [ "$(cat "$_b/dev" 2>/dev/null)" = "$_rootmm" ]; then\n\t\t\t\t\t_rootdisk="${_b##*/}"; _rootdisk="${_rootdisk%p*}"\n\t\t\t\t\tbreak\n\t\t\t\tfi\n\t\t\tdone\n'
       '\t\t\twhile [ "$part" != "$parts" ]\n\t\t\tdo\n\t\t\t\t\tpart=${parts%%:*}\n\t\t\t\t\t_dev="${part#*@}"\n'
       '\t\t\t\t\tcase "$_dev" in\n\t\t\t\t\t\tmmcblk[0-9]*) [ -n "$_rootdisk" ] && _dev="${_rootdisk}${_dev#mmcblk[0-9]}" ;;\n\t\t\t\t\tesac\n'
       '\t\t\t\t\tln -s "/dev/${_dev}" "/dev/by-name/${part%@*}"\n\t\t\t\t\tparts=${parts#*:}\n\t\t\tdone\n')
if old not in s: raise SystemExit("etc/init.d/boot: the by-name loop is not the shape this patch expects")
open(p, 'w', newline='').write(s.replace(old, new)); print("    /dev/by-name follows the root disk, not a fixed mmcblk0")
PY
cp "$R/usr/magicx/bin/runmagicx.sh" "$R/usr/magicx/bin/runmagicx.sh.orig"
INIT=/sbin/init
# INIT_STAMP=1 (diagnostic, needs PSTORE=1): init= writes "i<uptime>;" to the last sector
# of the pstore partition before handing to /sbin/init - the stage marker between the
# kernel's jump (bootmark "k") and the first rootfs_data mount.
if [ "${INIT_STAMP:-0}" = 1 ]; then
    [ "${PSTORE:-0}" = 1 ] || die "INIT_STAMP=1 needs PSTORE=1"
    install -m 0755 "$OAKMOSS_ROOT/diag/init-stamp.sh" "$R/sbin/init-stamp"; INIT=/sbin/init-stamp; echo "    init stamp: init=/sbin/init-stamp"
fi
if [ "$DIAG" = 1 ]; then
    install -m 0755 "$D/runmagicx-diag.sh" "$R/usr/magicx/bin/runmagicx.sh"; install -m 0755 "$FBFILL" "$R/usr/magicx/bin/fbfill"
    log "hand-off: DIAGNOSTIC (DIAG=0 for the stock one)"
    if [ "$EARLY_PROBE" = 1 ]; then install -m 0755 "$D/init-probe.sh" "$R/sbin/init-probe"; INIT=/sbin/init-probe; echo "    early probe: init=/sbin/init-probe"; fi
    if [ -n "$EXPERIMENTS" ]; then
        EGLTEST=$BUILDS_DIR/egltest
        if [ ! -x "$EGLTEST" ] || [ "$D/egltest.c" -nt "$EGLTEST" ]; then "$ARMGNU_DIR/bin/aarch64-none-linux-gnu-gcc" -O -o "$EGLTEST" "$D/egltest.c" -ldl || exit 1; fi
        mkdir -p "$R/usr/magicx/diag/experiments"; install -m 0755 "$EGLTEST" "$R/usr/magicx/diag/egltest"
        for x in $EXPERIMENTS; do [ -f "$D/experiments/$x.sh" ] || die "no such experiment: $x"; install -m 0755 "$D/experiments/$x.sh" "$R/usr/magicx/diag/experiments/$x.sh"; echo "    experiment installed: $x"; done
    fi
else
    install -m 0755 "$OAKMOSS_ROOT/overlay/usr/magicx/bin/runmagicx.sh" "$R/usr/magicx/bin/runmagicx.sh"; log "hand-off: stock"
    # BOOT_DMESG=1 (diagnostic): the hand-off also saves the kernel log of every boot that
    # reaches it to UDISK (oakmoss-dmesg-<time>.log), so a card read back after a mixed run
    # carries the good boots' full kernel logs next to oakmoss-boot.log.
    if [ "${BOOT_DMESG:-0}" = 1 ]; then
        python3 - "$R/usr/magicx/bin/runmagicx.sh" <<'PYD' || die "BOOT_DMESG: hand-off patch failed"
import sys
p = sys.argv[1]; s = open(p, newline='').read()
a = 'echo "=== boot $(date \'+%Y-%m-%d %H:%M:%S\') device=$(cat /usr/magicx/device 2>/dev/null)" >> "$LOG" 2>/dev/null\n'
assert s.count(a) == 1, "boot banner line not found"
open(p, 'w', newline='').write(s.replace(a, a + 'dmesg > "/mnt/UDISK/oakmoss-dmesg-$(date +%H%M%S).log" 2>/dev/null; sync\n'))
PYD
        echo "    hand-off saves dmesg to UDISK"
    fi
    # LATE_TOUCH=1 (diagnostic): with no user card the hand-off loads the board's touch module
    # (XU20 hynitron.ko, Zero 40 axs15205.ko; tree patch 090 packages both, autoloading neither)
    # just before it powers off, when the board has settled: in the background, with up to
    # 5 s for the input node, logging the outcome and saving the kernel log, so an SD1-only
    # run exercises the late probe. With a user card the launcher loads it (spruce
    # magicx_load_touch) and this stays out of the way.
    if [ "${LATE_TOUCH:-0}" = 1 ]; then
        case $BOARD in xu20) TMOD=hynitron; TPAT='*hyn*' ;; zero40) TMOD=axs15205; TPAT='*axs*' ;; esac
        ls "$R"/lib/modules/*/$TMOD.ko >/dev/null 2>&1 || die "LATE_TOUCH: no $TMOD.ko in the rootfs (sdk-patches/tree/090, kmod-touchscreen-*)"
        [ -z "$(grep -rlw "$TMOD" "$R"/etc/modules.d 2>/dev/null)" ] || die "LATE_TOUCH: $TMOD is set to autoload (/etc/modules.d)"
        python3 - "$R/usr/magicx/bin/runmagicx.sh" "$TMOD" "$TPAT" <<'PYT' || die "LATE_TOUCH: hand-off patch failed"
import sys
p, mod, pat = sys.argv[1:4]; s = open(p, newline='').read()
a = '    log "no card or nothing to run after ${n} x 0.5 s; powering off"\n'
assert s.count(a) == 1, "no-card branch not found"
late = ('    t0=$(cut -d" " -f1 /proc/uptime)\n'
        f'    modprobe {mod} >/tmp/oakmoss-touch.err 2>&1 &\n'
        '    tp=$!; i=0; node=""\n'
        '    while [ $i -lt 10 ]; do\n'
        '        for d in /sys/class/input/event*; do case "$(cat "$d/device/name" 2>/dev/null)" in ' + pat + ') node=${d##*/} ;; esac; done\n'
        '        [ -n "$node" ] && break; sleep 0.5; i=$((i + 1))\n'
        '    done\n'
        '    if kill -0 $tp 2>/dev/null; then st="modprobe still running"; else wait $tp; st="modprobe rc=$?"; fi\n'
        f'    log "late touch load ({mod}) at ${{t0}} s: $st; input node: ${{node:-none}} after ${{i}} x 0.5 s; $(head -1 /tmp/oakmoss-touch.err 2>/dev/null)"\n'
        '    dmesg > "/mnt/UDISK/oakmoss-dmesg-$(date +%H%M%S)-touch.log" 2>/dev/null; sync\n')
open(p, 'w', newline='').write(s.replace(a, late + a))
PYT
        echo "    hand-off loads the touch module ($TMOD) late when there is no user card"
    fi
fi
"$MKSQUASHFS" "$R" "$W/rootfs.fex" -noappend -root-owned -comp xz -b 262144 -processors "$(nproc)" \
    -p '/dev d 755 0 0' -p '/dev/console c 600 0 0 5 1' >/dev/null 2>"$W/mksq.err" || { cat "$W/mksq.err" >&2; die "mksquashfs failed"; }
echo "    rootfs squashfs: $(stat -c%s "$W/rootfs.fex") bytes"
EXT4_FEATURES='has_journal,ext_attr,resize_inode,dir_index,filetype,extent,flex_bg,sparse_super,large_file,huge_file,uninit_bg,dir_nlink,extra_isize,^64bit,^metadata_csum'
# e2fsprogs 1.47 adds orphan_file by default; the boards' e2fsck 1.42 refuses it ("FEATURE_C12") at every
# boot (V90S, 2026-10-24). An older mke2fs does not know the name, hence the trial run.
"$MKE2FS" -q -F -t ext4 -O ^orphan_file "$W/orphan-trial.ext4" 8M >/dev/null 2>&1 && EXT4_FEATURES="$EXT4_FEATURES,^orphan_file"
rm -f "$W/orphan-trial.ext4"
"$MKE2FS" -q -t ext4 -O "$EXT4_FEATURES" -L rootfs_data -m 0 "$W/rootfs_data.ext4" 64M
"$MKE2FS" -q -t ext4 -O "$EXT4_FEATURES" -L UDISK -m 0 "$W/udisk.ext4" 16M

cp "$BOOTPKG" "$W/boot_package.fex"
if [ "${OWN_STOCK_DT:-0}" = 1 ]; then
    log "device tree: the stock package's own, the package byte-identical"
    : > "$W/our.dtb"    # unused: a v0 boot image carries no tree
else
    log "device tree: ours, into the stock boot package and into the boot image"
    python3 "$OAKMOSS_ROOT/scripts/toc1-item.py" --extract "$OURPKG" dtb "$W/our.dtb"
    python3 "$OAKMOSS_ROOT/scripts/toc1-item.py" --replace "$W/boot_package.fex" dtb "$W/our.dtb"
    python3 "$OAKMOSS_ROOT/scripts/toc1-checksum.py" --fix "$W/boot_package.fex"
fi
# boot image: the stock header (addresses, page size, its command line) with our
# kernel, a placeholder ramdisk (our kernel mounts root= itself), our tree, and no
# header command line of its own.
python3 - "$BOOTIMG" "$OURBOOT" "$W/our.dtb" "$W/boot.img" "$STOCK" <<'PY'
import struct, sys, hashlib
stock, ours, dtb, out, kind = sys.argv[1:6]
h = bytearray(open(stock, 'rb').read(2048))
ps = struct.unpack_from('<I', h, 36)[0]; hv = struct.unpack_from('<I', h, 40)[0]
assert h[:8] == b'ANDROID!' and hv == (2 if kind == 'android' else 0), f"expected a header v{2 if kind == 'android' else 0} stock boot image, got v{hv}"
o = open(ours, 'rb').read(); oks, ops = struct.unpack_from('<I', o, 8)[0], struct.unpack_from('<I', o, 36)[0]
kernel = o[ops:ops + oks]
assert kernel[56:60] == b'ARM\x64', "our boot.fex does not carry an arm64 Image"
ramdisk = b'\0' * 12; tree = open(dtb, 'rb').read() if hv == 2 else b''
pg = lambda n: (n + ps - 1) // ps * ps
struct.pack_into('<I', h, 8, len(kernel)); struct.pack_into('<I', h, 16, len(ramdisk)); struct.pack_into('<I', h, 24, 0)
if hv == 2:
    struct.pack_into('<I', h, 1632, 0); struct.pack_into('<I', h, 1648, len(tree))
body = kernel.ljust(pg(len(kernel)), b'\0') + ramdisk.ljust(pg(len(ramdisk)), b'\0') + tree.ljust(pg(len(tree)), b'\0')
sha = hashlib.sha1(); 
for part, n in ((kernel, len(kernel)), (ramdisk, len(ramdisk)), (b'', 0)):
    sha.update(part); sha.update(struct.pack('<I', n))
h[576:576 + 20] = sha.digest(); h[596:608] = b'\0' * 12
h[64:576] = b'\0' * 512   # no header command line: no Android firmware paths, no dtbo overlay request; bootargs are ours
open(out, 'wb').write(bytes(h).ljust(ps, b'\0') + body)
print(f"    boot.img: kernel {len(kernel)} B (ours), ramdisk placeholder, "
      + (f"dtb {len(tree)} B (ours), header v2" if hv == 2 else "header v0, the tree from the package") + ", header cmdline blank")
PY

log "env: stock variables, root and init pointed at our rootfs (squashfs, our kernel)"
ROOT_UUID=$(python3 -c 'import uuid; print(uuid.uuid4())'); printf '%s' "$ROOT_UUID" > "$W/rootfs.uuid"
ROOTB_UUID=$(python3 -c 'import uuid; print(uuid.uuid4())'); printf '%s' "$ROOTB_UUID" > "$W/rootfs_b.uuid"
STOCK=$STOCK AB=$AB EMMC=${OWN_EMMC:-0} python3 - "$ENVSTOCK" "$W/env.txt" "$ROOT_UUID" "$INIT" "${CONSOLE:-}" "${EXTRA_BOOTARGS:-}" "$ROOTB_UUID" <<'PY'
import os, struct, sys, zlib
raw = open(sys.argv[1], 'rb').read(); root_uuid, init, console, extra_args, root_b_uuid = sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6], sys.argv[7]
# A redundant env (the Powkiddy cards) has a flag byte after the CRC; read as plain, it
# prefixed the first variable's name (B169R's env had "\x01bootdelay").
d = raw[5:] if zlib.crc32(raw[5:]) & 0xffffffff == struct.unpack_from('<I', raw)[0] else raw[4:]
kv = dict(v.decode().split('=', 1) for v in d.split(b'\0') if v)
kv['nand_root'] = kv['mmc_root'] = 'PARTUUID=' + root_uuid
kv['init'] = init; kv['loglevel'] = '7'
# CONSOLE overrides the stock console list. A KDEBUG_FBCON kernel needs tty0 in it
# for the kernel log to reach the panel; the lab units have no serial header, so the
# stock ttyS0 alone means an early panic is invisible (docs/hardware-notes.md).
if console:
    kv['console'] = console
# The stock Android env hands the kernel cma=8M; our disp driver allocates the
# framebuffer from that pool through dma_alloc_coherent (dev_disp.c) and the
# GPU's ion heap draws on it too. The XU20's 1024x768 double-buffered fb is 6 MB
# of the 8; the Zero 40's 480x800 is 3. Our own chain boots with the SDK's
# cma=32M (env-4.9.cfg), so this one does too.
kv['cma'] = '32M'
kv['partitions'] = 'bootloader@mmcblk0p1:env@mmcblk0p2:boot@mmcblk0p3:misc@mmcblk0p4:dtbo@mmcblk0p5:rootfs@mmcblk0p6:rootfs_data@mmcblk0p7:UDISK@mmcblk0p8:vbmeta@mmcblk0p9:vbmeta_system@mmcblk0p10:vbmeta_vendor@mmcblk0p11'
if extra_args and 'pstore_blk' in extra_args:
    kv['partitions'] += ':pstore@mmcblk0p12'
# The redundant env's second copy (mkenvimage -r below) is the last GPT entry, so
# /etc/fw_env.config's /dev/by-name/env-redund exists.
if os.environ.get('STOCK') == 'tina':
    kv['partitions'] += ':env-redund@mmcblk0p%d' % (13 if 'pstore@' in kv['partitions'] else 12)
# Slot B, after everything else so that it moves nothing: empty on a new card.
if os.environ.get('AB') == '1':
    n = kv['partitions'].count('@') + 1
    kv['partitions'] += f':boot_b@mmcblk0p{n}:rootfs_b@mmcblk0p{n + 1}'
# ROOTDELAY=N (diagnostic) replaces rootwait: the kernel sleeps N s, tries the root
# device once and panics if it is missing, so with panic=S a boot whose SD1 host never
# enumerated reboots by itself instead of waiting on the logo forever (2026-09-18).
_rd = os.environ.get('ROOTDELAY', '')
extra = (f' rootdelay={int(_rd)}' if _rd else ' rootwait') + ' rootfstype=squashfs partitions=${partitions} cma=${cma}'
# EXTRA_BOOTARGS is appended verbatim, for arguments with no env variable of their
# own: fbcon=rotate:2 on the XU20, whose panel is mounted upside down, so a
# KDEBUG_FBCON kernel prints its log the right way up.
if extra_args:
    extra += ' ' + extra_args
kv['setargs_nand'] = 'setenv bootargs earlyprintk=${earlyprintk} initcall_debug=${initcall_debug} console=${console} loglevel=${loglevel} root=${nand_root} init=${init}' + extra
kv['setargs_mmc'] = 'setenv bootargs earlyprintk=${earlyprintk} initcall_debug=${initcall_debug} console=${console} loglevel=${loglevel} root=${mmc_root} init=${init}' + extra
# BOOTMARK=1: every U-Boot pass that reaches bootcmd appends a 'u' to the env variable
# bootmark and saves the env (stock U-Boot has saveenv), so a card read back after a
# wedged boot shows whether U-Boot handed over at all - the one question no kernel-
# side record can answer (2026-09-18). Diagnostic only: it writes the env partition
# on every boot.
# KMARK=1 (with BOOTMARK=1, and a KDEBUG_MARK=1 kernel): the kernel writes its progress
# to RTC general-purpose register 5 (0x07000114; U-Boot uses 0 reboot-script, 2 FEL,
# 6 boot mode, 7 bootcount), which keeps its value through a reset and a held-power
# shutdown. Each U-Boot pass appends the value the PREVIOUS boot left there after its
# 'u' and clears it, so 'u<hex>' says where the boot before stopped: an initcall's
# address (System.map, saved beside the card), or 1-6 for the hand-off stages in
# sdk-patches/debug/kdebug-mark.patch.
KMARK = os.environ.get('KMARK') == '1'
# NEVER touch the register below it (0x07000110, GPR4): a bootcmd that also read and
# cleared GPR4 stopped both the XU20 and the Zero 40 in U-Boot before saveenv, on the
# first pass (2026-09-18; boot0, U-Boot and its tree byte-identical to a card that
# stamped). The kernel packs the touch-bus I2C phase into GPR5's low half instead.
_mark = 'setexpr.l kmark *0x07000114; mw.l 0x07000114 0; setenv bootmark ${bootmark}u${kmark}; ' if KMARK else 'setenv bootmark ${bootmark}u; '
kv['bootcmd'] = (_mark + 'saveenv; ' if os.environ.get('BOOTMARK') == '1' else '') + 'run setargs_mmc boot_normal'
if os.environ.get('BOOTMARK') == '1':
    kv['bootmark'] = ''
    # A second stamp, 'k', after U-Boot has read the kernel and just before bootm: a 'u'
    # without its 'k' means the stall is in U-Boot's kernel load, a 'uk' means U-Boot
    # jumped to the kernel and the stall is the kernel's.
    bn = kv['boot_normal']; assert ';bootm ' in bn, bn
    kv['boot_normal'] = bn.replace(';bootm ', ';setenv bootmark ${bootmark}k;saveenv;bootm ', 1)
# The slot check, as build.sh writes it for the SDK lane (docs/updates.md): no hush parser, so the
# branch is the variable's name. This U-Boot sets mmc_root from root_partition too (root=/dev/mmcblk0p6).
if os.environ.get('AB') == '1':
    bn = kv['boot_normal']
    assert bn.startswith('sunxi_flash read 45000000 ${boot_partition};') and kv.get('boot_partition') == 'boot' and kv.get('root_partition') == 'rootfs', bn
    kv['boot_normal'] = 'run ab_${ab_try};' + bn
    kv['ab_'] = 'setenv ab_try'
    kv['ab_1'] = 'setenv ab_try 2; saveenv'
    kv['ab_2'] = ('setenv boot_partition ${ab_fallback_boot}; setenv root_partition ${ab_fallback_root}; setenv ab_try; '
                  'setenv ab_fallback_boot; setenv ab_fallback_root; setenv ab_reverted 1; saveenv; reset')
# A board with an eMMC (TrimUI: mmcblk0, the stock firmware): U-Boot sets mmc_root from root_partition as
# /dev/mmcblk0pN (board_helper.c), which there names the eMMC. The root comes from oak_root instead, set by
# the slot's name (no hush parser: the name is the branch), so slot B and the fallback need nothing new.
if os.environ.get('EMMC') == '1':
    kv['oakroot_rootfs'] = 'setenv oak_root PARTUUID=' + root_uuid
    if os.environ.get('AB') == '1':
        kv['oakroot_rootfs_b'] = 'setenv oak_root PARTUUID=' + root_b_uuid
    assert kv['setargs_mmc'].count(' root=${mmc_root} ') == 1 and kv.get('root_partition') == 'rootfs'
    kv['setargs_mmc'] = kv['setargs_mmc'].replace(' root=${mmc_root} ', ' root=${oak_root} ')
    kv['bootcmd'] = kv['bootcmd'].replace('run setargs_mmc boot_normal', 'run oakroot_${root_partition} setargs_mmc boot_normal')
assert kv['init'] in ('/sbin/init', '/sbin/init-probe', '/sbin/init-stamp') and 'rdinit' not in kv['setargs_mmc']
assert kv['bootcmd'].endswith(('run setargs_mmc boot_normal', 'run oakroot_${root_partition} setargs_mmc boot_normal'))
open(sys.argv[2], 'w').write(''.join(f'{k}={v}\n' for k, v in kv.items()))
PY
# The Powkiddy stock U-Boot reads a redundant env (env + env-redund, a flag byte after the CRC) and
# falls back to its built-in env on a plain one, which boots nothing (V90S, 2026-10-23).
ENV_REDUND=; [ "$STOCK" = tina ] && ENV_REDUND=-r
"$MKENVIMAGE" $ENV_REDUND -s 131072 -p 0x00 -o "$W/env.fex" "$W/env.txt"
# The Powkiddy stock U-Boot reads its partition table at the card's 20 MiB mark (sector 40960), as the
# stock card lays it out; a card without one showed the backlight and nothing else (V90S, 2026-10-24).
# It is Allwinner's stock card shape: TrimUI's own rescue cards carry the same tables at 40960.
[ "$STOCK" = tina ] && GPT_LAYOUT=${GPT_LAYOUT:-powkiddy}
P1=40960; [ "${GPT_LAYOUT:-sdk}" = powkiddy ] && P1=41984

log "image: GPT layout ${GPT_LAYOUT:-sdk} (sdk: 128 entries @LBA 2048; stock: 16 @LBA 2), stock boot0 @16 and @256, our tree in the stock package @32800"
IMG=$OUT/oakmoss-$BOARD-own-$ST-sd1.img
STOCK=$STOCK AB=$AB GPT_LAYOUT=${GPT_LAYOUT:-sdk} python3 - "$IMG" "$W" "$BOOT0" "$W/boot_package.fex" "$BOOTRES" "$DTBO" "$VBMETA" "$VBMETA_SYS" "$VBMETA_VEN" "$PSTORE_PARTUUID" "$PSTORE" <<'PY'
import struct, sys, uuid, zlib, os
img, W, boot0, bootpkg, bootres, dtbo, vbmeta, vbmeta_sys, vbmeta_ven, pstore_uuid, pstore = sys.argv[1:12]
ROOT_UUID = uuid.UUID(open(f'{W}/rootfs.uuid').read().strip()); ROOTB_UUID = uuid.UUID(open(f'{W}/rootfs_b.uuid').read().strip()); S = 512
parts = [('bootloader', 65536, bootres), ('env', 32768, f'{W}/env.fex'), ('boot', 65536, f'{W}/boot.img'), ('misc', 32768, None),
         ('dtbo', 4096, dtbo), ('rootfs', 1048576, f'{W}/rootfs.fex'), ('rootfs_data', 131072, f'{W}/rootfs_data.ext4'), ('UDISK', 32768, f'{W}/udisk.ext4'),
         ('vbmeta', 32768, vbmeta), ('vbmeta_system', 32768, vbmeta_sys), ('vbmeta_vendor', 32768, vbmeta_ven),
         ]
# Crash log, 2 MB, blank, appended last so that enabling it moves nothing else, and
# ONLY when asked: an ordinary card must have the layout it has always had, or every
# card doubles as an experiment in whether an extra partition is survivable. It gets a
# fixed PARTUUID because the kernel names it on the command line. Its own partition
# rather than the blank 'misc': Android U-Boot reads misc as the bootloader control
# block, and pstore records there would read as boot commands.
if pstore == '1':
    parts.append(('pstore', 4096, None))
# The redundant env's second copy, the same image, last for the same reason (256 KB, as on the stock card).
if os.environ.get('STOCK') == 'tina':
    parts.append(('env-redund', 512, f'{W}/env.fex'))
if os.environ.get('AB') == '1':
    parts += [('boot_b', 65536, None), ('rootfs_b', 1048576, None)]
GPT_LAYOUT = os.environ.get('GPT_LAYOUT', 'sdk')
# powkiddy: the Powkiddy stock card's shape. Its U-Boot finds the partitions at the card's 20 MiB
# mark: a copy of the MBR and GPT at 40960 and Allwinner's table (softw411) at 40992, 41024 and
# 41056, relative to 40960, so the first partition starts at 41984 (V90S, 2026-10-24).
LOGICAL = 40960
start = 41984 if GPT_LAYOUT == 'powkiddy' else 40960; ents = []
for name, size, src in parts: ents.append((name, start, size, src)); start += size
total = start + 2048 + 34
f = open(img, 'wb'); f.truncate(total * S)
def wr(lba, path):
    if not path: return
    d = open(path, 'rb').read(); f.seek(lba * S); f.write(d)
wr(16, boot0); wr(256, boot0); wr(32800, bootpkg)
for name, st, size, src in ents:
    if src:
        assert os.path.getsize(src) <= size * S, f"{name}: {os.path.getsize(src)} > {size*S}"
        wr(st, src)
linux = uuid.UUID('0FC63DAF-8483-4772-8E79-3D69D8477DE4').bytes_le; attr = 0x8000200000000000; entry = b''
for name, st, size, src in ents:
    pu = {'rootfs': ROOT_UUID, 'rootfs_b': ROOTB_UUID}.get(name) or (uuid.UUID(pstore_uuid) if name == 'pstore' else uuid.uuid4())
    entry += linux + pu.bytes_le + struct.pack('<QQQ', st, st + size - 1, attr) + name.encode('utf-16-le').ljust(72, b'\0')
# The partition table is laid out the way MagicX's own firmware lays it out (the stock
# XU20 GPT item: entries at LBA 2, 17 entries, first usable LBA 32768), not the way the
# SDK's card packer does (entries at LBA 2048, 128 entries). A stuck XU20 card read back
# raw had its table rewritten IN PLACE AT LBA 2 (by Windows re-detecting the card, it
# turned out; docs/hardware-notes.md), sized by the header's entry count. With 128 entries
# that is 32 sectors over LBA 2-33, which erased boot0 at sector 16 and left a
# primary header pointing its entries at LBA 34848 (2026-09-18, read back off a card). 16
# entries = 4 sectors (LBA 2-5), clear of boot0, so the rewrite lands on a table already
# in the shape it writes. The boot0 mirror at 256 stays as a safety net.
# GPT_LAYOUT=sdk (default): the SDK card packer's table, 128 entries at LBA 2048, first
# usable 34880 - the only layout observed to boot (first boots of two cards, 2026-09-18).
# GPT_LAYOUT=stock: MagicX's shape, 16 entries at LBA 2, first usable 6. It survives the
# in-place rewrite without erasing boot0, but a card built with it never reached
# userspace even on its first boot (xu20-gptfix, 2026-09-18), so it is diagnostic only.
# GPT_LAYOUT=powkiddy (the default for v90s/v20): 16 entries at LBA 2, first usable 41984, as on
# the stock card, plus the tables at the 20 MiB mark (above).
NENT = 16 if GPT_LAYOUT in ('stock', 'powkiddy') else 128; assert len(ents) <= NENT
ENT_SECTORS = NENT * 128 // S
# First usable LBA = right after the array, as on MagicX's real cards (Zero 40 stock
# image: 20 entries at LBA 2 -> a 5-sector array, first usable 7). The rewrite sets the
# primary header's entry pointer to first_usable - array sectors while writing the
# array itself at LBA 2 (the old cards: 34880 - 32 = the 34848 read back off a card),
# so the two agree only when first_usable = 2 + array sectors.
FIRST_USABLE = {'stock': 2 + ENT_SECTORS, 'powkiddy': 41984}.get(GPT_LAYOUT, 34880)
entry = entry.ljust(NENT * 128, b'\0'); disk = uuid.uuid4().bytes_le; last = total - 1; ent_lba = 2 if GPT_LAYOUT in ('stock', 'powkiddy') else 2048; bk_ent = last - ENT_SECTORS
def header(cur, bak, ent):
    h = bytearray(92); h[0:8] = b'EFI PART'; struct.pack_into('<IIII', h, 8, 0x10000, 92, 0, 0)
    struct.pack_into('<QQQQ', h, 24, cur, bak, FIRST_USABLE, bk_ent - 1); h[56:72] = disk; struct.pack_into('<QIII', h, 72, ent, NENT, 128, zlib.crc32(entry) & 0xffffffff)
    struct.pack_into('<I', h, 16, zlib.crc32(bytes(h)) & 0xffffffff); return bytes(h).ljust(S, b'\0')
pmbr = bytearray(S); pmbr[446:462] = bytes([0, 0, 2, 0, 0xee, 0xff, 0xff, 0xff]) + struct.pack('<II', 1, min(last, 0xffffffff)); pmbr[510:512] = b'\x55\xaa'
f.seek(0); f.write(pmbr); f.seek(S); f.write(header(1, last, ent_lba)); f.seek(ent_lba * S); f.write(entry)
if GPT_LAYOUT == 'powkiddy':
    # The stock card's 20 MiB mark: the MBR, GPT header and entries copied byte for byte, then
    # Allwinner's table in copies 1-3 (copy 0's place holds the MBR copy there too). Fields as on the
    # stock card: user_type 0x8000 (UDISK 0x8100), sig_verify on boot, sig_erase on UDISK; CRC over 4..16383.
    f.seek(LOGICAL * S); f.write(bytes(pmbr)); f.write(header(1, last, ent_lba)); f.write(entry)
    sm = bytearray(16384)
    struct.pack_into('<I8sIIII', sm, 4, 0x200, b'softw411', 4, 0, len(ents), 0)
    for k, (name, st, size, src) in enumerate(ents):
        rel = st - LOGICAL
        struct.pack_into('<IIII16s16sIIIII', sm, 32 + 128 * k, rel >> 32, rel & 0xffffffff, size >> 32, size & 0xffffffff,
                         b'DISK', name.encode(), 0x8100 if name == 'UDISK' else 0x8000, 0, 0,
                         0x8000 if name == 'boot' else 0, 0x8000 if name == 'UDISK' else 0)
    for index in (1, 2, 3):
        struct.pack_into('<I', sm, 20, index); struct.pack_into('<I', sm, 0, zlib.crc32(bytes(sm[4:])) & 0xffffffff)
        f.seek((LOGICAL + 32 * index) * S); f.write(bytes(sm))
f.seek(bk_ent * S); f.write(entry); f.seek(last * S); f.write(header(last, 1, bk_ent)); f.close()
print(f"    {img}: {total*S/1e6:.0f} MB, {len(ents)} partitions, rootfs = p6")
PY
flush_file "$IMG"
log "verify"
[ "$(dd if="$IMG" bs=512 skip=16 count=1 status=none | head -c 8 | tail -c 4)" = "eGON" ] || die "no boot0 at sector 16"
[ "$(dd if="$IMG" bs=512 skip=256 count=1 status=none | head -c 8 | tail -c 4)" = "eGON" ] || die "no boot0 mirror at sector 256"
[ "$(dd if="$IMG" bs=512 skip=32800 count=1 status=none | head -c 13)" = "sunxi-package" ] || die "no boot package at sector 32800"
python3 "$OAKMOSS_ROOT/scripts/toc1-checksum.py" --check "$IMG" 32800 || die "the boot package would be refused by boot0"
[ "$(dd if="$IMG" bs=512 skip=$((P1+65536+32768)) count=1 status=none | head -c 8)" = "ANDROID!" ] || die "boot partition is not an Android boot image"
[ "$(dd if="$IMG" bs=512 skip=$((P1+200704)) count=1 status=none | head -c 4)" = "hsqs" ] || die "rootfs partition is not our squashfs"
if [ "${GPT_LAYOUT:-sdk}" = powkiddy ]; then
    [ "$(dd if="$IMG" bs=512 skip=40961 count=1 status=none | head -c 8)" = "EFI PART" ] || die "no GPT copy at sector 40961"
    for s in 40992 41024 41056; do
        [ "$(dd if="$IMG" bs=512 skip=$s count=1 status=none | head -c 16 | tail -c 8)" = "softw411" ] || die "no Allwinner partition table at sector $s"
    done
fi
# OWN_STOCK_DT: what the card's U-Boot runs from is the vendor's, byte for byte (TrimUI's recovery lives there).
if [ "${OWN_STOCK_DT:-0}" = 1 ]; then
    on_img() { dd if="$IMG" bs=512 skip="$1" count=$(( ($(stat -c%s "$2") + 511) / 512 )) status=none | head -c "$(stat -c%s "$2")" | sha256sum | cut -d' ' -f1; }
    for s in 16 256; do [ "$(on_img $s "$BOOT0")" = "$(sha256_of "$BOOT0")" ] || die "boot0 at sector $s is not the stock one"; done
    [ "$(on_img 32800 "$BOOTPKG")" = "$(sha256_of "$BOOTPKG")" ] || die "the boot package at sector 32800 is not the stock one"
    [ "$(on_img $P1 "$BOOTRES")" = "$(sha256_of "$BOOTRES")" ] || die "the boot-resource is not the stock one"
    echo "    boot0 (16, 256), boot package (32800) and boot-resource: the stock items, byte for byte"
fi
# The update for this lane's cards (docs/updates.md): LANE=own, kernel slot and squashfs. Only
# OMUPD_BOOTCHAIN=1 adds boot0 and the U-Boot package, which are the vendor's here: local only.
UPD=
if [ "$AB" = 1 ]; then
    VER=$(cat "$R/usr/magicx/version"); BLD=$(cat "$R/usr/magicx/build")
    UPD=oakmoss-$BOARD-own-$VER.omupd
    python3 "$OAKMOSS_ROOT/scripts/make-update.py" --own $([ "${OMUPD_BOOTCHAIN:-0}" = 1 ] && echo --bootchain) \
        "$IMG" "$BOARD" "$VER" "$OUT/$UPD" "$BLD" >/dev/null || die "make-update.py --own failed"
    echo "    update: $UPD (LANE=own, BUILD $BLD$([ "${OMUPD_BOOTCHAIN:-0}" = 1 ] && echo ", with the vendor boot chain: local only"))"
fi
{
  echo "device=$BOARD"; echo "kind=own-kernel-stock-chain"; echo "built=$ST"; echo "oakmoss=$(oakmoss_version)"
  if [ "${OWN_STOCK_DT:-0}" = 1 ]; then
    echo "boot_chain=$CHAIN: card boot0 (also mirrored at sector 256), boot package with its own device tree and boot-resource, all byte-identical (checked)"
  else
    echo "boot_chain=$CHAIN: card boot0 (also mirrored at sector 256), boot package with OUR device tree in place of its dtb item (checksum redone), boot-resource${BOOTRES_NOTE}$([ "$STOCK" = android ] && echo ", dtbo, vbmeta x3")"
  fi
  [ "${OWN_TRIMUI_INPUTD:-0}" = 1 ] && echo "publish=NO: the rootfs carries TrimUI's closed trimui_inputd (local images only, user 2026-10-25)"
  echo "boot_chain_sha256=$CHAIN_SHA"
  echo "kernel=ours from $BUILD ($(grep -m1 '^kernel_encrypt_obj_md5' "$BUILD/BUILD-INFO.txt")), in a $([ "$STOCK" = android ] && echo "header-v2 boot image with our device tree" || echo "header-v0 boot image (the tree comes from the package)"); board_dts=$(grep -m1 '^board_dts' "$BUILD/BUILD-INFO.txt" | cut -d= -f2-)"
  echo "rootfs=our $BOARD rootfs squashfs from $BUILD (md5 $(md5_of "$ROOTFS") before the hand-off/probe repack; our modules, PowerVR 1.19)"
  echo "handoff=$([ "$DIAG" = 1 ] && echo "DIAGNOSTIC (init=$INIT, experiments: ${EXPERIMENTS:-none})" || echo stock)"
  echo "autoload_dropped=${OWN_AUTOLOAD_DROP:-none}"
  echo "lane=own (/usr/magicx/lane); update=${UPD:-none (AB=0: one slot)}"
  echo "layout=bootloader env boot misc dtbo rootfs(p6, squashfs) rootfs_data UDISK vbmeta vbmeta_system vbmeta_vendor$([ "$STOCK" = tina ] && echo " (dtbo and vbmeta blank), env-redund (redundant env)")$([ "$AB" = 1 ] && echo ", boot_b + rootfs_b last (slot B, empty)"); GPT layout ${GPT_LAYOUT:-sdk}; root=PARTUUID via $([ "${OWN_EMMC:-0}" = 1 ] && echo "oak_root (U-Boot's mmc_root would name the eMMC)" || echo mmc_root)"
  e=$(tr '\n' ';' < "$W/env.txt")
  if [ ${#e} -gt 400 ]; then e="${e:0:400}...[truncated]"; fi
  echo "env=$e"
  if [ "${OWN_EMMC:-0}" = 1 ]; then
    echo "outputs=$(basename "$IMG") (raw GPT image: write raw, eject, boot; the card in the TF slot (sdc0), the stock eMMC (sdc2) left alone)"
  else
    echo "outputs=$(basename "$IMG") (raw GPT image: write raw, eject, boot; $([ "$STOCK" = tina ] && echo "system card in TF1 (sdc0), user card in TF2 (sdc1)" || echo "system card in the sdc2 slot, user card in the sdc0 slot"))"
  fi
} > "$OUT/BUILD-INFO.txt"
cp "$W/env.txt" "$OUT/env.txt"; ( cd "$OUT" && md5sum ./*.img > md5sums.txt )
log "$BOARD own-kernel image ready: $OUT"; ls -la "$OUT" >&2
