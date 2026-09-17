#!/usr/bin/env bash
# STOCK-CHAIN SD1 image for a MagicX board whose panel and touch drivers are in
# neither our SDK drop nor main-zero40: the device's own boot chain (card boot0,
# U-Boot + DTB boot package, boot-resource, dtbo, vbmeta) and its stock Android
# boot image, byte for byte, booting OUR Zero 40 rootfs as ext4 - the stock
# kernel has no squashfs - with the vendor's modules for that kernel (4.9.170,
# MODVERSIONS, so nothing of ours could load anyway), the PowerVR 1.11 userland
# its GPU driver expects, and either the diagnostic or the stock hand-off. The
# kernel is told to skip the Android ramdisk (rdinit=/nonexistent) and mount
# root= itself, so the boot image keeps its stock hash.
#
#   scripts/make-hybrid-stock.sh <board> <zero40 build dir> [out dir]     board: xu20 | zero40
#   (scripts/make-hybrid-xu20.sh and scripts/make-hybrid-zero40-stock.sh are the two wrappers)
#
# Both boards ship the same Allwinner Android BSP (kernel 4.9.170 #1/#18 2025,
# DDK 1.11@5516664, the same vendor module set, a device tree that differs in
# 174 lines: panel, touch, sticks, pad pins, radio). The XU20's firmware is a
# PhoenixSuit pack (unpack-xu20-stock.sh), the Zero 40's a raw card image
# (unpack-zero40-stock.sh); both unpackers produce the same item names, so
# from here on the recipe is one. See docs/hardware-notes.md.
#
# Inputs (fetch-inputs.sh + the board's unpacker): the stock firmware unpacked
# under inputs/<board>-stock/, and the TrimUI Smart Pro SDK /usr tarball for the
# nine PowerVR libraries (proprietary, never redistributed; only the libraries
# in inputs/xu20-pvr-1.11.sha256 are taken out of it).
#
# THE BOOT0 ITEM. Allwinner's image.cfg maps the two boot0 builds like this:
#     boot0_nand.fex    -> maintype "BOOT    "  subtype "BOOT0_0000000000"
#     boot0_sdcard.fex  -> maintype "12345678"  subtype "1234567890BOOT_0"
# so the CARD boot0 is the "12345678_1234567890BOOT_0" item, and the stock card
# script (item 12345678_1234567890SCRIPT) writes exactly that at sector 16.
# Confirmed against hardware: a bootable Zero 40 card carries boot0_sdcard.fex
# at sector 16 byte for byte. A build that had the two swapped never came up.
# (The Zero 40 unpacker cuts sector 16 of a card that boots, so there is no
# second candidate to confuse it with.)
#
# SECOND_SLOT=0 (the default) leaves the device tree stock. The earlier belief
# that a stock tree shows Linux exactly one card was WRONG: the system card sits
# in the slot on sdc2 (the eMMC-class controller, "non-removable" in the tree,
# the one card2_boot_para describes), which U-Boot enables at run time because
# it booted from it, and the user card sits in the slot on sdc0, which the
# stock tree already has "okay" with card detect. Both cards are visible
# untouched - the Zero 28 boots our images with sdc2 and sdc3 disabled in its
# tree file and mounts the user card all the same. SECOND_SLOT=1 additionally
# enables sdc2 and sdc3 statically; the images that carried it stopped behind
# the boot logo (XU20 2026-09-16 13:00; sdc3 drives PI pins nothing on these
# boards is known to use, sdc2 shares the card's regulator), so it stays off.
#
# DIAG=1 (the default while these boards are being brought up) installs the
# diagnostic hand-off (diag/); DIAG=0 installs overlay/usr/magicx/bin/runmagicx.sh,
# the one a shipped card carries. The diagnostic one paints the panel at each
# stage and powers the device off ten seconds after the hand-off returns, which
# is what you want when nothing is known and nobody can read a console - but it
# is NOT what a finished card does.
#
# Generalised from the XU20 recipe this repository started with.
# Nothing in this recipe has yet booted on a unit.
. "$(dirname "$0")/lib.sh"
BOARD=${1:?board: xu20 | zero40}; shift || true
case "$BOARD" in
    xu20)   STOCK_DIR=$XU20_STOCK_DIR;   DUMP=$STOCK_DIR/$XU20_STOCK_IMG.dump;   CHAIN_SHA=$XU20_STOCK_IMG_SHA256;   UNPACKER=unpack-xu20-stock.sh
            OUTNAME=xu20-hybrid;  RADIO=8189es   # ships no radio firmware, so the Realtek driver, which carries its own
            CHAIN="XU20 V32 stock firmware (github.com/Magicx-Breeze/XU20_V32, Developers release)" ;;
    zero40) STOCK_DIR=$ZERO40_STOCK_DIR; DUMP=$STOCK_DIR/$ZERO40_STOCK_IMG.dump; CHAIN_SHA=$ZERO40_STOCK_IMG_SHA256; UNPACKER=unpack-zero40-stock.sh
            OUTNAME=zero40-stock; RADIO=xr829    # persist.vendor.wlan_vendor=xradio in its vendor init; firmware shipped
            CHAIN="Zero 40 stock firmware (github.com/Magicx-Breeze/Zero40, release Zero40_V1, adb.img: the board's native Android)" ;;
    *) die "unknown board $BOARD (xu20 | zero40)" ;;
