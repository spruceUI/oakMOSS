#!/usr/bin/env python3
"""Items of an unencrypted Allwinner PhoenixSuit image (IMAGEWTY v1/v3, header layout from
OpenixCard's IMAGEWTY.h), named <maintype>_<subtype> as OpenixCard names them, which is what
scripts/make-own-kernel-stock.sh reads (12345678_1234567890BOOT_0, RFSFAT16_BOOT_FEX00000000...).

  awimg-items.py <image | zip> <out dir> [item ...]

The image may sit inside a zip (TrimUI's releases, LZMA): it is read from the archive, forward
only, with no copy on disk. With item names, only those are written; a name an image holds twice
(the env and env-redund items) is written once, and the script refuses when the copies differ.
items.tsv lists every item (file name, item name, offset, length).
"""
import os
import struct
import sys
import zipfile


def open_image(path):
    if zipfile.is_zipfile(path):
        z = zipfile.ZipFile(path)
        names = [n for n in z.namelist() if n.lower().endswith(('.awimg', '.img'))]
        if len(names) != 1:
            sys.exit(f'{path}: expected one .awimg/.img in the zip, found {names}')
        return z.open(names[0]), f'{path}:{names[0]}'
    return open(path, 'rb'), path


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    f, label = open_image(sys.argv[1])
    out, want = sys.argv[2], set(sys.argv[3:])
    hdr = f.read(1024)
    if hdr[:8] != b'IMAGEWTY':
        sys.exit(f'{label}: not an unencrypted IMAGEWTY image')
    hver = struct.unpack_from('<I', hdr, 8)[0]
    if hver == 0x300:
        nfiles = struct.unpack_from('<I', hdr, 60)[0]
    elif hver == 0x100:
        nfiles = struct.unpack_from('<I', hdr, 56)[0]
    else:
        sys.exit(f'{label}: unknown header version {hver:#x}')
    table = f.read(1024 * nfiles)
    rows = []
    for i in range(nfiles):
        fh = table[i * 1024:(i + 1) * 1024]
        item = (fh[8:16] + b'_' + fh[16:32]).decode('latin-1')
        if hver == 0x300:
            name = fh[36:292].split(b'\0', 1)[0].decode('latin-1')
            _stored, _, length, _, off = struct.unpack_from('<5I', fh, 292)
        else:
            _stored, length, off = struct.unpack_from('<3I', fh, 36)
            name = fh[56:312].split(b'\0', 1)[0].decode('latin-1')
        rows.append((off, length, item, os.path.basename(name.replace('\\', '/'))))
    missing = want - {r[2] for r in rows}
    if missing:
        sys.exit(f'{label}: no item {sorted(missing)}')
    os.makedirs(out, exist_ok=True)
    pos = 1024 + 1024 * nfiles
    done = {}
    for off, length, item, fname in sorted(rows):
        if want and item not in want:
            continue
        if off < pos:
            sys.exit(f'{label}: item {item} at {off} overlaps the one before it')
        while pos < off:  # forward only: a zip member cannot seek back cheaply
            pos += len(f.read(min(off - pos, 1 << 22)))
        dst = os.path.join(out, item if item not in done else item + '.copy')
        with open(dst, 'wb') as o:
            left = length
            while left:
                chunk = f.read(min(left, 1 << 22))
                if not chunk:
                    sys.exit(f'{label}: short read in {item}')
                o.write(chunk)
                left -= len(chunk)
        pos += length
        if item in done:
            same = open(dst, 'rb').read() == open(done[item], 'rb').read()
            os.remove(dst)
            if not same:
                sys.exit(f'{label}: the two {item} items differ')
        else:
            done[item] = dst
    with open(os.path.join(out, 'items.tsv'), 'w') as t:
        t.write('file\titem\toffset\tlength\n')
        for off, length, item, fname in rows:
            t.write(f'{fname}\t{item}\t{off}\t{length}\n')
    print(f'{label}: {nfiles} items, {len(done)} written to {out}')


main()
