#!/usr/bin/env bash
# Host-side test for overlay/usr/magicx/bin/oakmoss-update.sh against plain files: an update
# installs into the other slot only on a card of its own lane (sdk or own, docs/updates.md); an
# own-lane update carries no boot-resource and leaves the card's alone; a card without a second
# slot is refused before anything is written. fw_printenv and fw_setenv are stubs over a file.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
UPD=$HERE/../overlay/usr/magicx/bin/oakmoss-update.sh
FAIL=0
T=$(mktemp -d "${TMPDIR:-/tmp}/oakmoss-test-update.XXXX"); trap 'rm -rf "$T"' EXIT
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; sed 's/^/       /' "$T/out"; FAIL=1; fi; }

mkdir -p "$T/bin"
cat > "$T/bin/fw_printenv" <<'EOF'
#!/bin/sh
[ "$1" = -n ] && shift
awk -v k="$1" '$1 == k { v = substr($0, length(k) + 2); f = 1 } END { if (f) print v; else exit 1 }' "$ENVF"
EOF
cat > "$T/bin/fw_setenv" <<'EOF'
#!/bin/sh
if [ "$1" = -s ]; then cat "$2" >> "$ENVF"; else echo "$*" >> "$ENVF"; fi
EOF
chmod +x "$T/bin/fw_printenv" "$T/bin/fw_setenv"