esac
BUILD=${1:?zero40 build directory (builds/<stamp>-zero40)}; shift || true
ST=$(stamp); OUT=${1:-$BUILDS_DIR/$ST-$OUTNAME}
DIAG=${DIAG:-1}
SECOND_SLOT=${SECOND_SLOT:-0}
ROOTFS=$(ls "$BUILD"/*.img.dump/rootfs.fex 2>/dev/null | head -1)
[ -f "$ROOTFS" ] || die "no rootfs.fex under $BUILD (scripts/build.sh image zero40 produces it)"
grep -q '^device=zero40' "$BUILD/BUILD-INFO.txt" 2>/dev/null || die "$BUILD is not a zero40 build (both boards reuse that rootfs)"
VEND=$STOCK_DIR/vendor/modules; FIRMWARE=$STOCK_DIR/vendor/etc/firmware; GPU_FW=$STOCK_DIR/vendor/firmware
[ -d "$DUMP" ] && [ -d "$VEND" ] || die "stock firmware not unpacked at $STOCK_DIR (scripts/$UNPACKER)"
tsp=$INPUTS_DIR/$TSP_USR_TGZ
[ -f "$tsp" ] || die "missing $tsp (the TrimUI Smart Pro SDK /usr tree; inputs/README.md)"
sha256_check "$tsp" "$TSP_USR_TGZ_SHA256" || die "unexpected $TSP_USR_TGZ"
squashfs_tools; mkenvimage_tool
MKE2FS=$(command -v mke2fs || true); [ -n "$MKE2FS" ] || die "need mke2fs (e2fsprogs)"
command -v docker >/dev/null || die "need docker (the device nodes are made as root in the build container)"
D=$OAKMOSS_ROOT/diag
FBFILL=$BUILDS_DIR/fbfill
if [ "$DIAG" = 1 ] && [ ! -x "$FBFILL" ]; then
    CC=$ARMGNU_DIR/bin/aarch64-none-linux-gnu-gcc
    [ -x "$CC" ] || die "need the Arm toolchain to build fbfill (scripts/prepare-toolchain.sh)"
    mkdir -p "$BUILDS_DIR"; "$CC" -static -Os -s -o "$FBFILL" "$D/fbfill.c"; log "built fbfill"
fi
# Items are named EXACTLY, never matched by prefix: the pack ships a "V" copy of
# every flashable item (VBOOT_FEX beside BOOT_FEX, VENV beside ENV, VVBMETA
# beside VBMETA, VBOOT-RESOURCE beside BOOT-RESOURCE), so a prefix match is one
# sort-order accident away from writing the verify copy.
f() { p="$DUMP/$1"; [ -f "$p" ] || die "image item missing: $1"; printf '%s' "$p"; }
BOOT0=$(f '12345678_1234567890BOOT_0')          # boot0_sdcard.fex - see the note above
BOOT0_NAND=$DUMP/'BOOT    _BOOT0_0000000000'    # boot0_nand.fex - must NOT be used here
BOOTPKG=$(f '12345678_BOOTPKG-00000000')
BOOTRES=$(f 'RFSFAT16_BOOT-RESOURCE_FE')
BOOTIMG=$(f 'RFSFAT16_BOOT_FEX00000000')
DTBO=$(f 'RFSFAT16_DTBO_FEX00000000')
ENVSTOCK=$(f 'RFSFAT16_ENV_FEX000000000')
VBMETA=$(f 'RFSFAT16_VBMETA_FEX000000')
VBMETA_SYS=$(f 'RFSFAT16_VBMETA_SYSTEM_FE')
VBMETA_VEN=$(f 'RFSFAT16_VBMETA_VENDOR_FE')
[ "$(head -c 8 "$BOOT0" | tail -c 4)" = "eGON" ] || die "boot0 magic missing"
# Guard against ever swapping the two again: the card boot0 and the NAND boot0
# both carry the eGON magic, so the magic alone proves nothing. They must differ,
# and the one we write must be the item the stock card script names.
[ "$(basename "$BOOT0")" = "12345678_1234567890BOOT_0" ] || die "wrong boot0 item: need the card one"
if [ -f "$BOOT0_NAND" ] && cmp -s "$BOOT0" "$BOOT0_NAND"; then die "boot0 sanity check failed: the card and NAND boot0 items are identical"; fi
mkdir -p "$OUT"
need_tmp_space 2048
W=$(mktemp -d "${TMPDIR:-/tmp}/oakmoss-stock.XXXX"); trap 'rm -rf "$W"' EXIT
log "PowerVR 1.11 userland out of $(basename "$tsp")"
mkdir -p "$W/tsp"
# shellcheck disable=SC2046  # the manifest's paths are the members to extract
tar xzf "$tsp" -C "$W/tsp" $(sed 's/^[0-9a-f]*  //' "$OAKMOSS_ROOT/inputs/xu20-pvr-1.11.sha256")
( cd "$W/tsp" && sha256sum -c --quiet "$OAKMOSS_ROOT/inputs/xu20-pvr-1.11.sha256" ) || die "the PowerVR libraries in $TSP_USR_TGZ do not match inputs/xu20-pvr-1.11.sha256"
TSP=$W/tsp/usr/lib
log "rootfs: unpack $(basename "$BUILD") and adapt it to the stock 4.9.170 kernel"
"$UNSQUASHFS" -n -d "$W/root" "$ROOTFS" >/dev/null 2>"$W/unsq.err" || true
[ -f "$W/root/usr/magicx/bin/runmagicx.sh" ] || { echo "unsquash failed"; head -3 "$W/unsq.err"; exit 1; }
R=$W/root
printf '%s\n' "$BOARD" > "$R/usr/magicx/device"
# vendor modules for the stock kernel (kmodloader loads /lib/modules/$(uname -r)/<name>.ko)
mkdir -p "$R/lib/modules/4.9.170"
for m in pvrsrvkm simplepad sunxi-vibrator backlight generic_bl lcd 8189es xr829 xradio_btlpm aic8800_bsp aic8800_fdrv aic8800_btlpm uwe5622_bsp_sdio sprdwl_ng sprdbt_tty gslX680new; do
    [ -f "$VEND/$m.ko" ] && cp -a "$VEND/$m.ko" "$R/lib/modules/4.9.170/"
done
echo "    modules: $(ls "$R/lib/modules/4.9.170" | wc -l)"
# module list that fits that kernel: GPU, pad, rumble, and the board's radio
# (XU20: 8189es, whose driver carries its firmware; Zero 40: xr829, with the
# vendor's firmware files below). Nothing else autoloads.
rm -f "$R"/etc/modules.d/*
printf 'pvrsrvkm\n' > "$R/etc/modules.d/20-ge8300-km"
printf 'simplepad\n' > "$R/etc/modules.d/simplepad"
printf 'sunxi-vibrator\n' > "$R/etc/modules.d/70-vibrator"
case "$RADIO" in
    8189es) printf '8189es\n' > "$R/etc/modules.d/net-rtl8189es"; : > "$R/etc/modules.d/net-xr829" ;;
    xr829)  printf 'xr829\n' > "$R/etc/modules.d/net-xr829" ;;
esac
# The vendor's firmware goes where its kernel looks: the boot image's header
# command line (which U-Boot appends to bootargs) names firmware_class.path=
# /vendor/etc/firmware, and /lib/firmware is the default second place.
if [ -d "$FIRMWARE" ] && [ -n "$(ls "$FIRMWARE" 2>/dev/null)" ]; then
    mkdir -p "$R/lib/firmware" "$R/vendor/etc/firmware"
    cp -a "$FIRMWARE"/. "$R/lib/firmware/"; cp -a "$FIRMWARE"/. "$R/vendor/etc/firmware/"
    echo "    firmware: $(ls "$FIRMWARE" | tr '\n' ' ')"
fi
[ "$RADIO" = xr829 ] && [ ! -f "$R/lib/firmware/fw_xr829.bin" ] && die "xr829 autoloads but its firmware is missing"
# The GPU firmware must be the one pvrsrvkm 1.11 was built with. Our rootfs ships
# rgx.fw.22.102.54.38 for the SDK's 1.19 driver under the same name (the name is
# the GPU core's BVNC, not the DDK version); the vendor's copy replaces it.
[ -f "$GPU_FW/rgx.fw.22.102.54.38" ] || die "no PowerVR 1.11 firmware at $GPU_FW (re-run scripts/$UNPACKER)"
mkdir -p "$R/lib/firmware" "$R/vendor/firmware"
cp -a "$GPU_FW"/. "$R/lib/firmware/"; cp -a "$GPU_FW"/. "$R/vendor/firmware/"
rm -f "$R/lib/firmware/rgx.sh.22.102.54.38"    # the 1.19 driver's shader firmware; 1.11 has none
echo "    GPU firmware: $(ls "$GPU_FW" | tr '\n' ' ')(vendor, DDK 1.11)"
# PowerVR userland: DDK 1.11 (TrimUI Smart Pro SDK, verified against inputs/xu20-pvr-1.11.sha256)
# to match the stock kernel's pvrsrvkm 1.11 (our SDK ships 1.19)
for l in libEGL.so libGLESv2.so libglslcompiler.so libIMGegl.so libpvrNULL_WSEGL.so libPVROCL.so libPVRScopeServices.so libsrv_um.so libusc.so; do
    [ -f "$TSP/$l" ] || { echo "missing $TSP/$l" >&2; exit 1; }
    cp -a "$TSP/$l" "$R/usr/lib/$l"
done
rm -f "$R/usr/lib/libGLES_CM.so" "$R/usr/lib/libGLES_CM.so.1"
echo "    PVR userland: $(strings "$R/usr/lib/libGLESv2.so" | grep -m1 '1\.1[0-9]@[0-9]*')"
# /dev/by-name must follow the card we actually booted from. The base builds
# those links from the kernel's partitions= list, which names mmcblk0, but which
# mmc controller probes first is not fixed - and enabling the other SD
# controllers makes that a live question rather than a theoretical one. The root
# filesystem is found by PARTUUID and so is immune, but the overlay that makes
# /etc persistent is mounted through /dev/by-name/rootfs_data, and a link
# pointing at the other card's partition would silently lose every setting.
python3 - "$R/etc/init.d/boot" <<'PY'
import sys
p = sys.argv[1]
s = open(p, newline='').read()
old = ('\t\tif [ -n "${parts}" ]; then\n'
       '\t\t\twhile [ "$part" != "$parts" ]\n'
       '\t\t\tdo\n'
       '\t\t\t\t\tpart=${parts%%:*}\n'
       '\t\t\t\t\tln -s "/dev/${part#*@}" "/dev/by-name/${part%@*}"\n'
       '\t\t\t\t\tparts=${parts#*:}\n'
       '\t\t\tdone\n')
new = ('\t\tif [ -n "${parts}" ]; then\n'
       '\t\t\t# Which mmc controller is index 0 depends on probe order, not on\n'
       '\t\t\t# the device tree alias, so partitions= naming mmcblk0 is a guess.\n'
       '\t\t\t# Resolve the disk the root filesystem is really on and use that.\n'
       '\t\t\t_rootmm="$(awk \'$5=="/" {print $3; exit}\' /proc/self/mountinfo 2>/dev/null)"\n'
       '\t\t\t_rootdisk=""\n'
       '\t\t\tfor _b in /sys/class/block/mmcblk*p*; do\n'
       '\t\t\t\t[ -e "$_b/dev" ] || continue\n'
       '\t\t\t\tif [ "$(cat "$_b/dev" 2>/dev/null)" = "$_rootmm" ]; then\n'
       '\t\t\t\t\t_rootdisk="${_b##*/}"; _rootdisk="${_rootdisk%p*}"\n'
       '\t\t\t\t\tbreak\n'
       '\t\t\t\tfi\n'
       '\t\t\tdone\n'
       '\t\t\twhile [ "$part" != "$parts" ]\n'
       '\t\t\tdo\n'
       '\t\t\t\t\tpart=${parts%%:*}\n'
       '\t\t\t\t\t_dev="${part#*@}"\n'
       '\t\t\t\t\tcase "$_dev" in\n'
       '\t\t\t\t\t\tmmcblk[0-9]*) [ -n "$_rootdisk" ] && _dev="${_rootdisk}${_dev#mmcblk[0-9]}" ;;\n'
       '\t\t\t\t\tesac\n'
       '\t\t\t\t\tln -s "/dev/${_dev}" "/dev/by-name/${part%@*}"\n'
       '\t\t\t\t\tparts=${parts#*:}\n'
       '\t\t\tdone\n')
