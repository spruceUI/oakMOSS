#!/usr/bin/env bash
# Keep sdk-patches/debug/kdebug-mark.patch and the SDK tree in step.
#
#   scripts/kdebug.sh check            where the patch stands on the tree: applied / absent / mismatch
#   scripts/kdebug.sh init             record the pristine copy of every file the (applied) patch touches
#   scripts/kdebug.sh stash <file>...  record a file's pristine copy BEFORE its first debug edit
#   scripts/kdebug.sh regen            rebuild the patch from the pristine copies and the tree
#   scripts/kdebug.sh build <board>    check, then KDEBUG_MARK=1 build.sh image <board> from the oakMOSS root
#   scripts/kdebug.sh revert           take the (exactly applied) patch back out of the tree
#
# Files are SDK-relative (lichee/linux-4.9/...). Pristine copies live in
# $SDK_DIR/.oakmoss-kdebug/pristine/ and never change once recorded; a file that does not exist
# yet is recorded as new. Workflow: stash a file before its first edit, edit, regen, build.
# regen keeps the previous patch as kdebug-mark.patch.bak and only installs the new one after
# checking that it reverse-applies on the tree exactly; build refuses a tree the patch does not
# describe. Both exist because hand-regenerated sections drifted from the tree twice on
# 2026-09-29, and a forced apply then duplicated hunks in seven kernel files.
. "$(dirname "$0")/lib.sh"
need_sdk
PATCH=$OAKMOSS_ROOT/sdk-patches/debug/kdebug-mark.patch
STASH=$SDK_DIR/.oakmoss-kdebug/pristine

# section <rel> : this file's section of the patch (empty when the patch does not touch it)
section() {
    python3 - "$PATCH" "$1" <<'EOF'
import re, sys
patch, rel = sys.argv[1:3]
for part in re.split(r'(?m)^(?=--- )', open(patch, encoding='latin-1').read()):
    lines = part.split('\n', 2)
    if len(lines) > 1 and lines[1].split('\t')[0] == f'+++ b/{rel}':
        sys.stdout.write(part)
EOF
}

# patch_files : the files the patch touches, in patch order
patch_files() { awk '/^\+\+\+ b\//{ sub(/^\+\+\+ b\//, ""); sub(/\t.*$/, ""); print }' "$PATCH"; }

# record <rel> : store the pristine copy of <rel> unless there is one already. A file the
# applied patch touches is restored from the tree by reversing its section on a copy.
record() {
    local rel=$1 tmp sec
    [ -e "$STASH/$rel" ] || [ -e "$STASH/$rel.new-file" ] && return 0
    mkdir -p "$(dirname "$STASH/$rel")"
    sec=$(section "$rel")
    if [ -n "$sec" ]; then
        [ "$(kdebug_patch_state "$PATCH")" = applied ] || die "$rel is in the patch but the patch is not applied cleanly (kdebug.sh check)"
        tmp=$(mktemp -d)
        mkdir -p "$tmp/$(dirname "$rel")"
        [ -e "$SDK_DIR/$rel" ] && cp -p "$SDK_DIR/$rel" "$tmp/$rel"
        printf '%s\n' "$sec" | ( cd "$tmp" && patch -p1 -R -s -F0 --no-backup-if-mismatch ) || { rm -rf "${tmp:?}"; die "cannot reverse the section of $rel"; }
        if [ -e "$tmp/$rel" ]; then cp -p "$tmp/$rel" "$STASH/$rel"; else : > "$STASH/$rel.new-file"; fi
        rm -rf "${tmp:?}"
    elif [ -e "$SDK_DIR/$rel" ]; then
        cp -p "$SDK_DIR/$rel" "$STASH/$rel"
    else
        : > "$STASH/$rel.new-file"
    fi
    log "pristine copy recorded: $rel"
}

