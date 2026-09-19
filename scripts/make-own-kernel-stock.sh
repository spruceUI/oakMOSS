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
#   scripts/make-own-kernel-stock.sh <board> <build dir> [out dir]     board: xu20 | zero40
#
# Why not the Android kernel (scripts/make-hybrid-stock.sh): its 1.11 GPU driver
# exports no display-class API, so no Linux GPU userland can initialize on it
# (docs/hardware-notes.md, "EGL"). Why not our own boot0/U-Boot: the stock ones
# carry the board's DRAM and panel init and are known to work; ours are the Zero 28's.
#
# Inputs: the board's stock firmware unpacked (unpack-xu20-stock.sh /
# unpack-zero40-stock.sh) and a build of THIS board (boards/<board>/board.dts gives
# it the board's panel, pad, radio and battery; sdk-patches/tree/070-* the panel
# drivers). DIAG=1 (default) installs the diagnostic hand-off and, with
# EARLY_PROBE=1, the init= probe; EXPERIMENTS="..." adds diag/experiments.
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
BOARD=${1:?board: xu20 | zero40}; shift || true
case "$BOARD" in
    xu20)   STOCK_DIR=$XU20_STOCK_DIR;   DUMP=$STOCK_DIR/$XU20_STOCK_IMG.dump;   CHAIN_SHA=$XU20_STOCK_IMG_SHA256;   UNPACKER=unpack-xu20-stock.sh
            CHAIN="XU20 V32 stock firmware (github.com/Magicx-Breeze/XU20_V32, Developers release)" ;;
    zero40) STOCK_DIR=$ZERO40_STOCK_DIR; DUMP=$STOCK_DIR/$ZERO40_STOCK_IMG.dump; CHAIN_SHA=$ZERO40_STOCK_IMG_SHA256; UNPACKER=unpack-zero40-stock.sh
            CHAIN="Zero 40 stock firmware (github.com/Magicx-Breeze/Zero40, release Zero40_V1, adb.img)" ;;
    *) die "unknown board $BOARD (xu20 | zero40)" ;;
esac
BUILD=${1:?build directory (builds/<stamp>-$BOARD)}; shift || true
ST=$(stamp); OUT=${1:-$BUILDS_DIR/$ST-$BOARD-own}
DIAG=${DIAG:-1}; EARLY_PROBE=${EARLY_PROBE:-1}; EXPERIMENTS=${EXPERIMENTS:-}
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
MKE2FS=$(command -v mke2fs || true); [ -n "$MKE2FS" ] || die "need mke2fs (e2fsprogs)"
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
if [ -n "${BOOTRES:-}" ]; then [ -f "$BOOTRES" ] || die "BOOTRES=$BOOTRES: no such file"; log "boot-resource: $BOOTRES (board-sized bootloader screens)"; else BOOTRES=$(f 'RFSFAT16_BOOT-RESOURCE_FE'); fi
DTBO=$(f 'RFSFAT16_DTBO_FEX00000000'); ENVSTOCK=$(f 'RFSFAT16_ENV_FEX000000000')
VBMETA=$(f 'RFSFAT16_VBMETA_FEX000000'); VBMETA_SYS=$(f 'RFSFAT16_VBMETA_SYSTEM_FE'); VBMETA_VEN=$(f 'RFSFAT16_VBMETA_VENDOR_FE')
[ "$(head -c 8 "$BOOT0" | tail -c 4)" = "eGON" ] || die "boot0 magic missing"
[ "$(basename "$BOOT0")" = "12345678_1234567890BOOT_0" ] || die "wrong boot0 item: need the card one"
if [ -f "$BOOT0_NAND" ] && cmp -s "$BOOT0" "$BOOT0_NAND"; then die "boot0 sanity check failed: the card and NAND boot0 items are identical"; fi
mkdir -p "$OUT"
need_tmp_space 2048
W=$(mktemp -d "${TMPDIR:-/tmp}/oakmoss-own.XXXX"); trap 'rm -rf "$W"' EXIT

log "rootfs: our $BOARD squashfs, hand-off and probe added"
"$UNSQUASHFS" -n -d "$W/root" "$ROOTFS" >/dev/null 2>"$W/unsq.err" || true
[ -f "$W/root/usr/magicx/bin/runmagicx.sh" ] || { echo "unsquash failed"; head -3 "$W/unsq.err"; exit 1; }
R=$W/root
[ "$(tr -d '\r\n' < "$R/usr/magicx/device")" = "$BOARD" ] || die "rootfs marker is not $BOARD"
echo "    modules: $(ls "$R"/lib/modules/*/ | wc -l) ($(ls "$R"/lib/modules/)), PVR userland: $(strings "$R/usr/lib/libGLESv2.so" | grep -m1 -oE '[0-9]+\.[0-9]+@[0-9]+')"
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
"$MKE2FS" -q -t ext4 -O "$EXT4_FEATURES" -L rootfs_data -m 0 "$W/rootfs_data.ext4" 64M
"$MKE2FS" -q -t ext4 -O "$EXT4_FEATURES" -L UDISK -m 0 "$W/udisk.ext4" 16M