if old not in s:
    raise SystemExit("etc/init.d/boot: the by-name loop is not the shape this patch expects")
open(p, 'w', newline='').write(s.replace(old, new))
print("    /dev/by-name now follows the root disk, not a fixed mmcblk0")
PY

# The hand-off to the spruce payload. The stock one is kept either way, so a card
# can be switched over in place by moving the .orig back.
cp "$R/usr/magicx/bin/runmagicx.sh" "$R/usr/magicx/bin/runmagicx.sh.orig"
if [ "$DIAG" = "1" ]; then
    # Diagnostic: paints the panel at each stage, waits 30 s for the card, writes
    # a log to it, and powers off ten seconds after the hand-off returns.
    install -m 0755 "$D/runmagicx-diag.sh" "$R/usr/magicx/bin/runmagicx.sh"
    install -m 0755 "$FBFILL" "$R/usr/magicx/bin/fbfill"
    log "hand-off: DIAGNOSTIC (DIAG=0 for the stock one)"
else
    install -m 0755 "$OAKMOSS_ROOT/overlay/usr/magicx/bin/runmagicx.sh" "$R/usr/magicx/bin/runmagicx.sh"
    log "hand-off: stock"
fi
# EXPERIMENTS="xu20-egl ..." installs diag/experiments/<name>.sh under
# /usr/magicx/diag/experiments (the diagnostic hand-off runs each once the user
# card is up, output into the boot log) and the EGL test binary they use, built
# from diag/egltest.c with the Arm toolchain (dynamic: it dlopens the base's
# libEGL). Bench work for one board; a normal image carries none.
if [ "$DIAG" = 1 ] && [ -n "${EXPERIMENTS:-}" ]; then
    EGLTEST=$BUILDS_DIR/egltest
    if [ ! -x "$EGLTEST" ] || [ "$D/egltest.c" -nt "$EGLTEST" ]; then
        CC=$ARMGNU_DIR/bin/aarch64-none-linux-gnu-gcc
        [ -x "$CC" ] || { echo "need the Arm toolchain to build egltest" >&2; exit 1; }
        "$CC" -O -o "$EGLTEST" "$D/egltest.c" -ldl || exit 1
    fi
    mkdir -p "$R/usr/magicx/diag/experiments"
    install -m 0755 "$EGLTEST" "$R/usr/magicx/diag/egltest"
    for x in $EXPERIMENTS; do
        [ -f "$D/experiments/$x.sh" ] || { echo "no such experiment: $x" >&2; exit 1; }
        install -m 0755 "$D/experiments/$x.sh" "$R/usr/magicx/diag/experiments/$x.sh"; echo "    experiment installed: $x"
    done
