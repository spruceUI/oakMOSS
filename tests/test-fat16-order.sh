#!/usr/bin/env bash
# Host-side test for scripts/fat16-boot-resource.py: the same files listed in two orders (as two build hosts
# list a directory) give a byte-identical boot-resource, each directory in name order with the label,
# "." and ".." first, and the result reads back the same and passes make-update.py's check_bootres.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
python3 -I - "$HERE/../scripts" <<'PY'
import importlib.util, os, struct, sys
spec = importlib.util.spec_from_file_location('fat16', os.path.join(sys.argv[1], 'fat16-boot-resource.py'))
fat16 = importlib.util.module_from_spec(spec); spec.loader.exec_module(fat16)
fail = 0
def check(name, ok):
    global fail
    print(('ok   - ' if ok else 'FAIL - ') + name); fail |= not ok

def ent(name, attr):                       # a 32-byte entry, 1980-01-01 times, cluster and size filled in later
    return name.encode().ljust(11) + bytes([attr]) + bytes(20)
# fsbuild's geometry: 4 MiB, 2 sectors per cluster, 512 root entries, labelled FAT16
old = bytearray(4 << 20)
struct.pack_into('<HBHBHHBH', old, 11, 512, 2, 1, 2, 512, 8192, 0xF8, 12)
old[54:62] = b'FAT16   '
label = ([], ent('BOOTRES', 0x08), None)
files = [([], ent('BOOTLOGOBMP', 0x20), b'logo' * 3000), ([], ent('FONT24  SFT', 0x20), b'font' * 900),
         ([], ent('MAGIC   BIN', 0x20), b'')]
bat = [([], ent('LOW_PWR BMP', 0x20), b'low' * 2000), ([], ent('BAT0    BMP', 0x20), b'bat0' * 1500)]
sub = lambda kids: ([], ent('BAT', 0x10), [([], ent('.', 0x10), None), ([], ent('..', 0x10), None)] + kids)
a = [label] + files + [sub(bat)]
b = [label, sub(bat[::-1])] + files[::-1]
new_a, _ = fat16.write_fat16(bytes(old), a)
new_b, _ = fat16.write_fat16(bytes(old), b)
check('two listing orders give the same bytes', new_a == new_b)
check('it reads back the same', fat16.flatten(fat16.read_tree(new_a)) == fat16.flatten(a))
root = [e[:11] for _, e, _ in fat16.read_tree(new_a)]
check('root: the label first, then name order', root == [b'BOOTRES    ', b'BAT        ', b'BOOTLOGOBMP', b'FONT24  SFT', b'MAGIC   BIN'])
kids = [e[:11] for _, e, _ in [x for x in fat16.read_tree(new_a) if x[1][:3] == b'BAT'][0][2]]
check('subdirectory: "." and ".." first, then name order', kids == [b'.          ', b'..         ', b'BAT0    BMP', b'LOW_PWR BMP'])
try:
    fat16.make_update.check_bootres(new_a); ok = True
except SystemExit:
    ok = False
check('check_bootres passes', ok)
sys.exit(fail)
PY