# mkpkg <out> <lane|-> <build> <bootres 0|1> [bootchain 0|1]: a v90s package in make-update.py's format
mkpkg() { python3 -I - "$@" <<'PY'
import gzip, hashlib, sys
out, lane, build, with_bootres = sys.argv[1:5]
bootchain = sys.argv[5] if len(sys.argv) > 5 else '0'
A = 4096
parts = [('boot', b'BOOT-' + build.encode() * 1000, True), ('rootfs', b'hsqs' + build.encode() * 3000, False)]
if with_bootres == '1':
    parts.append(('bootres', b'SDK-BOOTRES' * 500, True))
lines = ['FORMAT=omupd1', 'BOARD=v90s'] + ([f'LANE={lane}'] if lane != '-' else []) + \
        [f'VERSION=v{build}', f'BUILD={build}', f'BOOTCHAIN={bootchain}', 'PARTS=' + ' '.join(n for n, _, _ in parts)]
blobs, off = [], A
for n, d, gz in parts:
    st = gzip.compress(d, 9, mtime=0) if gz else d
    lines += [f'{n}_OFFSET={off}', f'{n}_LENGTH={len(st)}', f'{n}_GZIP={int(gz)}', f'{n}_SIZE={len(d)}',
              f'{n}_SHA256={hashlib.sha256(d).hexdigest()}']
    blobs.append((off, st)); off += (len(st) + A - 1) // A * A
with open(out, 'wb') as f:
    f.write(('\n'.join(lines) + '\n').encode().ljust(A, b'\0'))
    for o, st in blobs:
        f.seek(o); f.write(st)
    f.truncate((off + A - 1) // A * A)
PY
}

# card <slot-b 0|1>: one plain file per partition, the boot-resource preset; slot A is running
card() {
    rm -rf "$T/card" "$T/sd"; mkdir -p "$T/card" "$T/sd"
    for p in boot rootfs bootloader $([ "$1" = 1 ] && echo boot_b rootfs_b); do
        head -c 65536 /dev/zero > "$T/card/$p"
    done
    printf 'STOCK-BOOTRES' | dd of="$T/card/bootloader" conv=notrunc 2>/dev/null
    printf 'boot_partition boot\nroot_partition rootfs\n' > "$T/env"
}
run() {  # run <lane> <pkg>: the updater as the board runs it, against the files
    rc=0
    ENVF=$T/env PATH="$T/bin:$PATH" DEVICE=v90s LANE=$1 KEEP_CHAIN=${KEEP:-$T/no-keep} BYNAME=$T/card BUILD_FILE=$T/build \
        BAT=$T/bat USB=$T/usb SHOW=true LOG=$T/log CARD_LOG=$T/sd/oakmoss-update.log TMPDIR=$T/tmp \
        sh "$UPD" "$2" >"$T/out" 2>&1 || rc=$?
}
slot_b_blank() { [ "$(tr -d '\000' < "$T/card/boot_b" | wc -c)" -eq 0 ] && [ "$(tr -d '\000' < "$T/card/rootfs_b" | wc -c)" -eq 0 ]; }
echo 100 > "$T/build"; echo 80 > "$T/bat"; echo 0 > "$T/usb"

# 1. own-lane card, own-lane package: slot B written, boot-resource kept, U-Boot pointed at B
card 1; mkpkg "$T/sd/oakmoss-v90s-own-v200.omupd" own 200 0
run own "$T/sd/oakmoss-v90s-own-v200.omupd"
check "own on own: exit 0" '[ "$rc" = 0 ]'
check "own on own: boot_b holds the new kernel" 'head -c 8 "$T/card/boot_b" | grep -q "BOOT-200"'
check "own on own: rootfs_b holds the new squashfs" 'head -c 4 "$T/card/rootfs_b" | grep -q hsqs'
check "own on own: stock boot-resource untouched" 'head -c 13 "$T/card/bootloader" | grep -q STOCK-BOOTRES'
check "own on own: next boot tries boot_b + rootfs_b" 'grep -qx "boot_partition boot_b" "$T/env" && grep -qx "root_partition rootfs_b" "$T/env" && grep -qx "ab_try 1" "$T/env"'
check "own on own: package removed" '[ ! -e "$T/sd/oakmoss-v90s-own-v200.omupd" ]'
check "own on own: logs that it carries no boot-resource" 'grep -q "bootres: not in this update (lane own)" "$T/log"'

# 2. own-lane card, SDK-lane package (boot-resource inside): set aside, nothing written
card 1; mkpkg "$T/sd/oakmoss-v90s-v201.omupd" - 201 1
run own "$T/sd/oakmoss-v90s-v201.omupd"
check "sdk on own: refused" '[ "$rc" != 0 ] && [ -e "$T/sd/oakmoss-v90s-v201.omupd.failed" ]'
check "sdk on own: slot B and boot-resource untouched" 'slot_b_blank && head -c 13 "$T/card/bootloader" | grep -q STOCK-BOOTRES'
check "sdk on own: env untouched" '[ "$(wc -l < "$T/env")" -eq 2 ]'

# 3. SDK-lane card, SDK-lane package: installs, boot-resource rewritten when it differs
card 1; mkpkg "$T/sd/oakmoss-v90s-v202.omupd" - 202 1
run sdk "$T/sd/oakmoss-v90s-v202.omupd"
check "sdk on sdk: exit 0" '[ "$rc" = 0 ]'
check "sdk on sdk: boot-resource rewritten" 'head -c 11 "$T/card/bootloader" | grep -q SDK-BOOTRES'

# 4. SDK-lane card, own-lane package: set aside, nothing written
card 1; mkpkg "$T/sd/oakmoss-v90s-own-v203.omupd" own 203 0
run sdk "$T/sd/oakmoss-v90s-own-v203.omupd"
check "own on sdk: refused" '[ "$rc" != 0 ] && [ -e "$T/sd/oakmoss-v90s-own-v203.omupd.failed" ]'
check "own on sdk: slot B untouched" 'slot_b_blank'

# 5. own-lane card without a second slot: refused before any write
card 0; mkpkg "$T/sd/oakmoss-v90s-own-v204.omupd" own 204 0
run own "$T/sd/oakmoss-v90s-own-v204.omupd"
check "no slot B: refused" '[ "$rc" != 0 ] && grep -q "no second slot" "$T/out"'
check "no slot B: slot A and boot-resource untouched" '[ "$(tr -d "\000" < "$T/card/boot" | wc -c)" -eq 0 ] && head -c 13 "$T/card/bootloader" | grep -q STOCK-BOOTRES'

# 6-8. a card that keeps the vendor's boot chain (TrimUI, /usr/magicx/keep-boot-chain): no package
# that writes boot0, the U-Boot package or the boot-resource; a plain own-lane package still installs
touch "$T/keep"
card 1; mkpkg "$T/sd/oakmoss-v90s-own-v205.omupd" own 205 0 1
KEEP=$T/keep run own "$T/sd/oakmoss-v90s-own-v205.omupd"
check "keep-chain card, BOOTCHAIN=1: refused" '[ "$rc" != 0 ] && [ -e "$T/sd/oakmoss-v90s-own-v205.omupd.failed" ]'
check "keep-chain card, BOOTCHAIN=1: slot B and env untouched" 'slot_b_blank && [ "$(wc -l < "$T/env")" -eq 2 ]'
card 1; mkpkg "$T/sd/oakmoss-v90s-own-v206.omupd" own 206 1
KEEP=$T/keep run own "$T/sd/oakmoss-v90s-own-v206.omupd"
check "keep-chain card, boot-resource inside: refused" '[ "$rc" != 0 ] && [ -e "$T/sd/oakmoss-v90s-own-v206.omupd.failed" ]'
check "keep-chain card, boot-resource inside: nothing written" 'slot_b_blank && head -c 13 "$T/card/bootloader" | grep -q STOCK-BOOTRES'
card 1; mkpkg "$T/sd/oakmoss-v90s-own-v207.omupd" own 207 0
KEEP=$T/keep run own "$T/sd/oakmoss-v90s-own-v207.omupd"
check "keep-chain card, plain own package: installs" '[ "$rc" = 0 ] && head -c 8 "$T/card/boot_b" | grep -q "BOOT-207"'

exit $FAIL