# exact : for every file the patch touches, pristine copy + its section must equal the tree
# byte for byte - catches edits patch's context check cannot see (far from any hunk).
exact() {
    local rel tmp bad=0 sec
    [ -d "$STASH" ] || { warn "no pristine copies yet (kdebug.sh init): exact check skipped"; return 0; }
    for rel in $(patch_files); do
        tmp=$(mktemp -d)
        mkdir -p "$tmp/$(dirname "$rel")"
        if [ -e "$STASH/$rel" ]; then cp -p "$STASH/$rel" "$tmp/$rel"
        elif [ ! -e "$STASH/$rel.new-file" ]; then warn "no pristine copy of $rel"; bad=1; rm -rf "${tmp:?}"; continue; fi
        sec=$(section "$rel")
        if ! printf '%s\n' "$sec" | ( cd "$tmp" && patch -p1 -s -F0 --no-backup-if-mismatch >/dev/null 2>&1 ) ||
           ! cmp -s "$tmp/$rel" "$SDK_DIR/$rel"; then
            warn "tree differs from pristine + patch: $rel"; bad=1
        fi
        rm -rf "${tmp:?}"
    done
    return $bad
}

cmd_regen() {
    local out files rel n=0
    out=$(mktemp)
    # patch order first, then anything stashed since
    files=$( { patch_files; ( cd "$STASH" && find . -type f | sed 's#^\./##; s#\.new-file$##' | sort ); } | awk '!seen[$0]++')
    for rel in $files; do
        if [ -e "$STASH/$rel.new-file" ]; then
            [ -e "$SDK_DIR/$rel" ] || continue
            diff -u /dev/null "$SDK_DIR/$rel" | sed "1s|.*|--- /dev/null|; 2s|.*|+++ b/$rel|" >> "$out" || true
        elif [ -e "$STASH/$rel" ]; then
            diff -u "$STASH/$rel" "$SDK_DIR/$rel" | sed "1s|.*|--- a/$rel|; 2s|.*|+++ b/$rel|" >> "$out" || true
        else
            die "$rel is in the patch but has no pristine copy (kdebug.sh init)"
        fi
    done
    n=$(grep -c '^+++ b/' "$out" || true)
    ( cd "$SDK_DIR" && patch -p1 -R --dry-run -s -F0 < "$out" >/dev/null 2>&1 ) || { rm -f "$out"; die "the regenerated patch does not reverse-apply on the tree - nothing written"; }
    cp -p "$PATCH" "$PATCH.bak"
    cp "$out" "$PATCH"; rm -f "$out"
    log "kdebug-mark.patch regenerated: $n files, $(grep -c '^@@' "$PATCH") hunks (previous: $PATCH.bak)"
}

case ${1:-} in
    check)
        st=$(kdebug_patch_state "$PATCH")
        if [ "$st" = applied ] && ! exact; then st=mismatch; fi
        echo "$st"; [ "$st" != mismatch ] ;;
    init)
        [ "$(kdebug_patch_state "$PATCH")" = applied ] || die "init needs the patch applied exactly (kdebug.sh check)"
        for rel in $(patch_files); do record "$rel"; done ;;
    stash)
        shift; [ $# -gt 0 ] || die "stash: which files?"
        for rel in "$@"; do record "${rel#./}"; done ;;
    regen)
        cmd_regen ;;
    revert)
        "$0" check >/dev/null || die "the patch does not match the tree - nothing reverted"
        [ "$(kdebug_patch_state "$PATCH")" = applied ] || { log "debug marker not applied"; exit 0; }
        ( cd "$SDK_DIR" && patch -p1 -R -s -F0 --no-backup-if-mismatch < "$PATCH" ) || die "revert failed"
        log "debug marker reverted" ;;
    build)
        [ -n "${2:-}" ] || die "build: which board?"
        "$0" check >/dev/null || die "the patch does not match the tree - kdebug.sh regen first"
        cd "$OAKMOSS_ROOT" || die "cannot enter $OAKMOSS_ROOT"
        KDEBUG_MARK=1 exec "$OAKMOSS_ROOT/scripts/build.sh" image "$2" ;;
    *)
        sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
