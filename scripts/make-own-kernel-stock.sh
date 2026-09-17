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
BOOTPKG=$(f '12345678_BOOTPKG-00000000'); BOOTRES=$(f 'RFSFAT16_BOOT-RESOURCE_FE'); BOOTIMG=$(f 'RFSFAT16_BOOT_FEX00000000')
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
python3 - "$ENVSTOCK" "$W/env.txt" "$ROOT_UUID" "$INIT" <<'PY'
import sys
d = open(sys.argv[1], 'rb').read()[4:]; root_uuid, init = sys.argv[3], sys.argv[4]
kv = dict(v.decode().split('=', 1) for v in d.split(b'\0') if v)
kv['nand_root'] = kv['mmc_root'] = 'PARTUUID=' + root_uuid
kv['init'] = init; kv['loglevel'] = '7'
kv['partitions'] = 'bootloader@mmcblk0p1:env@mmcblk0p2:boot@mmcblk0p3:misc@mmcblk0p4:dtbo@mmcblk0p5:rootfs@mmcblk0p6:rootfs_data@mmcblk0p7:UDISK@mmcblk0p8:vbmeta@mmcblk0p9:vbmeta_system@mmcblk0p10:vbmeta_vendor@mmcblk0p11'
extra = ' rootwait rootfstype=squashfs partitions=${partitions} cma=${cma}'
kv['setargs_nand'] = 'setenv bootargs earlyprintk=${earlyprintk} initcall_debug=${initcall_debug} console=${console} loglevel=${loglevel} root=${nand_root} init=${init}' + extra
kv['setargs_mmc'] = 'setenv bootargs earlyprintk=${earlyprintk} initcall_debug=${initcall_debug} console=${console} loglevel=${loglevel} root=${mmc_root} init=${init}' + extra
kv['bootcmd'] = 'run setargs_mmc boot_normal'
assert kv['init'] in ('/sbin/init', '/sbin/init-probe') and 'rdinit' not in kv['setargs_mmc']
open(sys.argv[2], 'w').write(''.join(f'{k}={v}\n' for k, v in kv.items()))
PY
"$MKENVIMAGE" -s 131072 -p 0x00 -o "$W/env.fex" "$W/env.txt"

log "image: GPT (entries at LBA 2048), stock boot0 @16 and @256, our tree in the stock package @32800"
IMG=$OUT/oakmoss-$BOARD-own-$ST-sd1.img
python3 - "$IMG" "$W" "$BOOT0" "$W/boot_package.fex" "$BOOTRES" "$DTBO" "$VBMETA" "$VBMETA_SYS" "$VBMETA_VEN" <<'PY'
import struct, sys, uuid, zlib, os
img, W, boot0, bootpkg, bootres, dtbo, vbmeta, vbmeta_sys, vbmeta_ven = sys.argv[1:10]
ROOT_UUID = uuid.UUID(open(f'{W}/rootfs.uuid').read().strip()); S = 512
parts = [('bootloader', 65536, bootres), ('env', 32768, f'{W}/env.fex'), ('boot', 65536, f'{W}/boot.img'), ('misc', 32768, None),
         ('dtbo', 4096, dtbo), ('rootfs', 1048576, f'{W}/rootfs.fex'), ('rootfs_data', 131072, f'{W}/rootfs_data.ext4'), ('UDISK', 32768, f'{W}/udisk.ext4'),
         ('vbmeta', 32768, vbmeta), ('vbmeta_system', 32768, vbmeta_sys), ('vbmeta_vendor', 32768, vbmeta_ven)]
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
    pu = ROOT_UUID if name == 'rootfs' else uuid.uuid4()
    entry += linux + pu.bytes_le + struct.pack('<QQQ', st, st + size - 1, attr) + name.encode('utf-16-le').ljust(72, b'\0')
entry = entry.ljust(128 * 128, b'\0'); disk = uuid.uuid4().bytes_le; last = total - 1; ent_lba = 2048; bk_ent = last - 32
def header(cur, bak, ent):
    h = bytearray(92); h[0:8] = b'EFI PART'; struct.pack_into('<IIII', h, 8, 0x10000, 92, 0, 0)
    struct.pack_into('<QQQQ', h, 24, cur, bak, 34880, bk_ent - 1); h[56:72] = disk; struct.pack_into('<QIII', h, 72, ent, 128, 128, zlib.crc32(entry) & 0xffffffff)
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
  echo "layout=bootloader env boot misc dtbo rootfs(p6, squashfs) rootfs_data UDISK vbmeta vbmeta_system vbmeta_vendor; GPT entries at LBA 2048; root=PARTUUID via mmc_root"
  e=$(tr '\n' ';' < "$W/env.txt")
  if [ ${#e} -gt 400 ]; then e="${e:0:400}...[truncated]"; fi
  echo "env=$e"
  echo "outputs=$(basename "$IMG") (raw GPT image: write raw, eject, boot; system card in the sdc2 slot, user card in the sdc0 slot)"
} > "$OUT/BUILD-INFO.txt"
cp "$W/env.txt" "$OUT/env.txt"; ( cd "$OUT" && md5sum ./*.img > md5sums.txt )
log "$BOARD own-kernel image ready: $OUT"; ls -la "$OUT" >&2
