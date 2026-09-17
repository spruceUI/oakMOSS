#!/usr/bin/env python3
"""Check or fix the checksum of an Allwinner boot package ("sunxi-package", the
toc1 image boot0 loads from sector 32800: u-boot, monitor, scp, dtb).

    toc1-checksum.py --check <file> [offset-in-sectors]
    toc1-checksum.py --fix   <file> [offset-in-sectors]

boot0 sums every 32-bit word of the package (valid_len bytes) with the add_sum
field replaced by the stamp 0x5F0A6C39 and refuses to run U-Boot when the
result differs from add_sum. So any byte changed inside the package - the
device tree's status flags, say - must be followed by --fix, or the device
never gets past boot0: no U-Boot, no logo, no LED (Zero 40 and XU20,
2026-09-16: every image with the second-slot patch failed exactly so, the
same image with the package untouched booted). The header is
    name[16] "sunxi-package", magic 0x89119800, add_sum, serial, status,
    items_nr, valid_len ...
(brandy/u-boot include/private_toc.h, sbrom_toc1_head_info)."""
import struct
import sys

STAMP = 0x5F0A6C39
MAGIC = 0x89119800


def header(b):
    if b[:13] != b"sunxi-package":
        raise SystemExit("not a sunxi-package (no magic name)")
    magic, add_sum, _serial, _status, items, valid_len = struct.unpack_from("<IIIIII", b, 16)
    if magic != MAGIC:
        raise SystemExit(f"bad toc1 magic {magic:#x}")
    if valid_len % 4 or valid_len > len(b):
        raise SystemExit(f"valid_len {valid_len} does not fit the data ({len(b)} bytes)")
    return add_sum, items, valid_len


def checksum(b, valid_len, add_sum):
    words = struct.unpack_from(f"<{valid_len // 4}I", b, 0)
    return (sum(words) - add_sum + STAMP) & 0xFFFFFFFF


def main(argv):
    if len(argv) not in (3, 4) or argv[1] not in ("--check", "--fix"):
        raise SystemExit(__doc__)
    mode, path = argv[1], argv[2]
    off = int(argv[3]) * 512 if len(argv) == 4 else 0
    with open(path, "r+b" if mode == "--fix" else "rb") as f:
        f.seek(off)
        b = bytearray(f.read(4 << 20))
        add_sum, items, valid_len = header(b)
        want = checksum(b, valid_len, add_sum)
        if want == add_sum:
            print(f"    boot package checksum {add_sum:#010x} OK ({items} items, {valid_len} bytes)")
            return 0
        if mode == "--check":
            raise SystemExit(f"boot package checksum MISMATCH: header {add_sum:#010x}, data sums to {want:#010x} "
                             "- boot0 would refuse it; run --fix after patching")
        struct.pack_into("<I", b, 20, want)
        assert checksum(b, valid_len, want) == want
        f.seek(off + 20)
        f.write(struct.pack("<I", want))
        print(f"    boot package checksum fixed: {add_sum:#010x} -> {want:#010x} ({items} items, {valid_len} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
