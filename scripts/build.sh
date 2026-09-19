#!/usr/bin/env bash
# Build the SD1 base image for a MagicX A133P board from the prepared Tina SDK.
#
#   scripts/build.sh ext                 full userland build on Arm GNU 13.3 (default toolchain)
#   scripts/build.sh cont                resume the current build without wiping anything
#   scripts/build.sh image <board>       overlay -> add-rootfs-demo -> pack -> OpenixCard -> builds/
#   scripts/build.sh all [board ...]     ext, then image for zero28 and zero40 (or the boards given)
#   scripts/build.sh phase1 | phase2     Moss-faithful fallback on the vendor/from-source toolchain
#                                        (TOOLCHAIN=vendor; see docs/toolchain.md)
#   scripts/build.sh overlay <board>     only stage the board's overlay + kernel object into the SDK tree
#
# Env: JOBS, TOOLCHAIN (armgnu13|vendor), EXT_CONFIG (configs/ext-armgnu13.config),
#      PHASE2_CONFIG (phase2-gcc750.config), OPENIXCARD_BIN, ZERO40_ENCRYPT_OBJ,
#      COMPRESS=1 (also write an .img.xz), OAKMOSS_WORK / BUILDS_DIR (see lib.sh),
#      KDEBUG_FBCON=1 (kernel console on the panel; debug cards only, see apply_overlay),
#      KDEBUG_MARK=1 (initcall progress marker for oakmoss_mark=; debug cards only).
# Everything runs inside the container except OpenixCard, which runs on the host.
. "$(dirname "$0")/lib.sh"
need_sdk; need_mods
STEP=${1:?step: ext|cont|image|all|phase1|phase2}; shift || true
mkdir -p "$BUILDS_DIR/logs"
RUN=$OAKMOSS_ROOT/scripts/run-in-sdk.sh
LUNCH='source build/envsetup.sh; lunch a133_aw3-tina;'
CFGS=/home/builder/oakmoss/configs
ENC=$SDK_DIR/lichee/linux-4.9/drivers/char/sunxi_encrypt

# install_config <name>: Tina's build/toplevel.mk copies the board defconfig over
# .config on EVERY make when the variant is tina, so the config must live at
# target/allwinner/a133-aw3/defconfig (docs/sdk-mods.md, "config gotcha").
install_config() { echo "cp $CFGS/$1 target/allwinner/a133-aw3/defconfig; cp target/allwinner/a133-aw3/defconfig .config;"; }

# zero40_encrypt_obj: where the Zero 40 kernel object comes from (proprietary, not in git).
zero40_encrypt_obj() {
    local obj
    if [ -n "${ZERO40_ENCRYPT_OBJ:-}" ]; then obj=$ZERO40_ENCRYPT_OBJ
    elif [ -f "$OAKMOSS_ROOT/boards/zero40/encrypt" ]; then obj=$OAKMOSS_ROOT/boards/zero40/encrypt
    elif [ -f "$INPUTS_DIR/$ZERO40_LICHEE_ZIP" ]; then
        obj=$BUILDS_DIR/.zero40-encrypt
        unzip -p "$INPUTS_DIR/$ZERO40_LICHEE_ZIP" "$ZERO40_ENCRYPT_PATH" > "$obj"
    else die "no Zero 40 encrypt object: put $ZERO40_LICHEE_ZIP in $INPUTS_DIR (inputs/README.md) or set ZERO40_ENCRYPT_OBJ"; fi
    [ "$(md5_of "$obj")" = "$ZERO40_ENCRYPT_MD5" ] || die "$obj md5 $(md5_of "$obj") != $ZERO40_ENCRYPT_MD5"
    echo "$obj"
}

# encrypt_stub_obj: sdk-patches/sunxi_encrypt/encrypt_stub.c compiled by the kernel's
# own build (same compiler, flags and headers as the vendor objects), cached in
# $BUILDS_DIR. For boards with no matching MagicX object: theirs reboot the kernel
# when the board's security chip does not answer to their key.
encrypt_stub_obj() {
    local src=$OAKMOSS_ROOT/sdk-patches/sunxi_encrypt/encrypt_stub.c out=$BUILDS_DIR/encrypt-stub.o
    if [ ! -f "$out" ] || [ "$src" -nt "$out" ]; then
        cp -a "$src" "$ENC/encrypt_stub.c"
        "$OAKMOSS_ROOT/scripts/run-in-sdk.sh" 'cd lichee/linux-4.9 && make ARCH=arm64 CROSS_COMPILE=/home/builder/lichee/prebuilt/gcc/linux-x86/aarch64/toolchain-sunxi-glibc/toolchain/bin/aarch64-openwrt-linux-gnu- drivers/char/sunxi_encrypt/encrypt_stub.o 2>&1 | grep -vE "STAGING_DIR|^\s*$" | tail -3' >&2 || { rm -f "$ENC/encrypt_stub.c"; return 1; }
        [ -f "$ENC/encrypt_stub.o" ] || { rm -f "$ENC/encrypt_stub.c"; log "encrypt stub did not compile"; return 1; }
        mv "$ENC/encrypt_stub.o" "$out"; rm -f "$ENC/encrypt_stub.c" "$ENC/.encrypt_stub.o.cmd"
        log "encrypt stub compiled: $out" >&2
    fi
    printf '%s' "$out"
}

