#!/usr/bin/env python3
"""Decode a raw read-back of an oakMOSS SD1 card (the first N bytes of the card).

    scripts/analyze-card-readback.py <raw card read> [builds dir]

Answers, in order, the questions a stuck boot raises:
  - which build the card is (root PARTUUID in its env, matched against builds/*/env.txt)
  - the partition table's state (primary entry pointer, backup location, CRCs) and
    whether boot0 is intact at sector 16 and at the 256 mirror
  - how far the system got: oakmoss-boot.log on UDISK, and whether rootfs_data and
    UDISK were ever mounted (mount count / last-mount time)
  - anything the kernel wrote to the pstore partition (panic / restart / power-off log)
  - which regions differ from the image as built
"""
import glob, os, re, struct, subprocess, sys, tempfile, zlib

S = 512
raw = sys.argv[1]
builds = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'builds')
f = open(raw, 'rb')
size = os.path.getsize(raw)
rd = lambda lba, n=1: (f.seek(lba * S), f.read(n * S))[1]


def gpt(read):
    h = read(1)
    if h[:8] != b'EFI PART':
        return None
    hh = bytearray(h[:92]); hc, = struct.unpack_from('<I', hh, 16); struct.pack_into('<I', hh, 16, 0)
    my, alt, fu, lu = struct.unpack_from('<QQQQ', h, 24)
    el, n, esz, ec = struct.unpack_from('<QIII', h, 72)
    arr = read(el, n * esz // S) if (el + n * esz // S) * S <= size else b''
    ents = []
    for i in range(n):
        e = arr[i * 128:(i + 1) * 128]
        if len(e) < 128 or e[:16] == b'\0' * 16:
            continue
        st, en = struct.unpack_from('<QQ', e, 32)
        ents.append((e[56:128].decode('utf-16-le', 'replace').rstrip('\0'), st, en))
    return dict(alt=alt, first_usable=fu, entries_lba=el, n=n,
                header_ok=(zlib.crc32(bytes(hh)) & 0xffffffff) == hc,
                entries_ok=bool(arr) and (zlib.crc32(arr) & 0xffffffff) == ec, ents=ents)


# identify the build
env = b''
g = gpt(rd)
parts = {}
if g and g['entries_ok'] and g['ents']:
    parts = {name: (st, en) for name, st, en in g['ents']}
if not parts:  # primary unusable (e.g. rewritten, CRC bad): fall back to the entries at 2048 or 2
    for el in (2048, 2):
        blob = rd(el, 32)
        for i in range(128):
            e = blob[i * 128:(i + 1) * 128]
            if e[:16] != b'\0' * 16:
                st, en = struct.unpack_from('<QQ', e, 32)
                parts[e[56:128].decode('utf-16-le', 'replace').rstrip('\0')] = (st, en)
        if parts:
            break
if 'env' in parts:
    env = rd(parts['env'][0], 256)
m = re.search(rb'mmc_root=PARTUUID=([0-9a-f-]{36})', env)
uuid = m.group(1).decode() if m else None
match = [os.path.basename(os.path.dirname(e)) for e in glob.glob(os.path.join(builds, '*', 'env.txt'))
         if uuid and uuid in open(e, errors='replace').read()]
print(f"card: root PARTUUID {uuid} -> build {match or 'no match'}")
bm = re.search(rb'bootmark=([uk0-9a-f.]*)\x00', env)
if bm is not None:
    seq = bm.group(1).decode()
    print(f"U-Boot passes that reached bootcmd (bootmark): {seq.count('u')}" + (f"; kernel loaded and jumped to: {seq.count('k')}; sequence {seq}" if 'k' in seq or 'setenv bootmark ${bootmark}k' in env.decode(errors='replace') else ''))
    if b'oakmoss_mark=' in env:
        # KMARK cards: each 'u<hex>' carries where the PREVIOUS boot's kernel stopped
        # (make-own-kernel-stock.sh KMARK=1); the last boot's own mark is still in the RTC.
        stages = {0: 'no mark (kernel ran no initcall, or the register was cleared)', 1: 'stage 1: all initcalls done',
                  2: 'stage 2: /dev/console opened', 3: 'stage 3: root mounted (prepare_namespace done)',
                  4: 'stage 4: async init work finished', 5: 'stage 5: init memory freed', 6: 'stage 6: exec of init'}
        smap = {}
        for d in ([os.path.join(builds, m, 'System.map') for m in match] if match else []):
            if os.path.exists(d):
                for l in open(d):
                    a, t, n = l.split()[:3]
                    if t in 'tT': smap.setdefault(int(a, 16) & 0xffffffff, n)
        # driver step codes (sdk-patches/debug/kdebug-mark.patch): 0x4859SSNN Hynitron touch
        hyn = {0x0101: 'driver init entered', 0x0102: 'input_sensor_startup done', 0x0103: 'input_sensor_init done',
               0x0104: 'before ctp_get_system_config', 0x0105: 'before touch power enable', 0x0106: 'touch power enabled',
               0x0107: 'i2c_add_driver called (probe runs inside)', 0x0108: 'i2c_add_driver returned',
               0x0201: 'probe entered', 0x0202: 'platform data done', 0x0203: 'GPIOs configured (reset pulsed)',
               0x0204: 'ts data init done', 0x0205: '60 ms wait done, reading firmware info', 0x0206: 'firmware info returned',
               0x0207: 'firmware info failed, detecting bootloader', 0x0208: 'bootloader detect returned',
               0x0209: 'registering input device', 0x020a: 'input device registered', 0x020b: 'IRQ requested',
               0x020c: 'IRQ disabled, update-firmware init (reads firmware info)', 0x020d: 'update-firmware init returned',
               0x020e: 'resetting the controller (the post-IRQ reset, removed 2026-09-18 night)',
               0x020f: 'enabling IRQ', 0x0210: 'IRQ enabled',
               0x0301: 'reset pulse: reset line driven low', 0x0302: 'reset pulse: held 20 ms, releasing',
               0x0303: 'reset pulse: released, settling', 0x0304: 'reset pulse: done',
               0x0211: 'probe finished OK', 0x02ee: 'probe failed (err_end)'}
        i2cph = {1: 'entered', 2: 'START sent, waiting for the transfer IRQ', 3: 'completed', 4: 'TIMED OUT', 5: 'START failed', 6: 'bus busy, 9-pulse recovery failed'}
        axs = {0x0101: 'driver init entered (probe runs inside)', 0x0102: 'i2c_add_driver returned (zero40-kmark card)', 0x0201: 'probe entered',
               0x0202: 'GPIOs + reset pulse done, 120 ms panel wait', 0x0203: 'reading firmware version (3 tries)',
               0x0204: 'version read returned', 0x0205: 'registering input device', 0x0206: 'requesting IRQ',
               0x0207: 'probe finished OK'}
        def name(v):
            if v >> 16 == 0x4859:
                return f'Hynitron touch: {hyn.get(v & 0xffff, hex(v))}'
            if v >> 16 == 0x4158:
                return f'AXS15205 touch: {axs.get(v & 0xffff, hex(v))}'
            if v >> 24 in (0x48, 0x41):  # packed: DD.ss.AA.PP (kdebug-mark.patch, GPR5 only)
                ss = (v >> 16) & 0xff
                code = 0x02ee if ss == 0xff else (0x0200 | (ss & 0x7f)) if ss & 0x80 else (0x0300 | (ss & 0x3f)) if ss & 0x40 else 0x0100 | ss
                drv, table = ('Hynitron', hyn) if v >> 24 == 0x48 else ('AXS15205', axs)
                out = f'{drv} touch: {table.get(code, hex(code))}'
                if v & 0xffff:
                    out += f"; last touch-bus (twi1) transfer: addr {(v >> 8) & 0xff:#04x} {i2cph.get(v & 0xff, hex(v & 0xff))}"
                return out
            return stages.get(v) or smap.get(v) or (f'{v:#x} (not in System.map)' if smap else f'{v:#x} (no System.map beside the build)')
        marks = re.findall(r'u([0-9a-f]*)(?:\.([0-9a-f]*))?', seq)
        print('kernel progress marks (each describes the boot BEFORE the U-Boot pass that read it):')
        for i, (a, b) in enumerate(marks):
            v = int(a or '0', 16); line = f"  read at pass {i + 1}: {name(v)}"
            if b:
                w = int(b, 16)
                if w >> 16 == 0x4931:
                    line += f"  | last touch-bus (twi1) transfer: addr {(w >> 8) & 0xff:#04x} {i2cph.get(w & 0xff, hex(w & 0xff))}"
                elif w:
                    line += f"  | mark2 {w:#x}"
            print(line)
elif b'setenv bootmark' in env:
    print("bootmark: bootcmd stamps it but no bootmark variable was saved - U-Boot never reached bootcmd, or saveenv failed")

# table and boot0
if g:
    print(f"table: entries@{g['entries_lba']} n={g['n']} first_usable={g['first_usable']} backup@{g['alt']:,} "
          f"header={'OK' if g['header_ok'] else 'BAD'} entries={'OK' if g['entries_ok'] else 'BAD (pointer does not match)'}")
else:
    print("table: no GPT header at LBA 1")
print(f"boot0: sector 16 {rd(16)[4:12]!r}  sector 256 {rd(256)[4:12]!r}")

# how far the system got
def ext4(name):
    if name not in parts:
        return None
    st, en = parts[name]
    t = tempfile.NamedTemporaryFile(delete=False, suffix='.ext4'); t.write(rd(st, en - st + 1)); t.close()
    return t.name
for name in ('UDISK', 'rootfs_data'):
    p = ext4(name)
    if not p:
        continue
    hdr = subprocess.run(['dumpe2fs', '-h', p], capture_output=True, text=True).stdout
    get = lambda k: next((l.split(':', 1)[1].strip() for l in hdr.splitlines() if l.startswith(k)), '?')
    print(f"{name}: mount count {get('Mount count')}, last mount {get('Last mount time')}, last write {get('Last write time')}, state {get('Filesystem state')}")
    if name == 'UDISK':
        log = subprocess.run(['/usr/sbin/debugfs', '-R', 'cat /oakmoss-boot.log', p], capture_output=True, text=True).stdout
        print("oakmoss-boot.log:" + ("\n  " + "\n  ".join(log.strip().splitlines()[-12:]) if log.strip() else " (empty or absent)"))
        ls = subprocess.run(['/usr/sbin/debugfs', '-R', 'ls -p /', p], capture_output=True, text=True).stdout
        for dm in sorted(re.findall(r'/(oakmoss-dmesg-\d+(?:-touch)?\.log)/', ls)):
            out = os.path.join(os.path.dirname(os.path.abspath(raw)), os.path.basename(raw) + '.' + dm)
            subprocess.run(['/usr/sbin/debugfs', '-R', f'dump /{dm} {out}', p], capture_output=True)
            print(f"kernel log saved by the hand-off: {out}")
    os.unlink(p)

# pstore
if 'pstore' in parts:
    st, en = parts['pstore']
    blob = rd(st, en - st + 1)
    stamp = blob[-S:].rstrip(b'\0')
    if stamp.startswith(b'i'):  # INIT_STAMP cards: init= ran, one 'i<uptime>;' per boot
        runs = [x for x in stamp.decode(errors='replace').split(';') if x]
        print(f"init stamp (kernel ran init= from the root fs): {len(runs)} times, at uptime {', '.join(r[1:] for r in runs)} s")
        blob = blob[:-S]
    elif 'pstore' in parts and b'init-stamp' in env:
        print('init stamp: none - the kernel never ran init= on this card')
    if blob.count(0) == len(blob):
        print("pstore: empty (no panic, restart or power-off was recorded)")
    else:
        text = re.findall(rb'[ -~\t]{6,}', blob)
        print(f"pstore: {sum(1 for b in blob if b)} non-zero bytes; last kernel lines:")
        for l in text[-40:]:
            print("  " + l.decode(errors='replace'))

# regions that differ from the build
if match:
    img = glob.glob(os.path.join(builds, match[0], '*.img'))
    if img:
        fi = open(img[0], 'rb'); ri = lambda lba, n=1: (fi.seek(lba * S), fi.read(n * S))[1]
        regions = [(0, 34, 'table sectors 0-33'), (34, 222, 'sectors 34-255'), (256, 64, 'boot0 mirror'), (32800, 2144, 'boot package')]
        regions += [(st, en - st + 1, f'p:{name}') for name, (st, en) in parts.items()]
        changed = [label for lba, n, label in regions if ri(lba, n) != rd(lba, n)]
        print("differs from the image as built:", changed or "nothing")