log "device tree: ours, into the stock boot package and into the boot image"
python3 "$OAKMOSS_ROOT/scripts/toc1-item.py" --extract "$OURPKG" dtb "$W/our.dtb"
cp "$BOOTPKG" "$W/boot_package.fex"
python3 "$OAKMOSS_ROOT/scripts/toc1-item.py" --replace "$W/boot_package.fex" dtb "$W/our.dtb"
python3 "$OAKMOSS_ROOT/scripts/toc1-checksum.py" --fix "$W/boot_package.fex"
# boot image: the stock header (addresses, page size, its command line) with our
# kernel, a placeholder ramdisk (our kernel mounts root= itself), our tree, and no
# header command line of its own.
python3 - "$BOOTIMG" "$OURBOOT" "$W/our.dtb" "$W/boot.img" <<'PY'
import struct, sys, hashlib
stock, ours, dtb, out = sys.argv[1:5]
h = bytearray(open(stock, 'rb').read(2048))
ps = struct.unpack_from('<I', h, 36)[0]; hv = struct.unpack_from('<I', h, 40)[0]
assert h[:8] == b'ANDROID!' and hv == 2, "expected a header v2 stock boot image"
o = open(ours, 'rb').read(); oks, ops = struct.unpack_from('<I', o, 8)[0], struct.unpack_from('<I', o, 36)[0]
kernel = o[ops:ops + oks]
assert kernel[56:60] == b'ARM\x64', "our boot.fex does not carry an arm64 Image"
ramdisk = b'\0' * 12; tree = open(dtb, 'rb').read()
pg = lambda n: (n + ps - 1) // ps * ps
struct.pack_into('<I', h, 8, len(kernel)); struct.pack_into('<I', h, 16, len(ramdisk)); struct.pack_into('<I', h, 24, 0)
struct.pack_into('<I', h, 1632, 0); struct.pack_into('<I', h, 1648, len(tree))
body = kernel.ljust(pg(len(kernel)), b'\0') + ramdisk.ljust(pg(len(ramdisk)), b'\0') + tree.ljust(pg(len(tree)), b'\0')
sha = hashlib.sha1(); 
for part, n in ((kernel, len(kernel)), (ramdisk, len(ramdisk)), (b'', 0)):
    sha.update(part); sha.update(struct.pack('<I', n))
h[576:576 + 20] = sha.digest(); h[596:608] = b'\0' * 12
h[64:576] = b'\0' * 512   # no header command line: no Android firmware paths, no dtbo overlay request; bootargs are ours
open(out, 'wb').write(bytes(h).ljust(ps, b'\0') + body)
print(f"    boot.img: kernel {len(kernel)} B (ours), ramdisk placeholder, dtb {len(tree)} B (ours), header v2, header cmdline blank")
PY

log "env: stock variables, root and init pointed at our rootfs (squashfs, our kernel)"
ROOT_UUID=$(python3 -c 'import uuid; print(uuid.uuid4())'); printf '%s' "$ROOT_UUID" > "$W/rootfs.uuid"
python3 - "$ENVSTOCK" "$W/env.txt" "$ROOT_UUID" "$INIT" "${CONSOLE:-}" "${EXTRA_BOOTARGS:-}" <<'PY'
import os, sys
d = open(sys.argv[1], 'rb').read()[4:]; root_uuid, init, console, extra_args = sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6]
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
assert kv['init'] in ('/sbin/init', '/sbin/init-probe', '/sbin/init-stamp') and 'rdinit' not in kv['setargs_mmc'] and kv['bootcmd'].endswith('run setargs_mmc boot_normal')
open(sys.argv[2], 'w').write(''.join(f'{k}={v}\n' for k, v in kv.items()))
PY
"$MKENVIMAGE" -s 131072 -p 0x00 -o "$W/env.fex" "$W/env.txt"

