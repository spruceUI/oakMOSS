#!/usr/bin/env bash
# Bring a freshly unpacked Tina SDK to the state oakMOSS builds from.
#
#   scripts/apply-sdk-mods.sh [--check]
#
# Every change is listed in docs/sdk-mods.md. Originals of every edited file are
# kept beside it as *.orig, replaced package directories move to
# sdk/lichee/.oakmoss-orig/. The script is idempotent: a change that is already
# in place is skipped, and --check only reports.
#
# What is NOT done here (done per board by build.sh at build time): the rootfs
# overlay (rc.local, banner, /usr/magicx), the board defconfig, the device
# marker and the Zero 40 kernel object.
. "$(dirname "$0")/lib.sh"
need_sdk
CHECK=0; for a in "$@"; do case $a in --check) CHECK=1 ;; *) die "unknown option $a" ;; esac; done
P=$OAKMOSS_ROOT/sdk-patches
cd "$SDK_DIR" || die "cannot enter $SDK_DIR"
missing=0
note() { printf '  %-8s %s\n' "$1" "$2" >&2; }

# 1. Tree patches (rules.mk, kernel config, toolchain menu, package Makefiles).

# patch_targets <patch> : the b/ paths a patch writes to, one per line.
# awk rather than grep: the tree patches carry vendor sources whose non-ASCII
# comments make some grep builds (ugrep among them) call the file binary and
# print nothing at all, which silently emptied this list and skipped every
# backup. The b/ path may also carry a tab and a timestamp, which word-splitting
# turned into extra bogus filenames.
patch_targets() {
    awk '/^\+\+\+ b\//{ sub(/^\+\+\+ b\//, ""); sub(/\t.*$/, ""); print }' "$1"
}