fi
# EARLY_PROBE=1 (default while DIAG=1): the kernel's init= is /sbin/init-probe,
# which paints the panel magenta the moment the kernel executes it, writes
# dmesg/cmdline/block devices to the user card (FAT, readable on a PC) and to
# this card's UDISK, then execs /sbin/init. A shipped card never carries it.
INIT=/sbin/init
if [ "$DIAG" = 1 ] && [ "${EARLY_PROBE:-1}" = 1 ]; then
    install -m 0755 "$D/init-probe.sh" "$R/sbin/init-probe"; INIT=/sbin/init-probe
    echo "    early probe: init=/sbin/init-probe (magenta = kernel ran our init; log on the user card)"
fi
# ext4 root (the stock kernel has no squashfs), with static /dev/console and /dev/null.
# Feature set as the vendor's own ext4 images carry (uninit_bg, no 64bit, no
# metadata_csum): what that 4.9 kernel is known to mount. The container's
# e2fsprogs (1.44) is older than the host's, so the list names nothing newer.
EXT4_FEATURES='has_journal,ext_attr,resize_inode,dir_index,filetype,extent,flex_bg,sparse_super,large_file,huge_file,uninit_bg,dir_nlink,extra_isize,^64bit,^metadata_csum'
# The root filesystem is made INSIDE the build container, as root: that is the
# only way its files end up root-owned (an unprivileged unsquashfs leaves them
# the build user's) and its device nodes exist; ownership of the work tree comes
# back to the host user afterwards so the cleanup can remove it.
HOST_UG=$(id -u):$(id -g); export EXT4_FEATURES HOST_UG
if ! docker run --rm --user 0 -v "$W/root:/r" -v "$W:/w" -e EXT4_FEATURES -e HOST_UG "$DOCKER_IMAGE" sh -c '
        set -e
        mkdir -p /r/dev && mknod -m 600 /r/dev/console c 5 1 && mknod -m 666 /r/dev/null c 1 3 && chown -R 0:0 /r
        mke2fs -q -t ext4 -O "$EXT4_FEATURES" -d /r -L rootfs -m 0 /w/rootfs.ext4 512M
        mke2fs -q -t ext4 -O "$EXT4_FEATURES" -L rootfs_data -m 0 /w/rootfs_data.ext4 64M
        mke2fs -q -t ext4 -O "$EXT4_FEATURES" -L UDISK -m 0 /w/udisk.ext4 16M
        chown -R "$HOST_UG" /r /w/rootfs.ext4 /w/rootfs_data.ext4 /w/udisk.ext4' 2>"$W/mke2fs.err"; then
    cat "$W/mke2fs.err" >&2; echo "the build container could not make the root filesystem (is the $DOCKER_IMAGE image present?)" >&2; exit 1
