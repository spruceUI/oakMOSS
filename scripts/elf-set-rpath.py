#!/usr/bin/env python3
"""Rewrite DT_RPATH/DT_RUNPATH in place, in an aarch64 ELF, to a shorter string.

The SDK's toolchain is a wrapper script that appends
`-Wl,-rpath=<toolchain>/lib:<toolchain>/usr/lib` to every link and offers no way
to turn that off (scripts/.../aarch64-openwrt-linux-gnu-wrapper.sh:60). So every
binary it produces carries the absolute path of the build machine's SDK. That is
useless on a device, and it leaks the builder's directory layout into files that
ship.

Only shrinking is supported: the string is overwritten where it already sits in
.dynstr and NUL-padded, so no offset anywhere else in the file moves. A longer
replacement is refused rather than risking a rebuild of the string table.

  elf-set-rpath.py <new-rpath> <file>...
"""
import struct
import sys

DT_NULL, DT_STRTAB, DT_RPATH, DT_RUNPATH = 0, 5, 15, 29


def vaddr_to_off(phdrs, vaddr):
    for p_type, p_offset, p_vaddr, p_filesz in phdrs:
        if p_type == 1 and p_vaddr <= vaddr < p_vaddr + p_filesz:   # PT_LOAD
            return p_offset + (vaddr - p_vaddr)
    raise SystemExit(f"vaddr {vaddr:#x} is in no PT_LOAD segment")


def set_rpath(path, new):
    data = bytearray(open(path, "rb").read())
    if data[:4] != b"\x7fELF" or data[4] != 2 or data[5] != 1:
        raise SystemExit(f"{path}: not a little-endian ELF64")
    e_phoff, = struct.unpack_from("<Q", data, 0x20)
    e_phentsize, e_phnum = struct.unpack_from("<HH", data, 0x36)

    phdrs, dyn = [], None
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        p_type, = struct.unpack_from("<I", data, off)
        p_offset, p_vaddr = struct.unpack_from("<QQ", data, off + 0x08)
        p_filesz, = struct.unpack_from("<Q", data, off + 0x20)
        phdrs.append((p_type, p_offset, p_vaddr, p_filesz))
        if p_type == 2:                                             # PT_DYNAMIC
            dyn = (p_offset, p_filesz)
    if dyn is None:
        return False

    dyn_off, dyn_size = dyn
    entries, strtab = [], None
    for off in range(dyn_off, dyn_off + dyn_size, 16):
        tag, val = struct.unpack_from("<qQ", data, off)
        if tag == DT_NULL:
            break
        if tag == DT_STRTAB:
            strtab = val
        if tag in (DT_RPATH, DT_RUNPATH):
            entries.append(val)
    if not entries or strtab is None:
        return False

    strtab_off = vaddr_to_off(phdrs, strtab)
    encoded = new.encode() + b"\0"
    for str_off in entries:
        start = strtab_off + str_off
        end = data.index(b"\0", start)
        old_len = end - start + 1
        if len(encoded) > old_len:
            raise SystemExit(f"{path}: new rpath is longer than the old one "
                             f"({len(encoded)} > {old_len}); refusing")
        data[start:start + old_len] = encoded + b"\0" * (old_len - len(encoded))
    open(path, "wb").write(data)
    return True


if __name__ == "__main__":
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    for f in sys.argv[2:]:
        set_rpath(f, sys.argv[1])
