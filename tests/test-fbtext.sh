#!/usr/bin/env bash
# Host-side test for src/fbtext.c (oakmoss-fbtext), built with the host's cc into a file screen
# (-o, no framebuffer): the title row, wrapping, scrolling (the screen shows the newest lines,
# exactly as those lines alone would), and a followed file's new lines (-f). Linux only: the
# tool includes <linux/fb.h>. PNG=<dir> also saves each screen as a PNG (needs Pillow).
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
[ "$(uname -s)" = Linux ] || { echo "skip - Linux only (linux/fb.h)"; exit 0; }
FAIL=0
T=$(mktemp -d "${TMPDIR:-/tmp}/oakmoss-test-fbtext.XXXX"); trap 'rm -rf "$T"' EXIT
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; FAIL=1; fi; }
cc -O2 -Wall -Wextra -Werror -o "$T/fbtext" "$HERE/../src/fbtext.c"
G=640x480; W=640; H=480

# rows <file>: the 16-pixel text rows that hold anything but the background, as row numbers
rows() { python3 -I - "$1" "$W" "$H" <<'PY'
import sys
d = open(sys.argv[1], 'rb').read(); w, h = int(sys.argv[2]), int(sys.argv[3]); stride = w * 4
bg = {0: d[0:4]}
out = []
for r in range(h // 16):
    band = d[r * 16 * stride:(r + 1) * 16 * stride]
    ref = band[0:4]
    if any(band[i:i + 4] != ref for i in range(0, len(band), 4)):
        out.append(str(r))
print(' '.join(out))
PY
}
png() { [ -z "${PNG:-}" ] || python3 -I -c "import sys; from PIL import Image; b, g, r, a = Image.frombytes('RGBA', ($W, $H), open(sys.argv[1], 'rb').read()).split(); Image.merge('RGB', (r, g, b)).save(sys.argv[2])" "$1" "$PNG/$2.png"; }

printf 'first line\nsecond line\n' | "$T/fbtext" -t "oakMOSS debug boot: test" -o "$T/a.raw" -g $G
check "screen size is W x H x 4" "[ \$(stat -c%s '$T/a.raw') = $((W * H * 4)) ]"
check "title and two lines on rows 0-2" "[ \"\$(rows '$T/a.raw')\" = '0 1 2' ]"
png "$T/a.raw" two-lines

printf '%0100d\n' 0 | "$T/fbtext" -t t -o "$T/b.raw" -g $G
check "a 100-character line wraps onto two 80-column rows" "[ \"\$(rows '$T/b.raw')\" = '0 1 2' ]"

seq 1 100 | sed 's/^/line /' | "$T/fbtext" -t t -o "$T/c.raw" -g $G
seq 72 100 | sed 's/^/line /' | "$T/fbtext" -t t -o "$T/d.raw" -g $G
check "100 lines: the newest 29 fill rows 1-29" "[ \"\$(rows '$T/c.raw' | wc -w)\" = 30 ]"
check "100 lines: the same screen as the last 29 alone" "cmp -s '$T/c.raw' '$T/d.raw'"
png "$T/c.raw" scrolled

printf 'tab\there, bytes \001\377 and ~\n' | "$T/fbtext" -t t -o "$T/e.raw" -g $G
check "tabs and bytes outside ASCII still draw one row" "[ \"\$(rows '$T/e.raw')\" = '0 1' ]"

# -f: lines added after the start show; what the file held before stays off.
printf 'old line\n' > "$T/log"
"$T/fbtext" -t t -f "$T/log" -o "$T/f.raw" -g $G & pid=$!
sleep 0.5; printf 'new one\nnew two\n' >> "$T/log"; sleep 0.7; kill $pid; wait $pid 2>/dev/null || true
printf 'new one\nnew two\n' | "$T/fbtext" -t t -o "$T/g.raw" -g $G
check "-f: only the lines added after the start" "cmp -s '$T/f.raw' '$T/g.raw'"

# -f on a file that appears later: all of it.
"$T/fbtext" -t t -f "$T/late" -o "$T/h.raw" -g $G & pid=$!
sleep 0.5; printf 'late one\n' > "$T/late"; sleep 0.7; kill $pid; wait $pid 2>/dev/null || true
printf 'late one\n' | "$T/fbtext" -t t -o "$T/i.raw" -g $G
check "-f: a file created later is read from its start" "cmp -s '$T/h.raw' '$T/i.raw'"

exit $FAIL
