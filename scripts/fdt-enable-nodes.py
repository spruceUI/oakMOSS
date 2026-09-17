#!/usr/bin/env python3
"""Enable device-tree nodes in place, without moving a single byte.

    fdt-enable-nodes.py <file> <offset> <node-name> [<node-name> ...]

The flattened device trees we need to edit are embedded inside larger blobs -
the boot package at sector 32800 and the Android boot image's dtb section - both
of which record the sizes and offsets of what they contain. Rebuilding a tree
with dtc changes its length and would mean rewriting those containers, so this
edits the tree where it lies instead.

That works because a device tree pads every property to a four-byte boundary and
records its length separately. "disabled\\0" is nine bytes and occupies twelve;
"okay\\0" is five and occupies eight. Writing the shorter string, shortening the
recorded length, and spending the four bytes that fall free on a NOP token - the
one token a device tree defines for exactly this purpose - leaves the tree the
same size, correctly formed, and reading "okay". Nothing downstream has to know
the edit happened.

A node that is already enabled, or has no status property at all (which also
means enabled), is left alone and reported.
"""
import sys

FDT_MAGIC = 0xD00DFEED
BEGIN_NODE, END_NODE, PROP, NOP, END = 1, 2, 3, 4, 9


def u32(buf, off):
    return int.from_bytes(buf[off:off + 4], "big")


def enable(data, base, wanted):
    """Patch every named node's status to okay. Returns a list of (node, what)."""
    if u32(data, base) != FDT_MAGIC:
        raise SystemExit(f"no device tree at offset {base}: magic is {u32(data, base):#x}")
    off_struct = base + u32(data, base + 8)
    off_strings = base + u32(data, base + 12)
    size_struct = u32(data, base + 36)

    def prop_name(name_off):
        end = data.index(b"\0", off_strings + name_off)
        return data[off_strings + name_off:end].decode()

    changed, path, pos, limit = [], [], off_struct, off_struct + size_struct
    # Remember where each open node started so a status property can be attributed.
    while pos < limit:
        tag = u32(data, pos)
        if tag == BEGIN_NODE:
            end = data.index(b"\0", pos + 4)
            path.append(data[pos + 4:end].decode())
            pos = (end + 4) & ~3
        elif tag == END_NODE:
            path.pop()
            pos += 4
        elif tag == PROP:
            plen, noff = u32(data, pos + 4), u32(data, pos + 8)
            value_at = pos + 12
            if path and path[-1] in wanted and prop_name(noff) == "status":
                current = data[value_at:value_at + plen].split(b"\0")[0].decode()
                old_pad = (plen + 3) & ~3
                new_pad = (5 + 3) & ~3
                if current in ("okay", "ok"):
                    changed.append((path[-1], f"already {current}"))
                elif old_pad < new_pad:
                    raise SystemExit(f"{path[-1]}: status occupies only {old_pad} bytes, cannot hold 'okay'")
                else:
                    data[pos + 4:pos + 8] = (5).to_bytes(4, "big")
                    data[value_at:value_at + new_pad] = b"okay\0".ljust(new_pad, b"\0")
                    # spend the bytes that fell free on NOPs, so nothing moves
                    for slack in range(value_at + new_pad, value_at + old_pad, 4):
                        data[slack:slack + 4] = NOP.to_bytes(4, "big")
                    changed.append((path[-1], f"{current} -> okay"))
            pos = value_at + ((plen + 3) & ~3)
        elif tag == NOP:
            pos += 4
        elif tag == END:
            break
        else:
            raise SystemExit(f"bad device-tree tag {tag:#x} at {pos}")
    return changed


def main():
    if len(sys.argv) < 4:
        raise SystemExit(__doc__)
    path, base, wanted = sys.argv[1], int(sys.argv[2], 0), set(sys.argv[3:])
    data = bytearray(open(path, "rb").read())
    changed = enable(data, base, wanted)
    seen = {node for node, _ in changed}
    missing = wanted - seen
    if missing:
        raise SystemExit(f"not found in the device tree, or it has no status property: {sorted(missing)}")
    with open(path, "wb") as fh:
        fh.write(data)
    for node, what in changed:
        print(f"    {node}: {what}")


if __name__ == "__main__":
    main()
