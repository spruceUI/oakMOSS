#!/usr/bin/env python3
"""Cut an oakMOSS update (.omupd) out of a finished SD1 image.

    make-update.py [--bootchain] [--own] <sd1.img> <board> <version> <out.omupd> [<build>]

The update carries the kernel slot (boot), the root filesystem slot (rootfs)
and the boot-resource partition, with --bootchain also boot0 and the U-Boot
package (BOOTCHAIN=1), each with the sha256 of the bytes that go on the card. The device installs it with
/usr/magicx/bin/oakmoss-update.sh (docs/updates.md). <build> is the commit time
(build.sh), which the device compares with /usr/magicx/build to install only newer updates.
--own cuts it from an own-lane image (make-own-kernel-stock.sh): LANE=own, and no
boot-resource, which is the board's stock one there (vendor data, never in an update).

Format: a 4 KiB text manifest (KEY=VALUE lines, NUL padded), then each part
at a 4 KiB-aligned offset. boot and bootres are gzipped whole partitions; the
others are stored as they are.
"""
import gzip
import hashlib
import struct
import sys

SECTOR = 512
ALIGN = 4096
BOOT0_SECTOR = 16
PACKAGE_SECTOR = 32800


def gpt_partitions(img):
    img.seek(SECTOR)
    hdr = img.read(92)
    if hdr[:8] != b'EFI PART':
        sys.exit('no GPT header at LBA 1')
    entries_lba, count, size = struct.unpack_from('<QII', hdr, 72)
    first_usable = struct.unpack_from('<Q', hdr, 40)[0]
    parts = {}
    img.seek(entries_lba * SECTOR)
    for _ in range(count):
        e = img.read(size)
        start, end = struct.unpack_from('<QQ', e, 32)
        name = e[56:128].decode('utf-16-le').rstrip('\0')
        if name:
            parts[name] = (start, end - start + 1)
    return parts, first_usable


def check_bootres(fat):
    """The boot-resource FAT must be a FAT16 of exactly its partition, without the SDK logo's backup
    (up to v0.6.0-beta.1 it claimed 8 MiB of a 4 MiB partition and carried bootlogo.bmp.orig)."""
    bps, spc, rsv, nfats, roots, tot16, _, spf = struct.unpack_from('<HBHBHHBH', fat, 11)
    tot = tot16 or struct.unpack_from('<I', fat, 32)[0]
    if bps != SECTOR or tot * bps != len(fat):
        sys.exit(f'boot-resource FAT says {tot * bps} bytes, its partition is {len(fat)}')
    clusters = (tot - rsv - nfats * spf - roots * 32 // bps) // spc
    if not 4085 <= clusters <= 65524:
        sys.exit(f'boot-resource FAT has {clusters} clusters: not a FAT16, whatever its label says')
    if fat[54:62] != b'FAT16   ':
        sys.exit('boot-resource FAT is not labelled FAT16: U-Boot goes by the label, Linux by the count')
    root = fat[(rsv + nfats * spf) * bps:][:roots * 32]
    for i in range(0, len(root), 32):
        e = root[i:i + 32]
        if e[0] == 0:
            break
        if e[0] != 0xE5 and e[11] != 0x0F and e[8:11] == b'ORI':
            sys.exit('boot-resource carries a .orig file (the SDK logo is not ours to ship)')


def read_at(img, sector, length):
    img.seek(sector * SECTOR)
    data = img.read(length)
    if len(data) != length:
        sys.exit(f'image too short at sector {sector}')
    return data


def main():
    args = sys.argv[1:]
    bootchain = '--bootchain' in args
    own = '--own' in args
    args = [a for a in args if a not in ('--bootchain', '--own')]
    if len(args) not in (4, 5):
        sys.exit(__doc__)
    path, board, version, out = args[:4]
    build = args[4] if len(args) == 5 else '0'
    if not build.isdigit():
        sys.exit(f'build must be a number, not {build!r}')
    with open(path, 'rb') as img:
        parts, first_usable = gpt_partitions(img)
        for need in ('boot', 'rootfs') + (() if own else ('bootloader',)):
            if need not in parts:
                sys.exit(f'no "{need}" partition in {path}')

        def whole(name):
            start, sectors = parts[name]
            return read_at(img, start, sectors * SECTOR)

        boot = whole('boot')
        # An own-lane update carries no boot-resource (the card keeps the board's stock one); the SDK
        # lane's is ours, and must be the FAT16 the bundle round lays out.
        bootres = None if own else whole('bootloader')
        if not own:
            check_bootres(bootres)

        start, sectors = parts['rootfs']
        sb = read_at(img, start, 96)
        if sb[:4] != b'hsqs':
            sys.exit('rootfs partition does not start with a squashfs superblock')
        used = struct.unpack_from('<Q', sb, 40)[0]
        used = (used + ALIGN - 1) // ALIGN * ALIGN
        if used > sectors * SECTOR:
            sys.exit('squashfs is larger than its partition')
        rootfs = read_at(img, start, used)

        head = read_at(img, BOOT0_SECTOR, 32)
        if head[4:12] != b'eGON.BT0':
            sys.exit(f'no boot0 at sector {BOOT0_SECTOR}')
        boot0 = read_at(img, BOOT0_SECTOR, struct.unpack_from('<I', head, 16)[0])

        head = read_at(img, PACKAGE_SECTOR, 64)
        if not head.startswith(b'sunxi-package'):
            sys.exit(f'no U-Boot package at sector {PACKAGE_SECTOR}')
        package = read_at(img, PACKAGE_SECTOR, struct.unpack_from('<I', head, 36)[0])
        if PACKAGE_SECTOR * SECTOR + len(package) > first_usable * SECTOR:
            sys.exit('U-Boot package runs into the partitions')

    # boot0 and the U-Boot package are shared by both slots: only a --bootchain update carries them.
    items = [('boot', boot, True), ('rootfs', rootfs, False)]
    if bootchain:
        items += [('boot0', boot0, False), ('package', package, False)]
    if not own:
        items.append(('bootres', bootres, True))
    lines = ['FORMAT=omupd1', f'BOARD={board}'] + (['LANE=own'] if own else []) + [f'VERSION={version}', f'BUILD={build}',
             f'BOOTCHAIN={int(bootchain)}', 'PARTS=' + ' '.join(n for n, _, _ in items)]
    blobs = []
    offset = ALIGN
    for name, data, gz in items:
        stored = gzip.compress(data, 9, mtime=0) if gz else data
        lines += [f'{name}_OFFSET={offset}', f'{name}_LENGTH={len(stored)}',
                  f'{name}_GZIP={int(gz)}', f'{name}_SIZE={len(data)}',
                  f'{name}_SHA256={hashlib.sha256(data).hexdigest()}']
        blobs.append((offset, stored))
        offset += (len(stored) + ALIGN - 1) // ALIGN * ALIGN
    manifest = ('\n'.join(lines) + '\n').encode()
    if len(manifest) > ALIGN:
        sys.exit('manifest larger than its 4 KiB block')

    with open(out, 'wb') as f:
        f.write(manifest.ljust(ALIGN, b'\0'))
        for off, stored in blobs:
            f.seek(off)
            f.write(stored)
        f.truncate((offset + ALIGN - 1) // ALIGN * ALIGN)
    print(out)


if __name__ == '__main__':
    main()