fi
[ -s "$W/rootfs.ext4" ] && [ -s "$W/rootfs_data.ext4" ] && [ -s "$W/udisk.ext4" ] || { echo "ext4 images missing after the container ran" >&2; exit 1; }
echo "    ext4 (in the container, root-owned): $(dumpe2fs -h "$W/rootfs.ext4" 2>/dev/null | grep -m1 'features' | cut -d: -f2 | xargs)"

log "env: stock variables, root and init pointed at our rootfs"
# root= is given as PARTUUID, not /dev/mmcblkNpM. The mmc block index is handed out
# in host probe order (drivers/mmc/core/host.c), not by device-tree alias, and which
# SD controller this board probes first is exactly the thing we cannot check without
# the unit in hand. PARTUUID is resolved by scanning every block device for a GPT
# entry with that unique GUID (init/do_mounts.c devt_from_partuuid), so it is right
# whichever slot the card is in and whatever index it lands on. The stock kernel has
# CONFIG_EFI_PARTITION=y, so the table is parsed, and 4.9 implements PARTUUID= (but
# NOT PARTLABEL=, which is why the label is not used here).
ROOT_UUID=$(python3 -c 'import uuid; print(uuid.uuid4())')
printf '%s' "$ROOT_UUID" > "$W/rootfs.uuid"
python3 - "$ENVSTOCK" "$W/env.txt" "$ROOT_UUID" "$INIT" <<'PY'
import sys
d=open(sys.argv[1],'rb').read()[4:]
root_uuid=sys.argv[3]
kv=dict(v.decode().split('=',1) for v in d.split(b'\0') if v)
kv['nand_root']=kv['mmc_root']='PARTUUID='+root_uuid
kv['init']=sys.argv[4] if len(sys.argv) > 4 and sys.argv[4] else '/sbin/init'; kv['loglevel']='7'
kv['partitions']='bootloader@mmcblk0p1:env@mmcblk0p2:boot@mmcblk0p3:misc@mmcblk0p4:dtbo@mmcblk0p5:rootfs@mmcblk0p6:rootfs_data@mmcblk0p7:UDISK@mmcblk0p8:vbmeta@mmcblk0p9:vbmeta_system@mmcblk0p10:vbmeta_vendor@mmcblk0p11'
# rdinit=/nonexistent: the stock ramdisk's /init is skipped, the kernel mounts root= and runs init=
extra=' rdinit=/nonexistent rootwait rootfstype=ext4 partitions=${partitions} cma=${cma}'
# root= is written out LITERALLY, not as ${mmc_root}: the stock U-Boot recomputes
# mmc_root at boot as /dev/mmcblk0p<index of the partition named rootfs> (its
# binary carries the "mmcblk0p%d" format and "update bootcmd"), which is right
# only while the boot card is the first block device. With the second slot
# enabled that is a race, and a lost race is root= naming the other card's
# sixth partition and rootwait waiting for it forever behind the boot logo
# (XU20, 2026-09-16 13:00: two-slot image stuck on the logo, one-slot fine).
# root= goes through ${mmc_root} (mmc_root=PARTUUID=... above). The stock U-Boot
# may rewrite mmc_root as /dev/mmcblk0p<index of rootfs> at boot ("set root to
# %s" in its binary); the image that booted with two cards (Zero 40 1240) used
# this form, the one with the PARTUUID written literally (1308) stopped behind
# the logo with two cards and booted with one - so this form stays.
kv['setargs_nand']='setenv bootargs earlyprintk=${earlyprintk} initcall_debug=${initcall_debug} console=${console} loglevel=${loglevel} root=${nand_root} init=${init}'+extra
kv['setargs_mmc']='setenv bootargs earlyprintk=${earlyprintk} initcall_debug=${initcall_debug} console=${console} loglevel=${loglevel} root=${mmc_root} init=${init}'+extra
kv['bootcmd']='run setargs_mmc boot_normal'
# Standing guard against the 0100-class failure. init/main.c's kernel_init() runs
# execute_command and PANICS with no fallback if it cannot be executed; the stock
# Android value is /init, which our rootfs does not have (it has /sbin/init). The
# panic only reaches the UART, never the panel, so it looks like a dead device.
assert kv['init'] in ('/sbin/init', '/sbin/init-probe'), f"init must be /sbin/init (or the early probe), not {kv['init']!r}"
assert kv['mmc_root'].startswith('PARTUUID='), 'root must be given as PARTUUID'
assert 'root=${mmc_root}' in kv['setargs_mmc'] and 'init=${init}' in kv['setargs_mmc']
open(sys.argv[2],'w').write(''.join(f'{k}={v}\n' for k,v in kv.items()))
PY
"$MKENVIMAGE" -s 131072 -p 0x00 -o "$W/env.fex" "$W/env.txt"

