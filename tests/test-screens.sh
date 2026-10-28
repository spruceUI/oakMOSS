#!/usr/bin/env bash
# Host-side test for the boot screens of overlay/usr/magicx/bin/charge-screen.sh (docs/boot-screens.md)
# against plain files: boot, frontend, reboot and poweroff draw their frame onto both pages of a
# two-page framebuffer and unblank it; a board without the boot screens and a debug-text boot get
# nothing drawn; the updating screen is unchanged. RUN="<shell>" runs the script under that shell
# (a rehearsal in a Linux VM: the unit's BusyBox ash, its applets first on PATH).
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CS=$HERE/../overlay/usr/magicx/bin/charge-screen.sh
FAIL=0
T=$(mktemp -d "${TMPDIR:-/tmp}/oakmoss-test-screens.XXXX"); trap 'rm -rf "$T"' EXIT
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; FAIL=1; fi; }

# A 4 x 2 framebuffer, two pages: rows of 16 bytes, virtual size 4,4. Each frame is 32 bytes of one letter.
mkdir -p "$T/frames" "$T/fbsys" "$T/bin"
# zcat as BusyBox's: gzip (macOS's zcat wants .Z files)
printf '#!/bin/sh\nexec gzip -dc "$@"\n' > "$T/bin/zcat"; chmod +x "$T/bin/zcat"; export PATH=$T/bin:$PATH
for f in loading boot-loading reboot poweroff updating; do
    printf '%032d' 0 | tr 0 "$(printf '%s' "$f" | cut -c1 | tr a-z A-Z)" | gzip -n > "$T/frames/$f.rgba.gz"
done
printf 'X%.0s' $(seq 32) | gzip -n > "$T/frames/boot-loading.rgba.gz"   # not B: boot-loading and nothing else
echo 4,4 > "$T/fbsys/virtual_size"; echo 16 > "$T/fbsys/stride"
export FRAMES=$T/frames FB=$T/fb FBSYS=$T/fbsys TEXT_FLAG=$T/debug-text

page() { dd if="$FB" bs=32 skip="$1" count=1 2>/dev/null; }
draw() { printf '%064d' 0 > "$FB"; echo 1 > "$FBSYS/blank"; echo none > "$FBSYS/pan"; ${RUN:-} "$CS" "$1"; }
want() { [ "$(page 0)" = "$(printf "$1%.0s" $(seq 32))" ] && [ "$(page 1)" = "$(page 0)" ] && [ "$(cat "$FBSYS/blank")" = 0 ] && [ "$(cat "$FBSYS/pan")" = 0,0 ]; }
blank() { [ "$(cat "$FB")" = "$(printf '%064d' 0)" ]; }

draw boot;     check "boot: boot-loading on both pages, unblanked, panned to 0,0" "want X"
draw frontend; check "frontend: the loading frame" "want L"
draw reboot;   check "reboot: the reboot frame" "want R"
draw poweroff; check "poweroff: the poweroff frame" "want P"
draw updating; check "updating: unchanged" "want U"

: > "$TEXT_FLAG"
for m in boot frontend reboot poweroff; do draw "$m"; check "debug-text boot, $m: nothing drawn" blank; done
draw updating; check "debug-text boot, updating: still drawn" "want U"
rm -f "$TEXT_FLAG"

rm "$T/frames/boot-loading.rgba.gz"
for m in boot frontend reboot poweroff; do draw "$m"; check "board without the boot screens, $m: nothing drawn" blank; done

exit $FAIL
