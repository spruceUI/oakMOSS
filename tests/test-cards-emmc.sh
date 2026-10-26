#!/usr/bin/env bash
# Host-side test for the eMMC guard in overlay/usr/magicx/bin/oakmoss-cards.sh: on a board that
# boots from a card but has an eMMC (TrimUI: mmcblk0), neither the election nor hotplug may take
# the eMMC, its partitions, boot areas or rpmb as a card. The sysfs tree is faked with the
# kernel's shape: /sys/class/block/<name> links into the device tree, partitions inside their disk.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CARDS=$HERE/../overlay/usr/magicx/bin/oakmoss-cards.sh
FAIL=0
T=$(mktemp -d "${TMPDIR:-/tmp}/oakmoss-test-cards.XXXX"); trap 'rm -rf "$T"' EXIT
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; FAIL=1; fi; }

D=$T/devices; SYS_BLOCK=$T/class-block; mkdir -p "$SYS_BLOCK"
disk() {	# disk <name> <mmc type> [partitions...]
    mkdir -p "$D/$1/device"; echo "$2" > "$D/$1/device/type"; ln -s "$D/$1" "$SYS_BLOCK/$1"
    local n=$1; shift 2
    for p in "$@"; do mkdir -p "$D/$n/$p"; echo "${p##*p}" > "$D/$n/$p/partition"; ln -s "$D/$n/$p" "$SYS_BLOCK/$p"; done
}
disk mmcblk0 MMC mmcblk0p1 mmcblk0p10
disk mmcblk0boot0 MMC
disk mmcblk0rpmb MMC
disk mmcblk1 SD mmcblk1p1 mmcblk1p15
disk mmcblk2 SD mmcblk2p1
mkdir -p "$D/loop0"; ln -s "$D/loop0" "$SYS_BLOCK/loop0"	# a loop device: no MMC type at all

# The function under test, taken from the script itself (it ends in a dispatch that needs $1).
eval "$(sed -n '/^emmc() {$/,/^}$/p' "$CARDS")"
declare -F emmc >/dev/null || { echo "FAIL - no emmc() in $CARDS"; exit 1; }
export SYS_BLOCK

for n in mmcblk0 mmcblk0p1 mmcblk0p10 mmcblk0boot0 mmcblk0rpmb; do check "$n is the eMMC" "emmc $n"; done
for n in mmcblk1 mmcblk1p1 mmcblk1p15 mmcblk2 mmcblk2p1 loop0 nosuch; do check "$n is not the eMMC" "! emmc $n"; done
check "sd2() skips the eMMC" "sed -n '/^sd2() {/,/^}/p' '$CARDS' | grep -q 'emmc \"\${d##\*/}\" && continue'"
check "hotplug skips the eMMC" "sed -n '/^cards_hotplug() {/,/^}/p' '$CARDS' | grep -q 'emmc \"\$DEVNAME\" && return 0'"
check "the script parses (sh -n)" "sh -n '$CARDS'"
[ "$FAIL" = 0 ] && echo "all passed" || { echo "FAILED"; exit 1; }