log "boot.img: the stock one (kernel + Android ramdisk + DTB)"
cp "$BOOTIMG" "$W/boot.img"
cp "$BOOTPKG" "$W/boot_package.fex"
python3 - "$W/boot.img" "$W/boot_package.fex" "$W/dtb-offsets" <<'PY'
import struct,sys
img,pkg,out=sys.argv[1:4]
b=open(img,'rb').read()
ps=struct.unpack_from('<I',b,36)[0]
ks,rs,ss=struct.unpack_from('<I',b,8)[0],struct.unpack_from('<I',b,16)[0],struct.unpack_from('<I',b,24)[0]
rdsz,dtbsz=struct.unpack_from('<I',b,1632)[0],struct.unpack_from('<I',b,1648)[0]
pg=lambda n:(n+ps-1)//ps*ps
img_dtb=ps+pg(ks)+pg(rs)+pg(ss)+pg(rdsz)
# the boot package records its own contents, so find its tree by its magic
p=open(pkg,'rb').read(); i, pkg_dtb = 0, None
while True:
    i=p.find(b'\xd0\x0d\xfe\xed', i)
    if i<0: break
    if struct.unpack_from('>I',p,i+4)[0]==dtbsz: pkg_dtb=i; break
    i+=4
assert pkg_dtb is not None, "no device tree of the boot image's size inside the boot package"
assert b[img_dtb:img_dtb+dtbsz]==p[pkg_dtb:pkg_dtb+dtbsz], \
    "the boot image and the boot package carry DIFFERENT device trees; patch the one U-Boot passes"
open(out,'w').write(f"{img_dtb} {pkg_dtb}\n")
print(f"    kernel {ks} B, ramdisk {rs} B, dtb {dtbsz} B (identical in the boot image and the boot package)")
print(f"    header cmdline: {b[64:576].split(b'\0')[0].decode()}")
PY
read -r IMG_DTB PKG_DTB < "$W/dtb-offsets"

