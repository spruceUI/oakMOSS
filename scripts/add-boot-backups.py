#!/usr/bin/env python3
"""Put second copies of boot0 and the U-Boot package into an SD1 image.

    add-boot-backups.py <sd1.img>

boot0 goes to sector 256 beside its copy at 16, the package to sector 24576
beside its copy at 32800. An update writes the second copy first and the
first copy last (oakmoss-update.sh), so an interrupted write leaves one good
copy for the boot ROM and boot0 to fall back to (docs/updates.md).
"""
import struct
import sys

SECTOR = 512
BOOT0, BOOT0_BACKUP = 16, 256
PACKAGE, PACKAGE_BACKUP = 32800, 24576
GPT_ENTRIES = 2048


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    with open(sys.argv[1], 'r+b') as img:
        img.seek(BOOT0 * SECTOR)
        boot0 = img.read(32)
        if boot0[4:12] != b'eGON.BT0':
            sys.exit(f'no boot0 at sector {BOOT0}')
        img.seek(BOOT0 * SECTOR)
        boot0 = img.read(struct.unpack_from('<I', boot0, 16)[0])

        img.seek(PACKAGE * SECTOR)
        package = img.read(64)
        if not package.startswith(b'sunxi-package'):
            sys.exit(f'no U-Boot package at sector {PACKAGE}')
        img.seek(PACKAGE * SECTOR)
        package = img.read(struct.unpack_from('<I', package, 36)[0])

        for data, at, limit in ((boot0, BOOT0_BACKUP, GPT_ENTRIES), (package, PACKAGE_BACKUP, PACKAGE)):
            if at * SECTOR + len(data) > limit * SECTOR:
                sys.exit(f'{len(data)} bytes do not fit at sector {at}')
            img.seek(at * SECTOR)
            there = img.read(len(data))
            if there == data:
                continue
            if any(there):
                sys.exit(f'sector {at} onwards is not empty')
            img.seek(at * SECTOR)
            img.write(data)
    print(f'boot0 copy at {BOOT0_BACKUP}, U-Boot package copy at {PACKAGE_BACKUP}')


if __name__ == '__main__':
    main()
