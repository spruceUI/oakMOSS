#!/usr/bin/env python3
"""Replace one item inside an Allwinner boot package ("sunxi-package" / toc1) in place.

    toc1-item.py --list    <package>
    toc1-item.py --extract <package> <item> <out file>
    toc1-item.py --replace <package> <item> <new file>

The package is a fixed-size blob (valid_len in its header) whose item table (from
byte 64, 368 bytes per entry: name[64], offset, length, ...) points at the pieces
boot0 loads. --replace keeps the item where it is and requires the new data to fit
before the next item (or the end of the package); the remainder is zero-filled and
the length field updated. The checksum is NOT redone here: run toc1-checksum.py --fix
afterwards, and --check before shipping."""
import struct
import sys


def table(b):
    items = []
    for off in range(64, 64 + 368 * 8, 368):
        name = b[off:off + 64].split(b"\0")[0].decode()
        if not name:
            break
        o, l = struct.unpack_from("<II", b, off + 64)
        items.append((name, off, o, l))
    return items


def main(argv):
    mode, path = argv[1], argv[2]
    b = bytearray(open(path, "rb").read())
    if b[:13] != b"sunxi-package":
        raise SystemExit("not a sunxi-package")
    valid_len = struct.unpack_from("<I", b, 36)[0]
    items = table(b)
    if mode == "--list":
        for name, _, o, l in items:
            print(f"  {name:<8} offset={o:#x} length={l}")
        print(f"  valid_len={valid_len}")
        return 0
    name = argv[3]
    ent = next((i for i in items if i[0] == name), None)
    if not ent:
        raise SystemExit(f"no item {name!r} in the package")
    _, toff, o, l = ent
    if mode == "--extract":
        open(argv[4], "wb").write(bytes(b[o:o + l]))
        print(f"    {name}: {l} bytes -> {argv[4]}")
        return 0
    if mode == "--replace":
        new = open(argv[4], "rb").read()
        nxt = min([i[2] for i in items if i[2] > o] + [valid_len])
        room = nxt - o
        if len(new) > room:
            raise SystemExit(f"{name}: new data is {len(new)} bytes, only {room} fit before the next item")
        b[o:o + room] = new.ljust(room, b"\0")
        struct.pack_into("<I", b, toff + 68, len(new))
        open(path, "wb").write(bytes(b))
        print(f"    {name}: {l} -> {len(new)} bytes at {o:#x} ({room} available); redo the checksum")
        return 0
    raise SystemExit(__doc__)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