if [ "$SECOND_SLOT" = "1" ]; then
    echo "--- device tree: enable the other SD controllers so both cards are visible"
    # The stock tree enables sdc0 (a TF slot with card detect on PF6) and sdc1
    # (SDIO, the radio), and leaves sdc2 and sdc3 disabled. U-Boot enables only
    # the controller it booted from (board_helper.c, "fix nand&sdmmc"), and the
    # three device-tree overlays in the dtbo partition are empty stubs that
    # enable nothing, so Linux sees exactly one card. spruce needs two: the base
    # on this card and its payload on the other.
    #
    # Enabling them is safe on this board: every function whose pins overlap is
    # disabled in the stock tree (uart5, uart6, twi4, twi5, spi0, nand0) and no
    # node claims a PC or PI pin as a GPIO, so nothing else wants them.
    #
    # Both copies of the tree are patched. They are byte-identical, and which one
    # U-Boot hands the kernel depends on build options we cannot read off the
    # device (common/bootm.c sets images.ft_addr from gd->fdt_blob, which
    # use_android_image_dtb may have pointed at the boot image's copy), so
    # patching both removes the question.
    "$OAKMOSS_ROOT/scripts/fdt-enable-nodes.py" "$W/boot.img"          "$IMG_DTB" sdmmc@04022000 sdmmc@04023000
    "$OAKMOSS_ROOT/scripts/fdt-enable-nodes.py" "$W/boot_package.fex"  "$PKG_DTB" sdmmc@04022000 sdmmc@04023000
    # boot0 checksums the whole package before it runs U-Boot (toc1 add_sum);
    # the patch above changed bytes inside it, so the header must be redone or
    # the device never leaves boot0 - no logo, no LED (2026-09-16, both boards).
    python3 "$OAKMOSS_ROOT/scripts/toc1-checksum.py" --fix "$W/boot_package.fex"
else
    echo "--- device tree: stock (system card on sdc2, enabled by U-Boot at boot; user card on sdc0, already okay)"
fi

log "image: GPT (entries at LBA 2048, as the Tina images), card boot0 @16, boot package @32800"
IMG=$OUT/oakmoss-$OUTNAME-$ST-sd1.img
python3 - "$IMG" "$W" "$BOOT0" "$W/boot_package.fex" "$BOOTRES" "$DTBO" "$VBMETA" "$VBMETA_SYS" "$VBMETA_VEN" <<'PY'
import struct,sys,uuid,zlib,os
img,W,boot0,bootpkg,bootres,dtbo,vbmeta,vbmeta_sys,vbmeta_ven=sys.argv[1:10]
# the rootfs entry must carry the exact GUID the env's root=PARTUUID names
ROOT_UUID=uuid.UUID(open(f'{W}/rootfs.uuid').read().strip())
S=512
parts=[('bootloader',65536,bootres),('env',32768,f'{W}/env.fex'),('boot',65536,f'{W}/boot.img'),('misc',32768,None),
       ('dtbo',4096,dtbo),('rootfs',1048576,f'{W}/rootfs.ext4'),('rootfs_data',131072,f'{W}/rootfs_data.ext4'),('UDISK',32768,f'{W}/udisk.ext4'),
       ('vbmeta',32768,vbmeta),('vbmeta_system',32768,vbmeta_sys),('vbmeta_vendor',32768,vbmeta_ven)]
start=40960; ents=[]
for name,size,src in parts: ents.append((name,start,size,src)); start+=size
last_part_end=start; total=last_part_end+2048+34   # room for the backup GPT
f=open(img,'wb'); f.truncate(total*S)
def wr(lba,path):
    if not path: return
    d=open(path,'rb').read(); f.seek(lba*S); f.write(d); return len(d)
wr(16,boot0); wr(32800,bootpkg)
# A second boot0 at sector 256 (128 KiB). Sectors 2..33 are where every PC tool
# lays a "standard" GPT entry array, and sector 16 is inside that range: a
# Windows or DiskGenius table rewrite zeroes boot0 while leaving everything
# else intact (2026-09-16: three "no LED" cards, sector 16 zeroed, 32800 fine).
# The sun50i boot ROMs try 8 KiB and then 128 KiB, and 256..383 is free here.
wr(256,boot0)
for name,st,size,src in ents:
    if src:
        n=os.path.getsize(src); assert n<=size*S, f"{name}: {n} > {size*S}"
        wr(st,src)
# GPT
linux=uuid.UUID('0FC63DAF-8483-4772-8E79-3D69D8477DE4').bytes_le; attr=0x8000200000000000
entry=b''
for name,st,size,src in ents:
    part_uuid = ROOT_UUID if name=='rootfs' else uuid.uuid4()
    entry+=linux+part_uuid.bytes_le+struct.pack('<QQQ',st,st+size-1,attr)+name.encode('utf-16-le').ljust(72,b'\0')