# apply_overlay <board>: rootfs overlay + device marker + board kernel object into the SDK tree.
apply_overlay() {
    local board=$1
    local ov=$OAKMOSS_ROOT/overlay bov=$OAKMOSS_ROOT/boards/$board/overlay
    [ -f "$OAKMOSS_ROOT/boards/$board/board.conf" ] || die "unknown board $board (boards/)"
    # shellcheck disable=SC1090
    . "$OAKMOSS_ROOT/boards/$board/board.conf"
    local logo=$SDK_DIR/target/allwinner/generic/boot-resource/boot-resource/bootlogo.bmp
    if [ -f "$ov/bootlogo.bmp" ]; then cp -a "$ov/bootlogo.bmp" "$logo"
    elif [ -f "$logo.orig" ]; then cp -a "$logo.orig" "$logo"; fi      # no logo in the overlay: the SDK's own
    cp -a "$ov/etc/rc.local" "$SDK_DIR/target/allwinner/a133-aw3/base-files/etc/rc.local"
    cp -a "$ov/etc/banner"   "$SDK_DIR/package/base-files/files/etc/banner"
    rm -rf "$SDK_DIR/package/add-rootfs-demo/usr" "$SDK_DIR/package/add-rootfs-demo/etc"
    cp -a "$ov/usr" "$SDK_DIR/package/add-rootfs-demo/usr"
    cp -a "$ov/etc" "$SDK_DIR/package/add-rootfs-demo/etc"
    [ -d "$bov" ] && cp -a "$bov/." "$SDK_DIR/package/add-rootfs-demo/"
    printf '%s\n' "$DEVICE_MARKER" > "$SDK_DIR/package/add-rootfs-demo/usr/magicx/device"
    chmod 0755 "$SDK_DIR/package/add-rootfs-demo/usr/magicx/bin/"*
    # Board device tree: boards/<board>/board.dts (generated by scripts/make-board-dts.py
    # from the board's stock tree: panel, pad, radio, battery) replaces the SDK's a133-aw3
    # board.dts, which is the Zero 28's and comes back for boards without their own.
    local dts=$SDK_DIR/device/config/chips/a133/configs/aw3/board.dts
    [ -f "$dts.orig" ] || cp -a "$dts" "$dts.orig"
    if [ -f "$OAKMOSS_ROOT/boards/$board/board.dts" ]; then
        cp -a "$OAKMOSS_ROOT/boards/$board/board.dts" "$dts"; log "board.dts: boards/$board/board.dts"
    else
        cp -a "$dts.orig" "$dts"
    fi

    # Board sys_config: boards/<board>/sys_config.fex, same dance. This is where the
    # U-Boot-visible power_sply node comes from (battery_exist, charge_mode), which
    # decides whether a board powered on by charger insertion boots straight through
    # or waits for the power key. Boards without their own file get the SDK's back.
    local sysc=$SDK_DIR/device/config/chips/a133/configs/aw3/sys_config.fex
    [ -f "$sysc.orig" ] || cp -a "$sysc" "$sysc.orig"
    if [ -f "$OAKMOSS_ROOT/boards/$board/sys_config.fex" ]; then
        cp -a "$OAKMOSS_ROOT/boards/$board/sys_config.fex" "$sysc"; log "sys_config.fex: boards/$board/sys_config.fex"
    else
        cp -a "$sysc.orig" "$sysc"
    fi
    # Kernel console on the panel: KDEBUG_FBCON=1 builds a kernel whose console is
    # the display, so a panic or oops before userland is readable on the device
    # itself. These boards expose no serial header on the lab units, so without it
    # an early failure leaves U-Boot's logo on screen and says nothing - which is
    # exactly how the XU20's reboot loop and the diagnostic cards both present.
    # Debug cards only: it replaces the boot logo with scrolling kernel text. The
    # else-branch puts it back, so a normal build after a debug one is unaffected.
    # This file is $(LINUX_KCONFIG_LIST) in build/kernel-build.mk, so editing it
    # invalidates the kernel's configure stamp and the kernel reconfigures itself.
    local kcfg=$SDK_DIR/device/config/chips/a133/configs/aw3/linux/config-4.9
    # Every symbol fbcon pulls in has to be answered here: the kernel is configured
    # through silentoldconfig with stdin redirected, so one unanswered NEW prompt
    # aborts the whole build. ROTATION is not optional decoration - the XU20's panel
    # is mounted upside down, so without it the debug text comes out inverted; with
    # it the card can pass fbcon=rotate:2 (EXTRA_BOOTARGS in make-own-kernel-stock.sh).
    # Both branches rewrite from whatever state the file is in rather than testing for
    # one expected state: a half-applied config (fbcon on but a sub-symbol missing) is
    # exactly what an aborted build leaves behind, and silently skipping the fix there
    # costs another full build to discover. FONTS/FONT_8x16 come with fbcon: it selects
    # FONT_SUPPORT, which opens the "select compiled-in fonts" prompt, and the stock
    # config answers neither because it has no console font at all.
    if [ "${KDEBUG_FBCON:-0}" = 1 ]; then
        sed -i -e '/^CONFIG_FRAMEBUFFER_CONSOLE_DETECT_PRIMARY=y$/d' \
               -e '/^CONFIG_FRAMEBUFFER_CONSOLE_ROTATION=y$/d' \
               -e '/^# CONFIG_FONTS is not set$/d' \
               -e '/^CONFIG_FONT_8x16=y$/d' \
               -e 's|^# CONFIG_FRAMEBUFFER_CONSOLE is not set$|CONFIG_FRAMEBUFFER_CONSOLE=y|' \
               -e 's|^CONFIG_FRAMEBUFFER_CONSOLE=y$|CONFIG_FRAMEBUFFER_CONSOLE=y\nCONFIG_FRAMEBUFFER_CONSOLE_DETECT_PRIMARY=y\nCONFIG_FRAMEBUFFER_CONSOLE_ROTATION=y\n# CONFIG_FONTS is not set\nCONFIG_FONT_8x16=y|' \
               "$kcfg"
        log "kernel config: CONFIG_FRAMEBUFFER_CONSOLE=y (KDEBUG_FBCON; the panel is the kernel console)"
    elif grep -q '^CONFIG_FRAMEBUFFER_CONSOLE=y' "$kcfg"; then
        sed -i '/^CONFIG_FRAMEBUFFER_CONSOLE_DETECT_PRIMARY=y$/d; /^CONFIG_FRAMEBUFFER_CONSOLE_ROTATION=y$/d; /^# CONFIG_FONTS is not set$/d; /^CONFIG_FONT_8x16=y$/d; s|^CONFIG_FRAMEBUFFER_CONSOLE=y|# CONFIG_FRAMEBUFFER_CONSOLE is not set|' "$kcfg"
        log "kernel config: CONFIG_FRAMEBUFFER_CONSOLE off again (no KDEBUG_FBCON)"
    fi
    # Initcall marker: KDEBUG_MARK=1 applies sdk-patches/debug/kdebug-mark.patch,
    # which lets a card pass oakmoss_mark=<phys> (an RTC general-purpose register) so
    # each initcall and the init hand-off stages write where the boot has got to; the
    # next boot's U-Boot reads it (make-own-kernel-stock.sh KMARK=1). Inert without the
    # boot argument, but still reverted when not asked for, like KDEBUG_FBCON.
    local kmark=$OAKMOSS_ROOT/sdk-patches/debug/kdebug-mark.patch
    if [ "${KDEBUG_MARK:-0}" = 1 ]; then
        if ( cd "$SDK_DIR" && patch -p1 -R --dry-run -s -f < "$kmark" >/dev/null 2>&1 ); then log "kernel: initcall marker already applied (KDEBUG_MARK)"
        else ( cd "$SDK_DIR" && patch -p1 -N -s -f --no-backup-if-mismatch < "$kmark" ) || die "KDEBUG_MARK: patch did not apply"; log "kernel: initcall marker applied (KDEBUG_MARK)"; fi
    elif ( cd "$SDK_DIR" && patch -p1 -R --dry-run -s -f < "$kmark" >/dev/null 2>&1 ); then
        ( cd "$SDK_DIR" && patch -p1 -R -s -f --no-backup-if-mismatch < "$kmark" ) || die "could not revert the initcall marker"; log "kernel: initcall marker reverted (no KDEBUG_MARK)"
    fi
    # Kernel object: the SDK's own for the Zero 28, MagicX's Zero 40 object otherwise.
    [ -f "$ENC/encrypt.zero28" ] || die "no $ENC/encrypt.zero28 backup (scripts/apply-sdk-mods.sh)"
    chmod u+w "$ENC/encrypt" 2>/dev/null || true
    local obj
    case $ENCRYPT_OBJ in
        sdk)     obj=$ENC/encrypt.zero28 ;;
        zero40)  obj=$(zero40_encrypt_obj) || exit 1 ;;
        stub)    obj=$(encrypt_stub_obj) || exit 1 ;;
        *) die "boards/$board/board.conf: ENCRYPT_OBJ must be sdk, zero40 or stub" ;;
    esac
    cp -a "$obj" "$ENC/encrypt"
    touch "$ENC/encrypt"
    # The kernel's build stamp does not track the prebuilt object: force the (incremental)
    # kernel relink whenever the object differs from the one last linked in.
    local want; want=$(md5_of "$ENC/encrypt")
    if [ "$(cat "$ENC/.linked-md5" 2>/dev/null)" != "$want" ]; then
        rm -f "$SDK_DIR/out/a133-aw3/compile_dir/target/linux-a133-aw3/linux-4.9.191/.built"
        printf '%s\n' "$want" > "$ENC/.linked-md5"
        log "kernel object changed ($board): the kernel will relink"
    fi
}