# patch_effect_present <patch> : true when every line the patch adds is already
# in its target file. The unpacked SDK tree may already carry an equivalent change
# from other work against the same tree, written under different comments, so a
# change can be genuinely in place while `patch -R` still refuses it for want of
# matching context. Comments and blank lines are ignored precisely because that is
# where two versions of the same fix differ; a patch that adds nothing but comments
# is not eligible for this test and falls through to being applied.
patch_effect_present() {
    local patch=$1 f line added=0
    while IFS= read -r f; do
        [ -f "$f" ] || return 1
    done < <(patch_targets "$patch")
    while IFS=$'\t' read -r f line; do
        added=$((added + 1))
        grep -a -qF -- "$line" "$f" 2>/dev/null || return 1
    done < <(awk '
        /^\+\+\+ b\//     { file = $0; sub(/^\+\+\+ b\//, "", file); sub(/\t.*$/, "", file); next }
        /^\+\+\+/          { next }
        /^\+/ {
            line = substr($0, 2)
            gsub(/^[ \t]+|[ \t]+$/, "", line)
            if (line == "" || line ~ /^[#\/\*]/) next
            print file "\t" line
        }' "$patch")
    [ "$added" -gt 0 ]
}

for patch in "$P"/tree/*.patch; do
    name=$(basename "$patch" .patch)
    if patch -p1 -R --dry-run -s -f < "$patch" >/dev/null 2>&1; then note applied "$name"; continue; fi
    if patch_effect_present "$patch"; then note "in-tree" "$name"; continue; fi
    if [ "$CHECK" = 1 ]; then note MISSING "$name"; missing=1; continue; fi
    while IFS= read -r f; do
        [ -f "$f.orig" ] || cp -a "$f" "$f.orig"; chmod u+w "$f"
    done < <(patch_targets "$patch")
    # --no-backup-if-mismatch: GNU patch otherwise saves the file it could not match as
    # <file>.orig - the very name the loop above keeps the pristine SDK copy under - so
    # one failed attempt overwrites the pristine backup (config-4.9.orig, 2026-09-18).
    patch -p1 -N -s -f --no-backup-if-mismatch < "$patch" || die "patch $name did not apply cleanly"
    note patched "$name"
done

# 2. Package patches (OpenWrt quilt style: dropped into package/<pkg>/patches/).

# patch_body <file> : the diff itself, without the prose header above it. These
# quilt patches explain themselves in a paragraph before the first ---, and the
# same fix may already be present with a different provenance line in that
# paragraph. Comparing whole files called those MISSING and would have
# overwritten equivalent copies with byte-identical diffs under a different
# comment; comparing bodies asks the question that matters.
patch_body() {
    awk 'f || /^(--- |diff |Index:)/ { f = 1; print }' "$1"
}

while read -r pkgdir sub; do
    for src in "$P"/package-patches/"$sub"/*.patch; do
        dst=$pkgdir/patches/$(basename "$src")
        if [ -f "$dst" ] && cmp -s "$src" "$dst"; then note present "$dst"; continue; fi
        # The same fix may already be there under another name: an equivalent libubox
        # -Werror patch can already sit in this directory, and installing ours beside
        # it made quilt apply the change twice and fail the build outright. Match on
        # the diff body across the whole directory, not on the filename.
        same=""
        for cand in "$pkgdir"/patches/*.patch; do
            [ -f "$cand" ] || continue
            if diff -q <(patch_body "$src") <(patch_body "$cand") >/dev/null 2>&1; then
                same=$cand; break
            fi
        done
        if [ -n "$same" ]; then note "same-fix" "$same"; continue; fi
        if [ "$CHECK" = 1 ]; then note MISSING "$dst"; missing=1; continue; fi
        mkdir -p "$pkgdir/patches"; cp -a "$src" "$dst"; note added "$dst"
    done
done <<'EOF'
package/utils/busybox busybox
package/utils/bluez bluez
package/utils/e2fsprogs e2fsprogs
package/libs/libubox libubox
package/allwinner/stress-ng stress-ng
EOF

# 3. ncurses 5.9 -> 6.2 (OpenWrt 21.02 port). The old directory must leave
#    package/ entirely or the SDK keeps building 5.9.
if grep -q '^PKG_VERSION:=6.2' package/libs/ncurses/Makefile 2>/dev/null; then note present "package/libs/ncurses (6.2)"
elif [ "$CHECK" = 1 ]; then note MISSING "package/libs/ncurses 6.2"; missing=1
else
    mkdir -p .oakmoss-orig
    [ -d .oakmoss-orig/ncurses-5.9 ] || mv package/libs/ncurses .oakmoss-orig/ncurses-5.9
    rm -rf package/libs/ncurses; cp -a "$P/ncurses-6.2" package/libs/ncurses; note replaced "package/libs/ncurses -> 6.2"
fi

# 4. GCC 7.5.0 patch set for the phase-2 fallback toolchain (menu option added by tree patch 030).
if [ -d toolchain/gcc/patches/7.5.0 ] && diff -rq "$P/gcc-7.5.0-patches" toolchain/gcc/patches/7.5.0 >/dev/null 2>&1; then note present "toolchain/gcc/patches/7.5.0"
elif [ "$CHECK" = 1 ]; then note MISSING "toolchain/gcc/patches/7.5.0"; missing=1
else mkdir -p toolchain/gcc/patches/7.5.0; cp -a "$P"/gcc-7.5.0-patches/. toolchain/gcc/patches/7.5.0/; note added "toolchain/gcc/patches/7.5.0"
fi

# 5. Source tarballs the SDK cannot download any more.
for t in "$NCURSES_TARBALL" "$GCC750_TARBALL" "$BINUTILS228_TARBALL"; do
    if [ -f "dl/$t" ]; then note present "dl/$t"
    elif [ -f "$INPUTS_DIR/$t" ]; then [ "$CHECK" = 1 ] || { cp -a "$INPUTS_DIR/$t" "dl/$t"; note staged "dl/$t"; }
    elif [ "$t" = "$NCURSES_TARBALL" ]; then note MISSING "dl/$t (scripts/fetch-inputs.sh)"; missing=1
    fi
done

# 6. Backups build.sh relies on (so the overlay and the board object can be swapped back and forth).
enc=lichee/linux-4.9/drivers/char/sunxi_encrypt/encrypt
if [ ! -f "$enc.zero28" ]; then
    [ "$(md5_of "$enc")" = "$SDK_ENCRYPT_ZERO28_MD5" ] || die "$enc is not the SDK's original object (md5 $(md5_of "$enc"))"
    [ "$CHECK" = 1 ] || { cp -a "$enc" "$enc.zero28"; note backup "$enc.zero28"; }
fi
for f in target/allwinner/a133-aw3/defconfig target/allwinner/a133-aw3/base-files/etc/rc.local \
         package/base-files/files/etc/banner target/allwinner/generic/boot-resource/boot-resource/bootlogo.bmp; do
    [ -f "$f.orig" ] || [ "$CHECK" = 1 ] || { cp -a "$f" "$f.orig"; note backup "$f.orig"; }
done

if [ "$CHECK" = 1 ]; then
    [ "$missing" = 0 ] && log "all SDK modifications are in place" || die "SDK modifications missing (run without --check)"
else
    { echo "oakmoss_mods_version=7"; echo "applied=$(date -u +%FT%TZ)"; echo "oakmoss=$(oakmoss_version)"; } > .oakmoss-mods
    log "SDK modifications applied; ledger: docs/sdk-mods.md"
fi
