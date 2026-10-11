#!/usr/bin/env bash
# Fetch the userland lanes' sources: each URL in inputs/userland/urls.txt that $SRC_DIR (default
# $INPUTS_DIR/userland) lacks is downloaded and checked against inputs/userland/SHA256SUMS.
#
#   scripts/fetch-userland.sh [--print-sums]
#
# A line is "<url>" or "<url>  (saved as <name>)". --print-sums also fetches lines that have no
# checksum yet and prints one for each, for adding a source; without it such a line is an error.
. "$(dirname "$0")/lib.sh"
LIST=$OAKMOSS_ROOT/inputs/userland
SRC_DIR=${SRC_DIR:-$INPUTS_DIR/userland}
PRINT=0
for a in "$@"; do case $a in --print-sums) PRINT=1 ;; *) die "unknown option $a" ;; esac; done
mkdir -p "$SRC_DIR"
while read -r url rest; do
    case $url in ''|'#'*) continue ;; esac
    name=$(printf '%s' "$rest" | sed -n 's/.*(saved as \([^)]*\)).*/\1/p')
    name=${name:-${url##*/}}
    sum=$(awk -v f="$name" '$2 == f { print $1 }' "$LIST/SHA256SUMS")
    if [ -n "$sum" ]; then fetch "$url" "$SRC_DIR/$name" "$sum"; continue; fi
    [ "$PRINT" = 1 ] || die "$name is in urls.txt but not in SHA256SUMS"
    fetch "$url" "$SRC_DIR/$name"
    printf '%s  %s\n' "$(sha256_of "$SRC_DIR/$name")" "$name"
done < "$LIST/urls.txt"
log "userland sources ready in $SRC_DIR"
