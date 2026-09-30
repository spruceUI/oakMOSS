#!/usr/bin/env python3
"""Decode an oakMOSS KDEBUG_MARK mark ring (sdk-patches/debug/kdebug-mark.patch, init/main.c).

    scripts/kmark-ring.py <names file> <ring dump> [--tail N] [--boot K]

The ring is 1 MB of reserved, unmapped RAM at 0x7f000000 that a debug kernel appends every
mark to. It is never cleared, so after a watchdog or panic reset the previous boot's tail is
still there. Dump it on the board (base64, so it survives the ssh pipe):

    python3 -c "import mmap,os,sys,base64; f=os.open('/dev/mem',os.O_RDONLY|os.O_SYNC); \\
      m=mmap.mmap(f,0x100000,mmap.MAP_SHARED,mmap.PROT_READ,offset=0x7f000000); \\
      sys.stdout.write(base64.b64encode(m[:]).decode())" > ring.b64

(this script accepts the base64 text or raw bytes). By default it prints the last --tail
entries (400) of the boot BEFORE the most recent boot boundary - the run that hung - with the
time before its last entry, the CPU, 'I' for interrupt context, and the decoded mark.
Set KMARK_SYSTEM_MAP=<build>/System.map to name addresses.
"""
import base64
import importlib.util
import os
import struct
import sys

MAGIC = 0x4f414b52
FREQ = 24_000_000


def load_decoder():
    here = os.path.dirname(os.path.abspath(__file__))
    spec = importlib.util.spec_from_file_location('kmark_pm_decode', os.path.join(here, 'kmark-pm-decode.py'))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def read_ring(path):
    data = open(path, 'rb').read()
    if data[:4] != struct.pack('<I', MAGIC):
        data = base64.b64decode(data)
    magic, seq, boots, entries = struct.unpack_from('<4I', data, 0)
    if magic != MAGIC:
        sys.exit(f'no ring here (magic {magic:#x}): the DRAM did not keep it, or the kernel has no ring')
    out = []
    for i in range(entries):
        mark, meta, lo, hi = struct.unpack_from('<4I', data, 64 + i * 16)
        if meta == 0 and lo == 0 and hi == 0:
            continue
        out.append((meta & 0x7ffffff, mark, meta >> 28, (meta >> 27) & 1, (hi << 32) | lo))
    out.sort()
    return seq, boots, out


def main(argv):
    args = [a for a in argv[1:] if not a.startswith('--')]
    opts = dict(zip(argv[1::1], argv[2::1]))
    if len(args) < 2:
        sys.exit(__doc__)
    tail = int(opts.get('--tail', 400))
    dec = load_decoder()
    names = dec.load_names(args[0])
    seq, boots, ents = read_ring(args[1])
    marks = [i for i, e in enumerate(ents) if e[1] >> 16 == 0xb007]
    print(f'ring: last seq {seq}, boots {boots}, {len(ents)} entries, boot boundaries at seq '
          f'{[ents[i][0] for i in marks][-5:]}')
    k = int(opts.get('--boot', 1))
    if len(marks) >= k + 1:
        lo, hi = marks[-k - 1], marks[-k]
    elif marks:
        lo, hi = 0, marks[-k]
    else:
        lo, hi = 0, len(ents)
    seg = ents[lo:hi][-tail:]
    if not seg:
        sys.exit('nothing recorded before the boundary')
    last = seg[-1][4]
    prev = None
    for s, mark, cpu, irq, cnt in seg:
        gap = '' if prev is None else f'+{(cnt - prev) / FREQ * 1000:8.3f}'
        prev = cnt
        print(f'{s:9d} {-(last - cnt) / FREQ * 1000:10.3f} ms {gap:>10} cpu{cpu} {"I" if irq else " "} '
              f'{mark:#010x}  {dec.describe(mark, names)}')


if __name__ == '__main__':
    main(sys.argv)