entry=entry.ljust(128*128,b'\0')
disk=uuid.uuid4().bytes_le; last=total-1; ent_lba=2048; bk_ent=last-32
def header(cur,bak,ent):
    h=bytearray(92); h[0:8]=b'EFI PART'; struct.pack_into('<IIII',h,8,0x10000,92,0,0)
    struct.pack_into('<QQQQ',h,24,cur,bak,34880,bk_ent-1); h[56:72]=disk; struct.pack_into('<QIII',h,72,ent,128,128,zlib.crc32(entry)&0xffffffff)
    struct.pack_into('<I',h,16,zlib.crc32(bytes(h))&0xffffffff); return bytes(h).ljust(S,b'\0')
pmbr=bytearray(S); pmbr[446:462]=bytes([0,0,2,0,0xee,0xff,0xff,0xff])+struct.pack('<II',1,min(last,0xffffffff)); pmbr[510:512]=b'\x55\xaa'
f.seek(0); f.write(pmbr); f.seek(S); f.write(header(1,last,ent_lba)); f.seek(ent_lba*S); f.write(entry)
f.seek(bk_ent*S); f.write(entry); f.seek(last*S); f.write(header(last,1,bk_ent)); f.close()
print(f"    {img}: {total*S/1e6:.0f} MB, {len(ents)} partitions, rootfs = p6")
PY
flush_file "$IMG"   # never a bare sync: see lib.sh
# Sector 0 must be a standard protective MBR ahead of the GPT: signature 0x55AA and
# a type-0xEE record starting at LBA 1. That is what the vendor's own XU20 layout
# uses (its GPT item carries exactly this), and what U-Boot's and the kernel's
# is_pmbr_valid() require before they will read the table at LBA 1. The
# Allwinner "softw411" table the PhoenixSuit image also ships is for the flasher
# and NAND targets; no card carries it as a partition table.
python3 - "$IMG" <<'PY'
import struct, sys
b = open(sys.argv[1], 'rb').read(1024)
ok = b[510:512] == b'\x55\xaa' and any(b[446+i*16+4] == 0xEE and struct.unpack_from('<I', b, 446+i*16+8)[0] == 1 for i in range(4)) and b[512:520] == b'EFI PART'
raise SystemExit(0 if ok else "sector 0 is not a protective MBR ahead of a GPT header")
PY
log "verify"
sfdisk -d "$IMG" 2>/dev/null | grep -E 'name=' | sed 's/^[^:]*: //' | cut -c1-100 >&2
[ "$(dd if="$IMG" bs=512 skip=16 count=1 status=none | head -c 8 | tail -c 4)" = "eGON" ] || die "no boot0 at sector 16"
[ "$(dd if="$IMG" bs=512 skip=256 count=1 status=none | head -c 8 | tail -c 4)" = "eGON" ] || die "no boot0 mirror at sector 256"
[ "$(dd if="$IMG" bs=512 skip=32800 count=1 status=none | head -c 13)" = "sunxi-package" ] || die "no boot package at sector 32800"
python3 "$OAKMOSS_ROOT/scripts/toc1-checksum.py" --check "$IMG" 32800 || die "the boot package in the image would be refused by boot0"
[ "$(dd if="$IMG" bs=512 skip=$((40960+65536+32768)) count=1 status=none | head -c 8)" = "ANDROID!" ] || die "boot partition is not an Android boot image"
{
  echo "device=$BOARD"; echo "kind=stock-chain"; echo "built=$ST"; echo "oakmoss=$(oakmoss_version)"
  echo "boot_chain=$CHAIN: card boot0 (12345678_1234567890BOOT_0 = boot0_sdcard), boot package (u-boot+dtb), boot-resource, dtbo, vbmeta x3, stock boot.img (kernel 4.9.170 + Android ramdisk, skipped with rdinit=/nonexistent)$([ "$SECOND_SLOT" = 1 ] && echo '; device tree: sdc2 + sdc3 enabled in both copies' || echo '; device tree: stock')"
  echo "boot_chain_sha256=$CHAIN_SHA"
  echo "rootfs=our Zero 40 rootfs from $BUILD as ext4 (marker $BOARD, vendor modules for 4.9.170, radio $RADIO, PowerVR 1.11 userland, /dev/by-name follows the root disk)"
  echo "rootfs_md5=$(md5_of "$ROOTFS")"
  echo "handoff=$([ "$DIAG" = 1 ] && echo 'DIAGNOSTIC: powers off 10 s after the hand-off returns' || echo 'stock')"
  echo "layout=bootloader env boot misc dtbo rootfs(p6) rootfs_data UDISK vbmeta vbmeta_system vbmeta_vendor; GPT entries at LBA 2048; root=PARTUUID"
  echo "env=$(tr '\n' ';' < "$W/env.txt" | cut -c1-400)"
  echo "outputs=$(basename "$IMG") (raw GPT image: dd or Etcher, whole card; goes in the slot the stock system card came from)"
} > "$OUT/BUILD-INFO.txt"
cp "$W/env.txt" "$OUT/env.txt"
[ "${COMPRESS:-0}" = 1 ] && xz -T0 -6 -k "$IMG"
log "$BOARD stock-chain image ready: $OUT"; ls -la "$OUT" >&2