log "image: GPT layout ${GPT_LAYOUT:-sdk} (sdk: 128 entries @LBA 2048; stock: 16 @LBA 2), stock boot0 @16 and @256, our tree in the stock package @32800"
IMG=$OUT/oakmoss-$BOARD-own-$ST-sd1.img
python3 - "$IMG" "$W" "$BOOT0" "$W/boot_package.fex" "$BOOTRES" "$DTBO" "$VBMETA" "$VBMETA_SYS" "$VBMETA_VEN" "$PSTORE_PARTUUID" "$PSTORE" <<'PY'
import struct, sys, uuid, zlib, os
img, W, boot0, bootpkg, bootres, dtbo, vbmeta, vbmeta_sys, vbmeta_ven, pstore_uuid, pstore = sys.argv[1:12]
ROOT_UUID = uuid.UUID(open(f'{W}/rootfs.uuid').read().strip()); S = 512
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
start = 40960; ents = []
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
    pu = ROOT_UUID if name == 'rootfs' else (uuid.UUID(pstore_uuid) if name == 'pstore' else uuid.uuid4())
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
GPT_LAYOUT = os.environ.get('GPT_LAYOUT', 'sdk')
NENT = 16 if GPT_LAYOUT == 'stock' else 128; assert len(ents) <= NENT
ENT_SECTORS = NENT * 128 // S
# First usable LBA = right after the array, as on MagicX's real cards (Zero 40 stock
# image: 20 entries at LBA 2 -> a 5-sector array, first usable 7). The rewrite sets the
# primary header's entry pointer to first_usable - array sectors while writing the
# array itself at LBA 2 (the old cards: 34880 - 32 = the 34848 read back off a card),
# so the two agree only when first_usable = 2 + array sectors.
FIRST_USABLE = 2 + ENT_SECTORS if GPT_LAYOUT == 'stock' else 34880
entry = entry.ljust(NENT * 128, b'\0'); disk = uuid.uuid4().bytes_le; last = total - 1; ent_lba = 2 if GPT_LAYOUT == 'stock' else 2048; bk_ent = last - ENT_SECTORS
def header(cur, bak, ent):
    h = bytearray(92); h[0:8] = b'EFI PART'; struct.pack_into('<IIII', h, 8, 0x10000, 92, 0, 0)
    struct.pack_into('<QQQQ', h, 24, cur, bak, FIRST_USABLE, bk_ent - 1); h[56:72] = disk; struct.pack_into('<QIII', h, 72, ent, NENT, 128, zlib.crc32(entry) & 0xffffffff)
    struct.pack_into('<I', h, 16, zlib.crc32(bytes(h)) & 0xffffffff); return bytes(h).ljust(S, b'\0')
pmbr = bytearray(S); pmbr[446:462] = bytes([0, 0, 2, 0, 0xee, 0xff, 0xff, 0xff]) + struct.pack('<II', 1, min(last, 0xffffffff)); pmbr[510:512] = b'\x55\xaa'
f.seek(0); f.write(pmbr); f.seek(S); f.write(header(1, last, ent_lba)); f.seek(ent_lba * S); f.write(entry)
f.seek(bk_ent * S); f.write(entry); f.seek(last * S); f.write(header(last, 1, bk_ent)); f.close()
print(f"    {img}: {total*S/1e6:.0f} MB, {len(ents)} partitions, rootfs = p6")
PY
flush_file "$IMG"
log "verify"
[ "$(dd if="$IMG" bs=512 skip=16 count=1 status=none | head -c 8 | tail -c 4)" = "eGON" ] || die "no boot0 at sector 16"
[ "$(dd if="$IMG" bs=512 skip=256 count=1 status=none | head -c 8 | tail -c 4)" = "eGON" ] || die "no boot0 mirror at sector 256"
[ "$(dd if="$IMG" bs=512 skip=32800 count=1 status=none | head -c 13)" = "sunxi-package" ] || die "no boot package at sector 32800"
python3 "$OAKMOSS_ROOT/scripts/toc1-checksum.py" --check "$IMG" 32800 || die "the boot package would be refused by boot0"
[ "$(dd if="$IMG" bs=512 skip=$((40960+65536+32768)) count=1 status=none | head -c 8)" = "ANDROID!" ] || die "boot partition is not an Android boot image"
[ "$(dd if="$IMG" bs=512 skip=241664 count=1 status=none | head -c 4)" = "hsqs" ] || die "rootfs partition is not our squashfs"
{
  echo "device=$BOARD"; echo "kind=own-kernel-stock-chain"; echo "built=$ST"; echo "oakmoss=$(oakmoss_version)"
  echo "boot_chain=$CHAIN: card boot0 (also mirrored at sector 256), boot package with OUR device tree in place of its dtb item (checksum redone), boot-resource, dtbo, vbmeta x3"
  echo "boot_chain_sha256=$CHAIN_SHA"
  echo "kernel=ours from $BUILD ($(grep -m1 '^kernel_encrypt_obj_md5' "$BUILD/BUILD-INFO.txt")), in a header-v2 boot image with our device tree; board_dts=$(grep -m1 '^board_dts' "$BUILD/BUILD-INFO.txt" | cut -d= -f2-)"
  echo "rootfs=our $BOARD rootfs squashfs from $BUILD (md5 $(md5_of "$ROOTFS") before the hand-off/probe repack; our modules, PowerVR 1.19)"
  echo "handoff=$([ "$DIAG" = 1 ] && echo "DIAGNOSTIC (init=$INIT, experiments: ${EXPERIMENTS:-none})" || echo stock)"
  echo "layout=bootloader env boot misc dtbo rootfs(p6, squashfs) rootfs_data UDISK vbmeta vbmeta_system vbmeta_vendor; GPT layout ${GPT_LAYOUT:-sdk}; root=PARTUUID via mmc_root"
  e=$(tr '\n' ';' < "$W/env.txt")
  if [ ${#e} -gt 400 ]; then e="${e:0:400}...[truncated]"; fi
  echo "env=$e"
  echo "outputs=$(basename "$IMG") (raw GPT image: write raw, eject, boot; system card in the sdc2 slot, user card in the sdc0 slot)"
} > "$OUT/BUILD-INFO.txt"
cp "$W/env.txt" "$OUT/env.txt"; ( cd "$OUT" && md5sum ./*.img > md5sums.txt )
log "$BOARD own-kernel image ready: $OUT"; ls -la "$OUT" >&2