run_make() {  # run_make <label> <pre-commands>
    local label=$1 pre=$2 LOG
    LOG=$BUILDS_DIR/logs/$label-$(stamp).log
    if ! "$RUN" "$LUNCH $pre echo '=== $label make start' \$(date) TOOLCHAIN=$TOOLCHAIN; make -j$JOBS 2>&1; rc=\${PIPESTATUS[0]}; echo \"=== $label make exit \$rc \$(date)\"; exit \$rc" 2>&1 | tee "$LOG"; then
        die "$label failed (log: $LOG)"
    fi
}

case $STEP in
  ext)
    [ "$TOOLCHAIN" = armgnu13 ] || die "ext needs TOOLCHAIN=armgnu13"
    apply_overlay zero28
    CFG=${EXT_CONFIG:-ext-armgnu13.config}
    # Drop target objects from any earlier vendor-toolchain build; keep the kernel tree, host tools and dl cache.
    run_make ext "$(install_config "$CFG") rm -rf out/a133-aw3/staging_dir/target out/a133-aw3/packages out/a133-aw3/root.squashfs out/a133-aw3/rootfs.img; for d in out/a133-aw3/compile_dir/target/*; do case \$(basename \$d) in linux-a133-aw3|host|stamp) ;; *) rm -rf \$d ;; esac; done;" ;;
  cont)
    run_make cont "cp target/allwinner/a133-aw3/defconfig .config;" ;;
  overlay)
    apply_overlay "${1:?board: zero28|zero40|xu20}"; log "overlay for $1 staged in $SDK_DIR" ;;
  phase1)
    TOOLCHAIN=vendor; export TOOLCHAIN; apply_overlay zero28
    run_make phase1 "$(install_config phase1.config)" ;;
  phase2)
    TOOLCHAIN=vendor; export TOOLCHAIN; apply_overlay zero28
    run_make phase2 "$(install_config "${PHASE2_CONFIG:-phase2-gcc750.config}")" ;;
  image)
    BOARD=${1:?board: zero28|zero40|xu20}
    [ -x "$OPENIXCARD_BIN" ] || die "OpenixCard not found at $OPENIXCARD_BIN (scripts/build-openixcard.sh)"
    apply_overlay "$BOARD"
    ST=$(stamp); OUT=$BUILDS_DIR/$ST-$BOARD; mkdir -p "$OUT"; LOG=$BUILDS_DIR/logs/image-$BOARD-$ST.log
    # pack's output is checked: it reports a partition overflow ("dl file
    # boot-resource.fex size too large", "update_mbr failed") and still returns, and
    # the card was then built from the PREVIOUS pack's stale output (2026-09-18, a Zero 28
    # image with the old logo and the old hand-off). Its exit status and the word ERROR
    # are no use: a good pack prints ERROR lines too. A good pack ends with Dragon's
    # "image.cfg SUCCESS".
    if ! "$RUN" "$LUNCH echo '=== kernel+rootfs refresh' \$(date); make -j$JOBS 2>&1 | tail -40; [ \${PIPESTATUS[0]} = 0 ] || { echo '=== image: make FAILED'; exit 1; }; gzip -c .config > package/add-rootfs-demo/usr/magicx/tina_config.gz; add-rootfs-demo 2>&1 | tail -5; echo '=== pack' \$(date); pack 2>&1 | tee /tmp/oakmoss-pack.log | tail -25; if grep -q 'update_mbr failed\|size too large' /tmp/oakmoss-pack.log || ! grep -q 'Dragon execute image.cfg SUCCESS' /tmp/oakmoss-pack.log; then echo '=== image: pack FAILED'; exit 1; fi; ls -la out/a133-aw3/*.img" 2>&1 | tee "$LOG"; then
        die "image step failed (log: $LOG)"
    fi
    IMG=$(ls -t "$SDK_DIR"/out/a133-aw3/tina_a133-aw3_*.img | head -1)
    cp -a "$IMG" "$OUT/"; cp -a "$SDK_DIR/.config" "$OUT/tina.config"
    ( cd "$OUT" && LD_LIBRARY_PATH="${OPENIXCARD_LIBDIR:-}${OPENIXCARD_LIBDIR:+:}${LD_LIBRARY_PATH:-}" "$OPENIXCARD_BIN" -d "$(basename "$IMG")" 2>&1 | tail -15 ) | tee -a "$LOG"
    RAW=$OUT/$(basename "$IMG").dump.out/$(basename "$IMG")
    [ -f "$RAW" ] || die "OpenixCard produced no raw image"
    FINAL=$OUT/oakmoss-$BOARD-$ST-sd1.img
    cp -a "$RAW" "$FINAL"
    ROOTFS=$SDK_DIR/out/a133-aw3/compile_dir/target/rootfs
    {
      echo "device=$BOARD"; echo "device_marker=$DEVICE_MARKER"; echo "built=$ST"; echo "oakmoss=$(oakmoss_version)"
      echo "sdk=mplus_a133_tina_v1.0 (Linux_SDK.zip) board a133-aw3, kernel 4.9.191, u-boot 2018"
      echo "sdk_tarball_md5=$(grep -m1 tarball_md5 "$SDK_DIR/.oakmoss-sdk" 2>/dev/null | cut -d= -f2)"
      echo "toolchain_mode=$TOOLCHAIN"
      case $TOOLCHAIN in armgnu13) echo "toolchain=userland Arm GNU Toolchain 13.3.Rel1 aarch64-none-linux-gnu (glibc 2.38, libstdc++ GLIBCXX_3.4.32); kernel + GE8300 km: vendor GCC 6.4 Linaro" ;;
                         *) echo "toolchain=$(grep '^CONFIG_GCC_VERSION=' "$SDK_DIR/.config") $(grep '^CONFIG_GLIBC_VERSION=' "$SDK_DIR/.config")" ;; esac
      echo "kernel_encrypt_obj_md5=$(md5_of "$ENC/encrypt") ($ENCRYPT_OBJ)"
      echo "overlay_md5=$(cd "$OAKMOSS_ROOT/overlay" && find . -type f | sort | xargs md5sum | md5sum | cut -c1-32)"
      echo "board_dts=$([ -f "$OAKMOSS_ROOT/boards/$BOARD/board.dts" ] && echo "boards/$BOARD/board.dts $(md5_of "$OAKMOSS_ROOT/boards/$BOARD/board.dts")" || echo "the SDK a133-aw3 (Zero 28) tree")"
      echo "libc=$(strings "$ROOTFS/lib/libc.so.6" 2>/dev/null | grep -m1 'GNU C Library')"
      echo "libstdcxx=$(for f in "$ROOTFS"/usr/lib/libstdc++.so.6.0.*; do [ -e "$f" ] && basename "$f" && break; done)"
      echo "outputs=$(basename "$FINAL") (raw GPT image: dd or Etcher to SD1, whole card); $(basename "$IMG") (Allwinner PhoenixSuit image); $(basename "$IMG").dump/rootfs.fex (rootfs squashfs, used by the hybrid and diag images)"
    } > "$OUT/BUILD-INFO.txt"
    # System.map beside the build: a KDEBUG_MARK card reports initcall addresses, and
    # scripts/analyze-card-readback.py names them from this file.
    cp "$SDK_DIR/lichee/linux-4.9/System.map" "$OUT/System.map" 2>/dev/null || true
    [ "${COMPRESS:-0}" = 1 ] && { log "compressing"; xz -T0 -6 -k "$FINAL"; }
    log "image ready: $OUT"; ls -la "$OUT" >&2 ;;
  all)
    "$0" ext
    boards=("$@"); [ ${#boards[@]} = 0 ] && boards=(zero28 zero40)
    for b in "${boards[@]}"; do "$0" image "$b"; done ;;
  *) die "unknown step $STEP" ;;
esac
