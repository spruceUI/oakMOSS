#!/usr/bin/env python3
"""Rewrite an image's boot-resource partition as a FAT16 with one sector per cluster.

fsbuild packs the boards' 4 MiB boot-resource with 2 sectors per cluster: 4071 clusters, which
U-Boot reads as FAT16 (by the label) and Linux as FAT12 (by the count, fs/fat/inode.c), so a
write from Linux corrupts it for U-Boot. This reads every entry fsbuild wrote and writes them
again, in place, into a FAT16 of about 8111 clusters: names (8.3 and long), attributes, times,
sizes and contents unchanged. It reads the result back and compares it before writing.

    scripts/fat16-boot-resource.py <sd1.img>
    scripts/fat16-boot-resource.py --export <sd1.img> <out.fex>   the partition as it is, checked
"""
import importlib.util
import hashlib
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location('make_update', os.path.join(HERE, 'make-update.py'))
make_update = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(make_update)
SECTOR = make_update.SECTOR


def bpb(fat):
    bps, spc, rsv, nfats, roots, tot16, media, spf = struct.unpack_from('<HBHBHHBH', fat, 11)
    tot = tot16 or struct.unpack_from('<I', fat, 32)[0]
    return bps, spc, rsv, nfats, roots, tot, media, spf


def read_tree(fat):
    """[(raw entries before it (LFN), raw 32-byte entry, data or children)] for the root, recursively."""
    bps, spc, rsv, nfats, roots, tot, _, spf = bpb(fat)
    if bps != SECTOR:
        sys.exit(f'boot-resource: {bps}-byte sectors')
    table = fat[rsv * bps:(rsv + spf) * bps]
    data0 = (rsv + nfats * spf) * bps + roots * 32
    csize = spc * bps
    # The table's width follows the cluster count, as Linux reads it: fsbuild's 4 MiB FAT is
    # labelled FAT16 but its table is 12-bit.
    fat12 = (tot - data0 // bps) // spc < 4085
    eoc = 0xFF8 if fat12 else 0xFFF8

    def next_cluster(c):
        if not fat12:
            return struct.unpack_from('<H', table, c * 2)[0]
        v = struct.unpack_from('<H', table, c * 3 // 2)[0]
        return v >> 4 if c & 1 else v & 0xFFF

    def chain(c):
        seen = []
        while 2 <= c < eoc:
            if c in seen or len(seen) > tot:
                sys.exit('boot-resource: a looping cluster chain')
            seen.append(c)
            c = next_cluster(c)
        return seen

    def clusters(c):
        return b''.join(fat[data0 + (n - 2) * csize:data0 + (n - 1) * csize] for n in chain(c))

    def entries(raw):
        out, lfn = [], []
        for i in range(0, len(raw), 32):
            e = raw[i:i + 32]
            if e[0] == 0:
                break
            if e[0] == 0xE5:
                lfn = []
                continue
            if e[11] == 0x0F:
                lfn.append(e)
                continue
            first = struct.unpack_from('<H', e, 26)[0]
            if e[11] & 0x08 or e[:11] in (b'.          ', b'..         '):
                out.append((lfn, e, None))       # the volume label, "." and "..": kept as they are
            elif e[11] & 0x10:
                out.append((lfn, e, entries(clusters(first))))
            else:
                size = struct.unpack_from('<I', e, 28)[0]
                out.append((lfn, e, clusters(first)[:size]))
            lfn = []
        return out

    root = fat[(rsv + nfats * spf) * bps:data0]
    return entries(root)


def flatten(tree, prefix=''):
    """{path: sha256 or 'dir'} for comparing two trees."""
    out = {}
    for lfn, e, body in tree:
        if body is None:
            continue
        name = prefix + e[:11].decode('latin1') + ''.join(x.hex() for x in lfn)
        if isinstance(body, list):
            out[name] = 'dir'
            out.update(flatten(body, name + '/'))
        else:
            out[name] = hashlib.sha256(body).hexdigest() + f':{len(body)}:{e[11]:02x}:{e[13:26].hex()}'
    return out


def write_fat16(old, tree):
    bps, _, rsv, nfats, roots, tot, media, _ = bpb(old)
    rootsecs = roots * 32 // bps
    spf = 1
    while True:                                   # the smallest FAT that holds every cluster
        n = tot - rsv - nfats * spf - rootsecs
        if (n + 2) * 2 <= spf * bps:
            break
        spf += 1
    if not 4085 <= n <= 65524:
        sys.exit(f'boot-resource: {n} clusters of one sector is not a FAT16 either')
    table = [0] * (n + 2)
    table[0], table[1] = 0xFF00 | media, 0xFFFF
    data = bytearray(n * bps)
    nxt = [2]

    def alloc(body):
        count = max(1, -(-len(body) // bps))
        first = nxt[0]
        if first + count - 2 > n:
            sys.exit('boot-resource: the files do not fit')
        for c in range(first, first + count):
            table[c] = c + 1
        table[first + count - 1] = 0xFFFF
        data[(first - 2) * bps:(first - 2) * bps + len(body)] = body
        nxt[0] += count
        return first

    def entry(e, first, size):
        e = bytearray(e)
        struct.pack_into('<H', e, 26, first)
        struct.pack_into('<I', e, 28, size)
        return bytes(e)

    def directory(items, self_cluster, parent_cluster):
        """A directory's raw bytes; subdirectories and files are allocated as they come."""
        raw = b''
        for lfn, e, body in items:
            if body is None:
                if e[:11] == b'.          ':
                    e = entry(e, self_cluster, 0)
                elif e[:11] == b'..         ':
                    e = entry(e, parent_cluster, 0)
                raw += b''.join(lfn) + e
            elif isinstance(body, list):
                # the subdirectory's cluster count follows from its entry count, before it is filled
                need = sum(len(l) + 1 for l, _, _ in body) * 32
                first = alloc(bytes(need))
                sub = directory(body, first, self_cluster)
                data[(first - 2) * bps:(first - 2) * bps + len(sub)] = sub
                raw += b''.join(lfn) + entry(e, first, 0)
            else:
                first = alloc(body) if body else 0
                raw += b''.join(lfn) + entry(e, first, len(body))
        return raw

    root = directory(tree, 0, 0)
    if len(root) > roots * 32:
        sys.exit('boot-resource: the root directory overflows')
    boot = bytearray(old[:bps])
    struct.pack_into('<B', boot, 13, 1)                   # sectors per cluster
    struct.pack_into('<H', boot, 22, spf)
    struct.pack_into('<H', boot, 19, tot if tot < 0x10000 else 0)
    struct.pack_into('<I', boot, 32, 0 if tot < 0x10000 else tot)
    boot[54:62] = b'FAT16   '
    # fsbuild leaves the extended boot signature at 0, so its label field "is not there": declare it
    # (0x29) with the root's label, which fsck.fat requires to match; the serial stays 0.
    label = [e for _, e, body in tree if body is None and e[11] & 0x08]
    boot[38] = 0x29
    boot[43:54] = label[0][:11] if label else b'NO NAME    '
    fatbytes = b''.join(struct.pack('<H', v) for v in table).ljust(spf * bps, b'\0')
    img = bytes(boot) + bytes((rsv - 1) * bps) + fatbytes * nfats + root.ljust(rootsecs * bps, b'\0') + bytes(data)
    assert len(img) == tot * bps, (len(img), tot * bps)
    return img, n


def export(path, out):
    with open(path, 'rb') as img:
        parts, _ = make_update.gpt_partitions(img)
        start, sectors = parts['bootloader']
        fat = make_update.read_at(img, start, sectors * SECTOR)
    make_update.check_bootres(fat)
    with open(out, 'wb') as f:
        f.write(fat)


def main():
    if len(sys.argv) == 4 and sys.argv[1] == '--export':
        return export(sys.argv[2], sys.argv[3])
    if len(sys.argv) != 2:
        sys.exit(__doc__.strip().splitlines()[-2].strip())
    path = sys.argv[1]
    with open(path, 'r+b') as img:
        parts, _ = make_update.gpt_partitions(img)
        start, sectors = parts['bootloader']
        old = make_update.read_at(img, start, sectors * SECTOR)
        if bpb(old)[5] * SECTOR != len(old):
            sys.exit('boot-resource: the FAT is not the size of its partition (boot-resource.ini, build.sh)')
        tree = read_tree(old)
        new, n = write_fat16(old, tree)
        if flatten(read_tree(new)) != flatten(tree):
            sys.exit('boot-resource: the rewritten FAT does not read back the same')
        make_update.check_bootres(new)
        img.seek(start * SECTOR)
        img.write(new)
    print(f'boot-resource: FAT16 of {n} one-sector clusters, {len(flatten(tree))} entries kept')


if __name__ == '__main__':
    main()
