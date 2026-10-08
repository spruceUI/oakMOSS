#!/usr/bin/env python3
"""Cut an oakMOSS update (.omupd) out of a finished SD1 image.

    make-update.py <sd1.img> <board> <version> <out.omupd> [<build>]

The update carries the kernel slot (boot), the root filesystem slot (rootfs),
boot0, the U-Boot package and the boot-resource partition, each with the
sha256 of the bytes that go on the card. The device installs it with
/usr/magicx/bin/oakmoss-update.sh (docs/updates.md). <build> is the commit time
(build.sh), which the device compares with /usr/magicx/build to install only newer updates.

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


def read_at(img, sector, length):
    img.seek(sector * SECTOR)
    data = img.read(length)
    if len(data) != length:
        sys.exit(f'image too short at sector {sector}')
    return data


def main():
    if len(sys.argv) not in (5, 6):
        sys.exit(__doc__)
    path, board, version, out = sys.argv[1:5]
    build = sys.argv[5] if len(sys.argv) == 6 else '0'
    if not build.isdigit():
        sys.exit(f'build must be a number, not {build!r}')
    with open(path, 'rb') as img:
        parts, first_usable = gpt_partitions(img)
        for need in ('boot', 'rootfs', 'bootloader'):
            if need not in parts:
                sys.exit(f'no "{need}" partition in {path}')

        def whole(name):
            start, sectors = parts[name]
            return read_at(img, start, sectors * SECTOR)

        boot = whole('boot')
        bootres = whole('bootloader')

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

    items = [
        ('boot', boot, True),
        ('rootfs', rootfs, False),
        ('boot0', boot0, False),
        ('package', package, False),
        ('bootres', bootres, True),
    ]
    lines = ['FORMAT=omupd1', f'BOARD={board}', f'VERSION={version}', f'BUILD={build}',
             'PARTS=' + ' '.join(n for n, _, _ in items)]
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
