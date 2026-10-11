#!/usr/bin/env bash
# Host-side test for lib.sh's apply_mods_stamp: a no-op apply-sdk-mods.sh run (nothing
# patched/copied/moved/staged, version already current) must leave .oakmoss-mods' applied=
# byte-identical - otherwise build.sh's check_shipped_modules would refuse every module on a
# clean tree after a harmless re-run. A real change or version bump must move it and wipe the
# kernel build tree.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
FAIL=0
# The checkout's own level, so a mods round never has to edit this test
CUR=$(sed -n 's/^OAKMOSS_MODS_VERSION=//p' "$HERE/../scripts/lib.sh")
[ -n "$CUR" ] || { echo "FAIL - no OAKMOSS_MODS_VERSION in scripts/lib.sh"; exit 1; }

make_fake_sdk() {  # make_fake_sdk <dir> <recorded-version> <applied-iso>
    local dir=$1 version=$2 applied=$3
    rm -rf "$dir"; mkdir -p "$dir/out/a133-aw3/compile_dir/target/linux-a133-aw3"
    touch "$dir/out/a133-aw3/compile_dir/target/linux-a133-aw3/vmlinux"   # wipe marker
    { echo "oakmoss_mods_version=$version"; echo "applied=$applied"; echo "oakmoss=test"; } > "$dir/.oakmoss-mods"
}

run_stamp() {  # run_stamp <sdk-dir> <changed>: stubs wipe_kernel_build_tree (real one needs
               # docker) with a marker-file remover, to test apply_mods_stamp's own decision.
    SDK_DIR=$1 bash -c '. "'"$HERE"'/../scripts/lib.sh"
        wipe_kernel_build_tree() { rm -f "$SDK_DIR/out/a133-aw3/compile_dir/target/linux-a133-aw3/vmlinux"; }
        apply_mods_stamp "'"$2"'"'
}

check_eq() { [ "$2" = "$3" ] && echo "ok   - $1" || { echo "FAIL - $1: expected '$3', got '$2'"; FAIL=1; }; }
check_wiped() {  # check_wiped <name> <sdk-dir> <expect: 0=gone 1=present>
    local dir=$2 present=0
    [ -e "$dir/out/a133-aw3/compile_dir/target/linux-a133-aw3/vmlinux" ] && present=1
    if [ "$present" = "$3" ]; then echo "ok   - $1 (present=$present)"
    else echo "FAIL - $1: expected present=$3, got $present"; FAIL=1
    fi
}

# No-op: already at the checkout's level, nothing changed this run -> applied= untouched, tree not wiped.
SDK=/tmp/oakmoss-test-stamp-noop
make_fake_sdk "$SDK" "$CUR" "2026-10-11T03:36:17Z"
run_stamp "$SDK" 0 >/tmp/oakmoss-test-stamp.log 2>&1
check_eq "no-op: applied= unchanged" "$(sed -n 's/^applied=//p' "$SDK/.oakmoss-mods")" "2026-10-11T03:36:17Z"
check_wiped "no-op: kernel tree not wiped" "$SDK" 1

# Changed=1 at the same version -> applied= moves, tree wiped.
SDK=/tmp/oakmoss-test-stamp-changed
make_fake_sdk "$SDK" "$CUR" "2026-10-11T03:36:17Z"
run_stamp "$SDK" 1 >/tmp/oakmoss-test-stamp.log 2>&1
got=$(sed -n 's/^applied=//p' "$SDK/.oakmoss-mods")
[ "$got" != "2026-10-11T03:36:17Z" ] && echo "ok   - changed: applied= moved ($got)" || { echo "FAIL - changed: applied= did not move"; FAIL=1; }
check_wiped "changed: kernel tree wiped" "$SDK" 0

# A real version bump, nothing else flagged changed -> still moves and wipes.
SDK=/tmp/oakmoss-test-stamp-bump
make_fake_sdk "$SDK" "$((CUR - 1))" "2026-10-09T05:32:21Z"
run_stamp "$SDK" 0 >/tmp/oakmoss-test-stamp.log 2>&1
got=$(sed -n 's/^applied=//p' "$SDK/.oakmoss-mods")
[ "$got" != "2026-10-09T05:32:21Z" ] && echo "ok   - version bump: applied= moved ($got)" || { echo "FAIL - version bump: applied= did not move"; FAIL=1; }
check_wiped "version bump: kernel tree wiped" "$SDK" 0

rm -rf /tmp/oakmoss-test-stamp-noop /tmp/oakmoss-test-stamp-changed /tmp/oakmoss-test-stamp-bump /tmp/oakmoss-test-stamp.log
[ "$FAIL" = 0 ] && echo "all tests passed" || { echo "TESTS FAILED"; exit 1; }
