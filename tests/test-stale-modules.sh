#!/usr/bin/env bash
# Host-side test for lib.sh's check_shipped_modules (scripts/build.sh's pack-time gate
# against a kernel module the current build did not actually produce).
#
#   tests/test-stale-modules.sh
#
# Builds a throwaway fake SDK tree per case (never touches a real SDK_DIR) and sources
# lib.sh against it. No docker, no network.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
FAIL=0

# make_fake_sdk <dir> <applied-iso> <ko-mtime-touch-spec>: a minimal tree with one module
# (foo.ko) staged both where build.sh ships it from and where its true link time survives.
make_fake_sdk() {
    local dir=$1 applied=$2 ko_touch=$3
    rm -rf "$dir"; mkdir -p "$dir"
    local rootfs=$dir/out/a133-aw3/compile_dir/target/rootfs/lib/modules/4.9.191
    local stage=$dir/out/a133-aw3/compile_dir/target/linux-a133-aw3/packages/ipkg-sunxi/kmod-foo/lib/modules/4.9.191
    mkdir -p "$rootfs" "$stage"
    printf 'fake module\n' > "$stage/foo.ko"
    touch -d "$ko_touch" "$stage/foo.ko"
    cp -a "$stage/foo.ko" "$rootfs/foo.ko"
    touch "$rootfs/foo.ko"   # the real install step re-stamps this copy; mtime here must not matter
    { echo "oakmoss_mods_version=19"; echo "applied=$applied"; echo "oakmoss=test"; } > "$dir/.oakmoss-mods"
}

check() {  # check <name> <expect: 0|1> <sdk-dir>
    local name=$1 expect=$2 sdk=$3 rc=0
    SDK_DIR=$sdk bash -c '. "'"$HERE"'/../scripts/lib.sh"; check_shipped_modules fakeboard' >/tmp/oakmoss-test-$$.log 2>&1 || rc=$?
    if [ "$rc" = "$expect" ]; then echo "ok   - $name (rc=$rc)"
    else echo "FAIL - $name: expected rc=$expect, got rc=$rc"; cat /tmp/oakmoss-test-$$.log; FAIL=1
    fi
    rm -f /tmp/oakmoss-test-$$.log
}

# Negative: the module was linked BEFORE the mods were last applied -> refused (rc 1).
make_fake_sdk /tmp/oakmoss-test-stale "2026-10-11T03:36:17Z" "2026-10-08 18:16:35"
check "stale module refused" 1 /tmp/oakmoss-test-stale

# Positive: the module was linked AFTER the mods were last applied -> accepted (rc 0).
make_fake_sdk /tmp/oakmoss-test-fresh "2026-10-11T03:36:17Z" "2026-10-11 03:40:00"
check "fresh module accepted" 0 /tmp/oakmoss-test-fresh

rm -rf /tmp/oakmoss-test-stale /tmp/oakmoss-test-fresh
[ "$FAIL" = 0 ] && echo "all tests passed" || { echo "TESTS FAILED"; exit 1; }
