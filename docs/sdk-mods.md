# Ledger of changes to the Tina SDK tree

The SDK (`sdk/lichee`, from MagicX's `Linux_SDK.zip`) is proprietary and never
enters git. This ledger lists every change made to it, with the reason, so that a
fresh unpack can be brought to the same state. `scripts/apply-sdk-mods.sh` applies
the first two tables (idempotent; `--check` audits), `scripts/build.sh` applies the
third at build time. Originals of edited files are kept beside them as `*.orig`;
replaced package directories move to `sdk/lichee/.oakmoss-orig/`.

Paths are relative to `sdk/lichee/`. "Source" names where the change came from:
Moss = Shaun Inman's Moss-zero28 notes, deps = `docs/DEPENDENCIES.md`, oakMOSS =
found while porting the tree to GCC 13 / glibc 2.38.

## Applied by `apply-sdk-mods.sh`: tree patches (`sdk-patches/tree/`, `patch -p1`)

| patch | path | change | reason | source |
|---|---|---|---|---|
| `010-rules-mk-external-toolchain-override` | `rules.mk` | env-driven external-toolchain block (`TINA_EXT_TOOLCHAIN_{ROOT,PREFIX,TARGET_NAME,SYSROOT}`, `TINA_EXT_KERNEL_CROSS`), `CONFIG_TOOLCHAIN_BIN_PATH="./wrap ./bin"`, glibc >= 2.34 file specs; the libc spec is set a second time after the SDK's late reassignment | docs/toolchain.md | oakMOSS |
| `020-kernel-config-4.9` | `device/config/chips/a133/configs/aw3/linux/config-4.9` | `NLS_UTF8=y`, FAT iocharset `utf8`, `VIDEO_SUNXI_VIN` off (Moss "changes not present in configs"); `BLK_DEV_LOOP=y` (MIN_COUNT 8), `INPUT_UINPUT=y`, `INPUT_JOYDEV=y`, `INPUT_FF_MEMLESS=y`, `SND_USB_AUDIO=m`, `XR829_WLAN=m`, `SQUASHFS_LZ4/LZO=y` (deps §7), `SQUASHFS_ZLIB/ZSTD=y` (round 17; LZ4 and gzip took effect only with 134); the 21 `XRADIO*`/`XRMAC*`/`NF_LOG_COMMON`/`IPV6_FOU*`/`BT_XR_BLUEDROID_SUPPORT` symbols `olddefconfig` resolved once XR829 was on (the build's non-interactive `silentoldconfig` aborts on new prompts) | PortMaster loop mounts, gptokeyb uinput, joystick nodes, rumble, USB audio, onboard radio | Moss, deps, oakMOSS |
| `030-toolchain-gcc-7.5.0-option` | `toolchain/gcc/{Config.version,Config.in,common.mk}` | new menu option `GCC_USE_VERSION_7_5_0` (vanilla GNU gcc-7.5.0.tar.xz, md5 recorded, `HOST_BUILD_DIR` set) | releases.linaro.org no longer serves `gcc-linaro-7.4-2019.02.tar.xz`; fallback toolchain only | oakMOSS |
| `040-gpu-km-kernel-cross` | `package/kernel/gpu-km/Makefile` | `CROSS_COMPILE=$(KERNEL_CROSS)` instead of `$(TARGET_CROSS)` | the PowerVR rogue_km build keys its compiler config on the prefix and has no `aarch64-none-linux-gnu.mk`; the module belongs with the kernel's compiler | oakMOSS |
| `050-libffi-no-multi-os-directory` | `package/libs/libffi/Makefile` | `CONFIGURE_ARGS += --disable-multi-os-directory`, placed before `$(eval $(call BuildPackage))` (OpenWrt expands the args at eval time; appending after has no effect) | Arm's gcc reports a `lib64` multi-os dir, libffi installed to `usr/lib64` and packaging failed | oakMOSS |
| `060-util-linux-disable-more` | `package/utils/util-linux/Makefile` | `--disable-more` in the target configure args (the host block already had it) | with `--without-ncurses`, util-linux 2.25's `more.c` has no TERM source and fails; nothing ships `more` | oakMOSS |

## Applied by `apply-sdk-mods.sh`: files and directories

| path | change | reason | source |
|---|---|---|---|
| `package/utils/busybox/patches/905-glibc-2.31-no-stime.patch` | `date`/`rdate`: `stime()` -> `clock_settime(CLOCK_REALTIME)` (as upstream busybox did) | glibc >= 2.31 dropped `stime()` from the link interface | oakMOSS |
| `package/utils/bluez/patches/905-glibc-2.38-sync-rename.patch` | obexd's file-scope driver `sync` -> `sync_driver` | collides with glibc 2.38's `sync()` declaration | oakMOSS |
| `package/utils/bluez/patches/906-glibc-2.38-pause-rename.patch` | media.c static `pause()` -> `media_pause` | collides with glibc 2.38's `pause()` | oakMOSS |
| `package/utils/e2fsprogs/patches/905-sysmacros.patch` | `#include <sys/sysmacros.h>` in every file using makedev/major/minor | glibc >= 2.28 dropped them from `<sys/types.h>`; a forced `-include` via CFLAGS broke the large-file `struct stat` setup | oakMOSS |
| `package/libs/libubox/patches/900-libubox-no-werror.patch` | drop `-Werror` from libubox's CMakeLists | GCC 13 `-Werror=array-bounds` in blobmsg.c | oakMOSS |
| `package/libs/ncurses/` | REPLACED by OpenWrt v21.02.7's ncurses 6.2 package (`$(INCLUDE_DIR)` -> `$(BUILD_DIR)`, `--with-termlib=tinfo`, libtinfo installed); 5.9 moved to `.oakmoss-orig/ncurses-5.9` (left under `package/`, it stays registered and builds) | 5.9's wide-char build breaks under GCC 13 + glibc 2.38; spruce's rnano, mupen64plus and libmp3lame need `libncursesw.so.6` + `libtinfo.so.6` | OpenWrt |
| `toolchain/gcc/patches/7.5.0/` | OpenWrt v19.07.10's 22-patch GCC 7.5.0 set (18 byte-identical to the SDK's linaro-7.4 set) | goes with tree patch 030 | OpenWrt |
| `dl/ncurses-6.2.tar.gz` (+ `dl/gcc-7.5.0.tar.xz`, `dl/binutils-2.28.tar.gz` for the fallback) | pre-fetched sources | the SDK's download URLs for these are dead or absent | GNU |
| `lichee/linux-4.9/drivers/char/sunxi_encrypt/encrypt.zero28` | backup of the SDK's original object (452120 B, 2024-12-16, md5 `f28d35eb…`) | `build.sh` swaps the object per board | oakMOSS |
| `target/allwinner/a133-aw3/defconfig.orig`, `…/base-files/etc/rc.local.orig`, `package/base-files/files/etc/banner.orig`, `…/boot-resource/bootlogo.bmp.orig` | backups | `build.sh` overwrites these per build; the logo reverts to the SDK's when `overlay/bootlogo.bmp` is absent | oakMOSS |

## Applied by `build.sh` at build time (per board)

| path | change | reason | source |
|---|---|---|---|
| `target/allwinner/a133-aw3/defconfig` | REPLACED by the build config (`configs/ext-armgnu13.config`; `phase1`/`phase2*` for the fallback). `build/toplevel.mk` copies this file over `.config` on every `make` when the variant is `tina` (lines 96-103) and `menuconfig` writes back here, so editing `.config` is futile. This is the mechanism behind Moss's "copying a config to .config re-enables everything" note; two builds were lost to it | the config must live where the SDK reads it | oakMOSS |
| `target/allwinner/a133-aw3/base-files/etc/rc.local` | `overlay/etc/rc.local`: the SDK's mixer defaults plus `exec` of `/usr/magicx/bin/runmagicx.sh` | the hand-off | Moss |
| `package/base-files/files/etc/banner` | `overlay/etc/banner` | Moss's banner | Moss |
| `target/allwinner/generic/boot-resource/boot-resource/bootlogo.bmp` | `overlay/bootlogo.bmp` if present, else the SDK's original | Moss's logo is his and is not shipped; `scripts/make-boot-resource.py --logo zero28 overlay/bootlogo.bmp` draws oakMOSS's own (the spruce tree, `assets/spruce-tree.png`). The Zero 28's boot-resource partition is 256 KiB, so its logo is 200 px | oakMOSS |
| `package/add-rootfs-demo/{usr,etc}` | the whole `overlay/` (`/usr/magicx` with `bin/runmagicx.sh`, the SDL2 blobs, the `device` marker; `/etc/modules.d/net-xr829` empty; `/etc/init.d/wpa_supplicant` a no-op) plus `boards/<board>/overlay/`; `add-rootfs-demo` copies it into the rootfs and re-squashes, so these override what the packages installed | `/usr/magicx/device` is what the launcher reads to tell `zero28` from `zero40`; the empty modules file stops the XR829 driver autoloading and tearing down the Realtek 8189es's SDIO card (docs/hardware-notes.md); the init stub replaces wifimanager's S96 service, which started a second wpa_supplicant on wlan0 (empty `/etc/wifi/wpa_supplicant.conf`) that sent a DISCONNECT after every association the launcher's own supplicant made (Zero 28, 2026-09-16) - the launcher owns the radio | Moss, oakMOSS |
| `package/add-rootfs-demo/usr/magicx/tina_config.gz` | gzip of the build's `.config` | Moss's `install.sh` ships it in the image | Moss |
| `package/add-rootfs-demo/usr/magicx/version` | `git describe` of the build | what the launcher compares with the latest release (`docs/updates.md`) | oakMOSS |
| `device/config/chips/a133/configs/aw3/linux/env-4.9.cfg` | `boot_normal` runs `ab_${ab_try}` first; `ab_`, `ab_1`, `ab_2` added | trial boot and fallback for the second slot (`docs/updates.md`) | oakMOSS |
| `lichee/linux-4.9/drivers/char/sunxi_encrypt/encrypt` | Zero 28: the SDK's object; Zero 40: MagicX's object from `Zero40-lichee.zip` (329272 B, 2025-09-22, md5 `33a0a6d7…`). The kernel's OpenWrt stamp does not track the prebuilt object, so `build.sh` records the linked md5 (`.linked-md5`) and forces a kernel relink when it changes | the Zero 40 kernel needs its own object | MagicX |

## Config-level choices (`configs/ext-armgnu13.config` vs Moss's `phase1.config`)

| setting | reason |
|---|---|
| `USE_LIBSTDCXX=y` (was `USE_UCLIBCXX`), `CONFIG_PACKAGE_uclibcxx` off | `build/uclibc++.mk` makes every C++ package depend on uClibc++ and compile through its `g++-uc` wrapper; uClibc++ 0.2.4 does not build under GCC 13 and the Arm toolchain's full libstdc++ is shipped anyway |
| `TARGET_OPTIMIZATION` + `-fcommon` + `-Wno-error=` format-truncation, format-overflow, array-bounds, stringop-truncation, stringop-overflow, maybe-uninitialized, deprecated-declarations, address, misleading-indentation, dangling-pointer, use-after-free | OpenWrt core packages (ubox, netifd, libubox) build with `-Werror`; GCC 13 promotes these newer diagnostics; `-fno-common` became the default in GCC 10 |
| `kmod-net-xr829`, `xr829-firmware`, `XR829_BT`, `bluez-{libs,alsa,daemon,utils,utils-extra}`, `libical` | onboard radio and Bluetooth (deps §5/§7); bluez 5.54's obexd links libical and the ipkg dependency check needs the provider selected (Moss had turned it off together with bluez) |
| `libmad` | the TrimUI `libSDL2_mixer` blob NEEDs `libmad.so.0`; PyUI imports `sdl2.sdlmixer` at start-up and died before its first log line without it (first hardware boot, 2026-09-16). Also added to `phase1`/`phase2*` |
| busybox `UNZIP` (+`FEATURE_UNZIP_CDF`), `LOSETUP`, `STAT` (+`FEATURE_STAT_FORMAT`), `SHA1SUM`, `XXD` | spruce and PortMaster tooling (deps §6); `BC` does not exist in busybox 1.27.2 |


## Round 8 (2026-09-16): conntrack-free kernel, busybox applets, bash

The reason for the round: MagicX's own kernel (which the Zero 40 hybrid boots) has no connection tracking, ours did, and the resulting `struct sk_buff` layout difference oopsed every module of ours loaded under theirs. `sdk-patches/tree/020-kernel-config-4.9.patch` is the regenerated pristine-to-round-8 diff; `configs/ext-armgnu13.config` is the round-8 userland config. Mod-set version 2.

| what | change | why | where |
|---|---|---|---|
| `device/config/chips/a133/configs/aw3/linux/config-4.9` (round 8, 2026-09-16) | REGENERATED through the kernel's `olddefconfig` from the previous file plus: `LOG_BUF_SHIFT=18`, `ZSMALLOC=y`, `ZRAM=m`, `CRYPTO_LZO/LZ4=y`, `SECCOMP=y`, `POSIX_MQUEUE=y`, `INPUT_JOYSTICK=y`, `JOYSTICK_XPAD=m` (+FF, LEDS), `HID_SONY=m` (+SONY_FF), `HID_MICROSOFT=m`, `HID_LOGITECH=m`, `BT_HIDP=m`; the VIN and `NF_LOG_COMMON` lines the board-only resolve dropped are re-appended verbatim (they become reachable again once the kmod packages merge). Previous file kept as `config-4.9.pre-round8`. | TODO.md | both |
| `target/allwinner/a133-aw3/defconfig` = `configs/ext-armgnu13.config` (round 8) | `CONFIG_PACKAGE_softap`/`softap-demo`/`dnsmasq`/`hostapd` OFF: **softap's Makefile injects `CONFIG_NF_CONNTRACK=y`, `NF_NAT=y`, the CONNMARK/STATE/REDIRECT/NETMAP xt options into the kernel config** (the board config-4.9 says conntrack is off, the real `.config` had it on). Conntrack adds a pointer to `struct sk_buff`, so our modules read `skb->data` 8 bytes past where MagicX's kernel keeps it - the Zero 40 xradio crash under the hybrid. `CONFIG_PACKAGE_bash=y`; BusyBox applets `TIMEOUT`, `NOHUP`, `SETSID`, `PASTE`, `PKILL`, `FUSER`, `LSOF`, `WATCH` on. `wifimanager` kept (its init script is stubbed by the overlay). Previous file kept as `ext-armgnu13.config.pre-round8`. | Zero 40 xradio oops analysis; wishlist | ext builds |
| `config-4.9` (round 8b/8c) | Three build aborts in a row taught the merge order: the kernel's `silentoldconfig` runs on config-4.9 PLUS the selected kmod packages' KCONFIG lines, so a board-only `olddefconfig` cannot see the prompts that appear once `NETFILTER_XTABLES` etc. are merged in (and `softap` used to answer `XT_MATCH_QUOTA2`, `CONNSECMARK`, `SECMARK`, `REJECT_SKERR` for us). Recipe that works: let the build write the merged `lichee/linux-4.9/.config`, run `make olddefconfig` on a copy inside the container, append every line whose VALUE changed (name-only diffs miss kconfig choices such as `CCI`), repeat until the build passes the config step. Appended this way: `XT_MATCH_QUOTA2/CCI_TO_TWI/D3D/DISPPLAY_SYNC/BUF_AUTO_UPDATE/MULTI_FRAME/PIPELINE_RESET/ENABLE_SENSOR_FLIP_OPTION/WDR_COMPRESS_EN/BT_XR_BLUEDROID_SUPPORT/IPV6_FOU*` not set, `CSI_CCI=m`, `CCI=y`, `CGROUPS=y`, `NF_LOG_IPV4/IPV6=m`, `NF_REJECT_IPV4=m`, `SLABINFO=y`; `WDR` forced back to not set (the resolver's default `y` does not compile: `sunxi_isp.c` references `ISP_WDR_GAMMA_FE_MEM_OFS`/`bsp_isp_set_wdr_addr*` that this tree lacks). | this repo | both |
| `config-4.9` (round 8d) | `ZRAM`, `JOYSTICK_XPAD`, `HID_SONY`, `HID_MICROSOFT`, `HID_LOGITECH`, `BT_HIDP` changed from `=m` to `=y`: the OpenWrt rootfs only carries modules that a `kmod-*` package installs, this SDK has none for them, and the `.ko` files stayed in the kernel tree (round 8 image had no `zram.ko`/`xpad.ko`). | this repo | both |

Everything else in the config is Moss-zero28's phase-1 selection.


## Round 9 (2026-09-16): the XU20 and Zero 40 panels, in our kernel

| what | where | why |
|---|---|---|
| `070-lcd-panels-rtp32hd016a-rtp40wv101b.patch` | `lichee/linux-4.9/drivers/video/fbdev/sunxi/disp2/disp/lcd/` (`rtp32hd016a.[ch]`, `rtp40wv101b.[ch]`, `panels.[ch]`, `Kconfig`, `../Makefile`) | The XU20's RTP32HD016A (1024x768) and the Zero 40's RTP40WV101B (480x800) two-lane DSI panels are in neither the SDK drop nor main-zero40. Their open/close flows, power and reset sequences and DSI init tables were read out of the boards' stock kernel binaries (XU20 developer `user.img`, kernel 4.9.170) with a symbol-resolving disassembly and reproduced call for call, delays included; the RTP32HD016A table keeps the stock driver's two malformed delay rows on purpose (they send DCS 0xfe with 120/20 bytes, which is what the shipped panel sees). Gamma/cmap setup is the SDK's standard one. |
| `020-kernel-config-4.9.patch` (refreshed) | `device/config/chips/a133/configs/aw3/linux/config-4.9` | `CONFIG_LCD_SUPPORT_RTP32HD016A=y`, `CONFIG_LCD_SUPPORT_RTP40WV101B=y`. |
| `boards/xu20/board.dts`, `boards/zero40/board.dts` (not SDK patches; installed by `build.sh` per board) | `device/config/chips/a133/configs/aw3/board.dts` | Generated by `scripts/make-board-dts.py` from the Zero 28 tree plus each board's stock tree: lcd0 timings and GPIOs, the simplepad key map, the wlan node, the battery model. The Zero 28's own tree comes back for boards without one. |

`mods_version` 2 -> 3.

## Round 10 (2026-09-17): the XU20 and Zero 40 touch controllers, in our kernel

| what | where | why |
|---|---|---|
| `080-touch-hynitron-axs15205.patch` | `lichee/linux-4.9/drivers/input/touchscreen/hynitron/` (Radxa allwinner-bsp `hyn_ts`, GPL-2.0, minus its firmware images and tool-debug file), `.../axs15205/axs15205.c` (ours), `touchscreen/Kconfig` + `Makefile` hooks | The XU20's Hynitron CST340 (I2C 0x5a) and the Zero 40's AXS15205 (0x3b). Hynitron: address from the node's `reg`, axis flags from the ctp node, `-EBUSY` accepted on PB7/PB6 (the ctp framework requests them first), firmware table guarded behind the (off) auto-update switches. AXS15205: written from the stock kernel's own driver (plain 32-byte frame reads, five slots, 480x800); the public ugreen sources are a different protocol. Details: hardware-notes "Touch". |
| `020-kernel-config-4.9.patch` (refreshed) | `device/config/chips/a133/configs/aw3/linux/config-4.9` | `CONFIG_TOUCHSCREEN_HYNITRON_TS=y`, `CONFIG_TOUCHSCREEN_AXS15205=y` (`INPUT_SENSORINIT` was already on). |
| `boards/xu20/board.dts`, `boards/zero40/board.dts` (regenerated) | `device/config/chips/a133/configs/aw3/board.dts` | `make-board-dts.py` now also moves `twi1_pins_a/b` to the stock PB4/PB5 (the Zero 28 tree has PH2/PH3), enables twi1 and carries the stock touch node (XU20 `ctp`, Zero 40 `cap_touch@3b`) with its gpio specs in label form. Axis flags stay at the stock 0: PyUI maps touch through the inverse of DISPLAY_ROTATION itself. |
| `boards/*/board.dts` (regenerated again, same day) | disp node | `cldo2-supply = <&reg_cldo2>` (every `lcd_powerN` rail the stock tree names becomes a disp supply): without it the disp gets a dummy regulator for `lcd_power`, the unused-regulator sweep turns cldo2 off at 3.8 s, and the touch controller's I2C lines lose their rail (hardware-notes "The touch rail"). |

| `085-simplepad-no-uart-thread-without-sticks.patch` | `lichee/linux-4.9/drivers/input/keyboard/simplepad.c` | The pad driver opens its stick UART only when `joysticks != 0` but always started the UART reader thread; on the XU20 (no sticks) the thread dereferenced the NULL file and oopsed at 8.4 s of every boot (`joystick_thread_fn+0x48`, 2026-09-17 log; the boot survived, the thread died). The thread now starts only with an open UART. |
| `086-simplepad-axes-without-sticks.patch` | `lichee/linux-4.9/drivers/input/keyboard/simplepad.c` | A board without sticks (XU20) registered no EV_ABS axis at all, and SDL does not count a device without axes as a joystick: SDL 2.26 (vendor) and 2.32 (spruce) both reported 0 joysticks on the XU20 (2026-09-22), so PortMaster's GUI, gptokeyb and every SDL port saw no pad. The pad now advertises ABS_X/ABS_Y held at 0, the centre of the range, and never reports them - what TrimUI's inputd does on the stickless Brick. Key codes and SDL's button numbering are unchanged. |

`mods_version` 3 -> 5 (4 = touch, 5 = simplepad).

## Repairs to `apply-sdk-mods.sh` (2026-09-17)

The script could not complete on an SDK tree that already carried some of these
changes and died on its first patch, leaving the marker at version 3 while the
scripts were at 5. Three defects,
all of which mattered:

| defect | effect |
|---|---|
| Target paths were read with `grep '^+++ b/'`. Some tree patches carry vendor sources whose non-ASCII comments make ugrep treat the whole patch as binary and print nothing. | The `.orig` backup loop silently found no files, so a forward apply would have overwritten originals with no backup. Patch `080` hit this exactly. |
| The same line split `+++ b/<path>\t<timestamp>` on whitespace. | Patches written with timestamps (`070`, `080`) yielded bogus extra filenames. |
| A change already present in the tree under different comments failed `patch -R --dry-run`, and the script treated that as "not applied" and tried to apply it again. | `010` was force-applied a second time, leaving a duplicated (inert) toolchain-override block in `rules.mk`. The tree has been restored. |

Targets are now parsed with `awk` (binary-safe, strips the timestamp). A patch whose
added lines are all already present is reported `in-tree` rather than reapplied.
Package patches compare their diff **body**, ignoring the prose header, because the same
fixes can already be present with a different provenance line: four were being reported
missing and would have been overwritten with byte-identical diffs. A fifth was present
under a different filename entirely, and installing ours beside it made quilt apply the
change twice and fail the build, which is why the comparison scans the whole directory.

An unpacked SDK tree that other work has touched can carry a change genuinely in place
without this repository having put it there; the `in-tree` check exists for that case.

## Round 11 (2026-09-18): touch as late modules, and a debug lane

| what | where | why |
|---|---|---|
| `080-touch-hynitron-axs15205.patch` (refreshed) | `touchscreen/Kconfig`, `hynitron/hynitron_core.c` | Both drivers are declared `tristate`. Built in, their `late_initcall` probes ran on the kernel's init thread and stalled boots at the logo (hardware-notes "Touch drivers stalled the boot"). The Hynitron probe no longer pulses reset a second time after requesting its IRQ: loaded late, that pulse froze the XU20. |
| `020-kernel-config-4.9.patch` (refreshed) | `config-4.9` | `CONFIG_TOUCHSCREEN_HYNITRON_TS=m`, `CONFIG_TOUCHSCREEN_AXS15205=m` (were `=y`). |
| `090-touch-modules.patch` | `target/allwinner/a133-aw3/modules.mk` | `kmod-touchscreen-hynitron` and `kmod-touchscreen-axs15205`, with **no** `AUTOLOAD`: the launcher loads the board's module once the board has settled (spruceOS `magicx_load_touch`). Both configs select the packages. |
| `100-disp2-fb-g2d-rotation.patch` | `drivers/char/sunxi_g2d/g2d_driver.c`, `drivers/video/fbdev/sunxi/disp2/disp/{dev_fb.c,fb_g2d_rot.c,fb_g2d_rot.h}` | Hardware framebuffer rotation through G2D on every flip (vendor Dechuang patch, a133-tina-bsp-update 2025-10-11, with the acmeplus gist fixes folded in), enabled per board by `disp_rotation_used`/`degree0` in board.dts: Zero 28 a quarter turn, XU20 a half turn. G2D init moved to subsys_initcall so it exists before disp. |
| `101-disp2-fb-g2d-rotation-current-frame-flip-by-crop.patch` | `drivers/video/fbdev/sunxi/disp2/disp/fb_g2d_rot.c` | Two defects of the vendor rotation, both measured on the XU20 2026-09-22. (1) It rotated `fb->var.yoffset`, the frame currently SHOWN - the fb core updates that field only after the pan returns - so every flip showed the previous frame and a press appeared one flip late (felt as lag in PortMaster). It now rotates the requested offset, read from crop.y. (2) It switched the layer buffer address every frame; the DE then raised vsync interrupts at ~34 Hz and a flip issued 1-11 ms after a vsync took two frames. The flip now keeps one address and selects the frame by crop.y over the two stacked rotation frames, as the un-rotated path does. |
| `102-uboot-fb-bootlogo-rotate.patch` | U-Boot boot logo (Zero 28 only) | Rotates the boot logo the same way the kernel rotates the framebuffer, so the logo is not sideways on the Zero 28's portrait panel. |
| `apply-sdk-mods.sh` | `patch --no-backup-if-mismatch` | GNU patch otherwise saves a file it could not match as `<file>.orig`, the name this script keeps the pristine SDK copy under, so one failed attempt overwrote the pristine `config-4.9.orig`. Every line now has one owning tree patch: a later patch that edits a line an earlier one adds makes the earlier one read as missing. |
| `sdk-patches/debug/kdebug-mark.patch` | `init/main.c`, the two touch drivers, `i2c-sunxi.c`, and since 2026-09-29 the suspend/resume path (PM core, regulator core, display, GIC, pinctrl, watchdog, PSCI, panic/restart; a reserved-memory mark ring in `sun50iw10p1.dtsi`) | **Not applied by this script.** `build.sh KDEBUG_MARK=1` applies it and every other build reverts it - only ever exactly: when the patch and the tree disagree the build stops with the tree untouched (no forced apply). Edit it through `scripts/kdebug.sh`: `stash` a file before its first debug edit, edit the SDK tree, `regen` (rebuilds the patch from the recorded pristine copies and checks it), `build <board>`; `check` compares every touched file byte for byte with pristine + patch. With `oakmoss_mark=<phys>` on the command line the kernel writes its progress (initcall addresses, init stages, driver steps) to an RTC general-purpose register that survives a power-off; `make-own-kernel-stock.sh KMARK=1` has U-Boot save it into the env on the next boot, and `scripts/analyze-card-readback.py` names it from `System.map`. Purely additive over the tree patches' lines. |

`mods_version` 5 -> 6.

## Round 12 (2026-09-24): on-device tools, a quiet serial console, a tracing lane

The image had no way to trace, decode input or hash-and-ship a file: on 2026-09-24 a
frame-skip hunt on the Zero 28 ran without `base64` (binaries had to be streamed through
`gzip`), without `od` (device-tree reads came back silently empty) and without ftrace (the
display driver's own `DISP_TRACE` markers compile to nothing). Everything below is from
the Tina package tree or BusyBox; nothing new is downloaded except strace's source.

| what | where | why |
|---|---|---|
| `configs/ext-armgnu13.config` | BusyBox applets | `base64`, `od`, `nproc`, `taskset` (+`FEATURE_TASKSET_FANCY`), `devmem`, `iostat`, `mpstat`, `pmap`, `dc` (+`FEATURE_DC_LIBM`). BusyBox is in custom mode here, so the `CONFIG_BUSYBOX_CONFIG_*` lines are the switches; the `CONFIG_BUSYBOX_DEFAULT_*` lines are only defaults (`timeout`, `losetup`, `lsof`, `xxd` and `watch` were already on). BusyBox 1.27.2 has no `bc` (added in 1.30); `dc` is the calculator it has. |
| `configs/ext-armgnu13.config` | packages | `strace`, `gdbserver` (`gdb` was already on), `i2c-tools`, `trace-cmd`, `memtester`, `stress-ng`, `htop`, `iperf3`, `tcpdump` (+`libpcap`), `ethtool`. The rootfs is a ~50 MiB squashfs in a 600 MiB partition. |
| `065-htop-link-libtinfo.patch` | `package/utils/htop/Makefile` | `TARGET_LDFLAGS += -ltinfo`: our ncurses 6.2 is built `--with-termlib=tinfo`, so `napms()` and the other terminfo symbols are in `libtinfo`, and htop 2.0.2 links `-lncursesw` only ("DSO missing from command line"). |
| `066-strace-6.10.patch` | `package/devel/strace/Makefile` | strace 5.0 -> 6.10 and `PKG_FIXUP:=autoreconf` dropped (6.10 ships its `configure`; the host autoconf is 2.69). 5.0 does not build against the GCC 13 / glibc 2.38 headers (`struct ptrace_syscall_info` "declared inside parameter list"). Source: `https://strace.io/files/6.10/strace-6.10.tar.xz`, sha256 `765ec71a...cf07`, signature checked against Dmitry V. Levin's release key (primary `296D 6F29 A020 808E 8717 A884 2DB5 BD89 A340 AEB7`); pre-staged in `dl/` for the first build. |
| `sdk-patches/package-patches/stress-ng/905-glibc-2.34-pthread-stack-min.patch` | `package/allwinner/stress-ng/patches/` | stress-ng 0.12.07 compares `PTHREAD_STACK_MIN` in `#if`; glibc >= 2.34 makes it `sysconf(...)`, which the preprocessor cannot evaluate. The run-time `#else` branch is kept (what stress-ng does from 0.13). |
| `110-env-4.9-quiet-serial-console.patch` | `device/config/chips/a133/configs/aw3/linux/env-4.9.cfg` | `loglevel=8` -> `4`. The Zero 28's image boots with this env (`console=ttyS0,115200`), and every kernel line was written synchronously to a 115200-baud UART - the RTW driver's power-save chatter comes in ~200-byte bursts, about 17 ms of UART, longer than a frame. Measured 2026-09-24: 30 injected 4-line log bursts cost **36 dropped frames** (disp `skip:`) at loglevel 8 and **0** with the console quieted; the XU20 (`console=tty0`) dropped none either way. Warnings and errors still reach the UART; everything stays in `dmesg` and pstore. The XU20 and Zero 40 do not use this env (`make-own-kernel-stock.sh` sets their `loglevel=7` with `console=tty0`). |
| `sdk-patches/debug/kdebug-ftrace.config` | `config-4.9` | **Not applied by this script.** `build.sh KDEBUG_FTRACE=1` puts this block where `# CONFIG_FTRACE is not set` stands (function, function-graph and event tracing; every prompt answered, resolved with `olddefconfig` and checked with `listnewconfig`: none left) and every other build takes it out again. It also sets `CONFIG_KERNEL_FTRACE`, `_FUNCTION_TRACER`, `_FUNCTION_GRAPH_TRACER` and `_DYNAMIC_FTRACE` in the SDK's top-level defconfig: `build/kernel-defaults.mk` appends every `CONFIG_KERNEL_*` line to the kernel config and the later line wins, so the first debug kernel came out without tracing. Both files are rewritten only when their state is wrong (`build.sh kdebug_block`). Proven from built images 2026-09-24 with `extract-ikconfig`: `KDEBUG_FTRACE=1` gives `CONFIG_FTRACE/FUNCTION_TRACER/DYNAMIC_FTRACE/EVENT_TRACING=y`, the next ordinary build is back to `# CONFIG_FTRACE is not set` with both files byte-identical to before. Debug cards only. |

`mods_version` 6 -> 7.

## Round 13 (2026-09-24): hardware feedback on the rotation set

| what | where | why |
|---|---|---|
| `100-disp2-fb-g2d-rotation.patch` (refreshed, same line count) | `dev_fb.c` `Fb_copy_boot_fb` | The 90/270 dst width/height swap is gone. `info->var` already holds the rotated frame (fb0_width/height are the panel's swapped), so the swap made the 270 copy (the Zero 28's `degree0 1`) start at row 639 of a 480-row buffer: 160 rows low and partly in the second buffer. Reported on the unit: the boot logo was right way up but "transposes down the screen after flickering" at the kernel's takeover. The 90 and 180 copies never read the swapped value. |
| `080-touch-hynitron-axs15205.patch` (refreshed, same line count) | `hynitron_core.c` | The ctp node's `ctp_revert_x/y_flag` / `ctp_exchange_x_y_flag` are now the whole transform (`? 1 : 0`). Before, `flag ? 1 : HYN_*_REVERT` could only ADD a flip, and `HYN_Y_REVERT 1` forced a Y flip whatever the node said, so no node could express "no Y flip". |
| `boards/xu20/board.dts`, `scripts/make-board-dts.py` | ctp node | `ctp_revert_x_flag` 1 -> 0 (Y stays 0). The panel frame needs X and Y flipped (TOUCH_PANEL_FRAME); the kernel shows the panel turned 180, which flips both back, so touch arrives in the frame every app draws in. `touch_flags()` derives the flags from TOUCH_PANEL_FRAME and FB_ROTATION (a quarter-turn with touch stops the generator: exchange is not modelled). Reported on the unit: XU20 touch inverted under the kernel rotation, as predicted from PyUI no longer inverting it. |

Images: `builds/20260924-1710-zero28` (both rounds), `builds/20260924-1713-xu20-own` (md5 `1f5ced17...`; both DTB copies checked: revert x/y 0, degree0 2). Not yet run on hardware.

## Round 14 (2026-09-25..30): charge mode, the SDK chain on all three, suspend that resumes

All three boards now flash the SDK chain (our U-Boot with their panels, SDK boot0 and ATF/SCP),
which is what reaches charge mode; real suspend-to-RAM works on all three with the fixes below.

| what | where | why |
|---|---|---|
| `020-kernel-config-4.9.patch` (refreshed) | `config-4.9` | `CONFIG_GPIO_SYSFS=y`: spruce drives the MagicX rumble motor through `/sys/class/gpio` (PH3, gpio227 on the Zero 40 and XU20); without it the export node did not exist and rumble was silently unavailable. |
| `120-axp2202-gauge-model-content-check.patch` | `drivers/power/supply/axp2202_battery.c` | The fuel gauge's 128-byte battery model is read back (the driver's own verify sequence) and reloaded when it differs from the device tree's. The driver loaded it only when the gauge's update mark was clear - after the PMIC lost power - and never compared, so a gauge kept whatever model it had. Paired with each board's own stock profile in `boards/*/board.dts` (`make-board-dts.py`; every board used to carry the SDK's). |
| `boards/*/board.dts`, `scripts/make-board-dts.py` | pad keys | One key code per press: the stock trees' second codes (`linux,code2`: A 353, and on the XU20 B 158 and MENU 256, their Android launcher's confirm and back keys) are dropped. The XU20's extra face button (PH11) was code 0, which the kernel drops; it is now `KEY_HOMEPAGE` (172), the TrimUI Smart Pro S's Home key. spruce reads the pad's key bitmap at run time, so a card works on older images too. |
| `103-uboot-lcd-panels-rtp32hd016a-rtp40wv101b.patch` | `lichee/brandy-2.0/u-boot-2018/drivers/video/sunxi/disp2/disp/lcd/` (`rtp32hd016a.[ch]`, `rtp40wv101b.[ch]`, `panels.[ch]`, `Kconfig`, `../Makefile`) | 070's two panel drivers in U-Boot, so our own U-Boot lights the Zero 40 and XU20 panels (boot logo, charge-mode picture) on the SDK chain. U-Boot's panel API is the kernel's with three typedef spellings (`panel_extend_para`, `disp_panel_para`, `__lcd_panel_t`); sequences unchanged. Their stock U-Boots carry the same two drivers, and main-zero40's SDK U-Boot differs from the SDK's only by RTP40WV101B (2026-09-26 string diff). The stock XU20 U-Boot also has an RTP36HD029A, a panel variant neither our kernel nor this patch has. |
| `boards/<board>/sys_config.fex` | `charge_mode = 1`, `battery_exist = 1` | U-Boot draws `bat/battery_charge.bmp` when a board is plugged in while off and boots Linux with `androidboot.mode=charger`; `runmagicx.sh` then runs the charge screen (`overlay/usr/magicx/bin/charge-screen.sh`) instead of the launcher. |
| `boards/<board>/sys_partition.fex` | boot-resource partition 4 MiB | Room for the charge, low-battery (`bat0`, `low_pwr`) and logo pictures (the XU20's set is 2.9 MB). |
| `130-i2c-sunxi-no-irq-storm-on-bus-error.patch` | `drivers/i2c/busses/i2c-sunxi.c` | A bus error (TWI status 0x00) left the controller's interrupt flag set - the vendor's flag clear sat after its `goto` - and the handler re-enabled the interrupt unconditionally, so it fired for ever: a hard lockup. On the XU20 with the touch driver loaded this froze every suspend: the display cuts the panel rail (cldo2) at the end of device suspend, the touch controller on twi1 goes down, the idle bus reports a bus error (captured 2026-09-29: stat 0x00, ctl 0xc8, no transfer in flight). Now the flag is cleared, the interrupt is re-enabled only while a transfer is in flight, and an interrupt with no transfer resets the controller and stays off (`sunxi_i2c_do_xfer` re-enables it). |
| `080-touch-hynitron-axs15205.patch` (refreshed) | `axs15205/axs15205.c` | The Zero 40's touch interrupt comes back in the PM `.complete` step instead of `.resume`. The chip is powered with the panel and leaves reset through the panel's power-on sequence, which the display runs in its own resume - in parallel when devices resume asynchronously - so the edge latched while the chip lost power at suspend was replayed at once and its frame read hit a chip still in reset (`i2c1 incomplete xfer (status 0x48, 0x3b)`, 19 ms into the display's resume, 2026-09-29). A flag keeps disable/enable balanced when a suspend is aborted. |
| `sdk-patches/debug/kdebug-mark.patch` (extended) | suspend/resume path | See its row under round 11: the marks, probes and switches that found the XU20 freeze. |
| `scripts/build.sh`, `scripts/apply-sdk-mods.sh`, `scripts/kdebug.sh` | patch application | Never forced: the debug patch is applied or reverted only exactly and a tree patch only after a clean dry run; when a patch and the tree disagree the scripts stop with the tree untouched. A forced partial apply had duplicated hunks in seven kernel files. `kdebug.sh` keeps the debug patch in step with the tree from recorded pristine copies. |

U-Boot is not rebuilt by `make`: the pack takes the binary at
`device/config/chips/a133/bin/u-boot-sun50iw10p1.bin`. After an SDK unpack or a U-Boot patch
(102, 103), run `scripts/build.sh uboot`: it builds the **Tina** defconfig
(`sun50iw10p1_tina_defconfig`; brandy's own `build.sh -o uboot` builds all five `sun50iw10p1*`
defconfigs and leaves whichever came last, and `sun50iw10p1_defconfig` is the Android one, with
AVB and A/B slots) and installs it. `build.sh image` refuses a binary without the panels and the
logo rotation, or an Android build, and records its md5 in `BUILD-INFO.txt` (`uboot_md5`).

`mods_version` 7 -> 8.

## Round 15 (2026-10-02): touch that apps can use

DraStic (trngaje's advdrastic, which finds the touchscreen through udev) saw no touchscreen on
the Zero 40 and XU20, and once it did, no tap registered: the log showed each held touch
re-reported as a new one.

| what | where | why |
|---|---|---|
| `131-input-drop-repeated-mt-values.patch` | `drivers/input/input.c` | The vendor commented out the input core's "drop unchanged value" check (for a g-sensor that repeats samples), so every report passes. Our touch drivers use `input_mt`, which relies on that check: each report re-sent the slot's `ABS_MT_TRACKING_ID` (and `-1` for the four empty slots; raw capture on the Zero 40, 2026-10-02), and SDL turns every repeated tracking ID into a finger up and down, so no app sees a held touch. The check comes back for multitouch values only; other axes keep the vendor behaviour. |
| `overlay/etc/udev/rules.d/60-oakmoss-touchscreen.rules` | `/etc/udev/rules.d` | The image has no `60-input-id.rules`, so udev tags no input device and libudev users find no touchscreen. The rule runs udev's `input_id` builtin on the two touch controllers only (`axs_ts`, `hyn_ts`): run on every input device it tags the pad a mouse (virtual-mouse buttons 272/273 plus `ABS_X/ABS_Y`), and SDL would stop treating it as a joystick. It also gives the XU20's touchscreen a calibration matrix (panel turned 180 degrees, axes inverted against it). |
| `132-bash-links-installed-readline.patch` | `package/utils/bash/Makefile` | A build from an empty `out/` failed on both build hosts (2026-10-02): `Package bash is missing dependencies for the following libraries: libhistory.so.6`. bash declared only `libncurses`, so whether it linked its bundled readline or the staged `libreadline`/`libhistory` depended on which package finished first; warm trees happened to win (the shipped bash needs only `libtinfo` and `libc`), a cold parallel build loses every time. bash now declares `libreadline` and links it (`--with-installed-readline`), as OpenWrt's own package does; bash 4.3 and readline 6.3 are a matched pair and the image already ships `libreadline`. |

`mods_version` 8 -> 10 (9 was round 15 without 132).

## Round 16 (2026-10-03): Bluetooth audio that does not wedge

The Zero 40 (BlueZ 5.54 + the SDK's bluez-alsa 1.3.1, measured 2026-10-03) lost Bluetooth audio
for good after RetroArch's in-game menu or a game-switcher exit: bluealsa's main and control
threads sat in `futex_wait` with no IO thread left, bluetoothd logged `Endpoint replied with an
error: org.freedesktop.DBus.Error.NoReply` and `Unable to select a valid configuration`, every
connect failed with `org.bluez.Error.Failed`, and `amixer -D bluealsa scontrols` blocked. In
1.3.1, `ctl.c` serves every request under `config.devices_mutex` and DRAIN waits on
`pcm->drained` with that mutex held, while the A2DP IO thread signals "drained" only from a
100 ms poll timeout and exits on FIFO EOF or a write error without signalling. Upstream rewrote
that locking (bbad9f5, e58331f, d14269a), all in 4.0.0. Separately, 1.3.1 without
`--a2dp-volume` copied the headset's AVRCP volume into its own software gain while the headset
applied it too: half volume on the headset played about 32 dB down. 4.0.0 no longer does: an A2DP
source in software-volume mode ignores the headset's volume reports, with or without that option.

4.0.0 still drains the same way in a narrower case: the PCM "Drain" command runs on the main GLib
loop thread and waits there, with no timeout, for a signal only the IO thread's 100 ms poll timeout
sends. A client that dies mid-drain is handled (the IO thread keeps running and signals), but an
IO thread that exits mid-drain (headset disconnected or out of range, BT write error) leaves the
main loop blocked for good, with the same symptoms. Upstream fixed this after 4.0.0, and its ALSA
plugin waited for every control reply with no time limit; those fixes are backported (906, 907).

| what | where | why |
|---|---|---|
| `133-bluez-alsa-4.0.0.patch` | `package/multimedia/bluez-alsa/Makefile` | 1.3.1 (snapshot 20180913) -> 4.0.0. 4.0.0 is the newest this SDK can build (glib 2.50.1, sbc 1.3): 4.1.0 calls `sbc_reinit_a2dp()`, which libsbc exports from 1.5 (upstream 23662ac raised the declared floor in 4.1.1); 4.1.1 also generates its D-Bus code with `gdbus-codegen --interface-info-body`, which neither the SDK's host glib 2.50 nor the build container's (Ubuntu 18.04, glib 2.56) has; 4.2.0 and 4.3.x need glib >= 2.58.2 (ed24c9c) and bluez >= 5.51 (4.0.0 needs glib >= 2.32, sbc >= 1.2, dbus-1 >= 1.6; BlueZ 5.54 meets bluez >= 5.0). 4.3.0 also opens a new codec configuration whenever a client asks for another rate (13b0bf8), which made earbuds announce a disconnect on every app switch on another spruce base; 5.x renames the daemon (`bluealsad`) and CLI, which spruce calls by name. SBC only: AAC, aptX, aptX HD, FastStream, LC3plus, LDAC, MP3, mSBC, oFono, UPower and systemd off (`fdk-aac` no longer pulled in). Installs `bluealsa`, `bluealsa-aplay`, `bluealsa-cli`, the pcm/ctl plugins in `/usr/lib/alsa-lib`, `20-bluealsa.conf` in `/usr/share/alsa/alsa.conf.d` (where this alsa-lib's `alsa.conf` hooks load add-ons) and the D-Bus policy `/etc/dbus-1/system.d/bluealsa.conf` (4.x owns `org.bluealsa` on the system bus). Declares `bluez-libs` and `libdbus`, which it links. Nothing starts the daemon at boot (no init script, procd entry or `bt_init.sh` line); spruce starts it (`bluealsa -p a2dp-source`). |
| `sdk-patches/package-patches/bluez-alsa/905-a2dp-stdlib-qsort.patch` | `package/multimedia/bluez-alsa/patches/` | `src/a2dp.c` calls `qsort()` without `<stdlib.h>`: an implicit declaration, a warning under GCC 13 and an error from GCC 14. |
| `sdk-patches/package-patches/bluez-alsa/906-drain-sync-backport.patch` | `package/multimedia/bluez-alsa/patches/` | The daemon's drain cannot block its main loop for good: upstream 7ae09a4 (4.1.0) and 0677f97 (4.2.0), adapted to 4.0.0 (see "Backported from upstream" below). |
| `sdk-patches/package-patches/bluez-alsa/907-pcm-ctrl-nosignal-timeout.patch` | `package/multimedia/bluez-alsa/patches/` | PCM clients (the ALSA plugin in every app, `bluealsa-cli`) neither hang on nor are killed by the PCM control socket: upstream 916c50f and 5f3eeef (4.2.0), as upstream wrote them. |
| `apply-sdk-mods.sh` step 3b | `package/multimedia/bluez-alsa/patches/` | The SDK's two patches for the 2018 source (`0001-add-extern-hfp-over-pcm-support`, `0002-fix-volume-adjustment-is-limited-by-name-length`) do not apply to 4.0.0 and move to `.oakmoss-orig/bluez-alsa-20180913-patches/`. |
| `scripts/lib.sh`, `fetch-inputs.sh`, `apply-sdk-mods.sh` step 5 | `dl/bluez-alsa-4.0.0.tar.gz` | The v4.0.0 tag archive is pinned (`BLUEZALSA_*`, sha256 = the Makefile's `PKG_HASH`), fetched into `inputs/` and staged into `dl/`. |

`mods_version` 10 -> 11.

### Backported from upstream

The source is the v4.0.0 tag; these upstream commits are carried as patches on it. Each patch's
header names the commits and says what was taken and what was changed.

| upstream commit | release | what it fixes | in oakMOSS |
|---|---|---|---|
| 7ae09a4 Fix PCM drain synchronization - use mutex for sync | 4.1.0 | `ba_transport_pcm_drain()` used a bare `pthread_cond_wait()` with no condition to check: a signal sent before the wait, or none at all, left it waiting forever. Upstream waits in a loop for a `synced` flag set under the mutex. | 906. Taken: the flag, the loop, and the flag set in io.c's poll timeout. Changed: the flag stays under 4.0.0's dedicated `synced_mtx`, not `pcm->mutex` as upstream (in 4.0.0 the PCM open handler and the IO thread's blocking FIFO write hold `pcm->mutex` for long stretches; upstream moved those to a client mutex in 0959403). The condition variable is renamed `synced` -> `synced_cond` so the flag can take upstream's name. Upstream's `th->changed` -> `th->cond` rename is left out. |
| 0677f97 Fix PCM drain lockup caused by transport destroy | 4.2.0 | An IO thread cancelled or exiting mid-drain never signalled the drain. Upstream's per-PCM thread cleanup now marks the PCM synced. | 906. 4.0.0 has no per-PCM thread cleanup, so the same lines go in `ba_transport_thread_cleanup()`, for the PCMs whose `th` is the exiting thread, after the state is reset to NONE. |
| (none: oakMOSS) | - | A 4.0.0 IO thread that has exited keeps its ID until the main thread joins it, so a drain arriving after the cleanup ran would still wait forever. | 906. The drain checks the thread state under `synced_mtx` and returns ESRCH unless it is RUNNING. The cleanup resets the state before it takes `synced_mtx`, so a drain either sees the thread gone or gets the cleanup's wake-up. Lock order: `synced_mtx` -> `state_mtx`, and nothing takes them the other way round. |
| 916c50f Protect PCM client control socket from SIGPIPE | 4.2.0 | `write()` to a control socket the daemon had closed (daemon stopped or restarted) raised SIGPIPE and killed the app. | 907, as upstream: `send(..., MSG_NOSIGNAL)`. |
| 5f3eeef Do not block forever PCM client on control command | 4.2.0 | The plugin waited for each control reply with `poll(..., -1)`: an app froze for good if the daemon never answered. | 907, as upstream: 3000 ms for Drain, 200 ms for Drop, Pause and Resume, then EIO. 4.0.0's one direct caller, the plugin's `bluealsa_pause()`, passes 200 as upstream's does. |

Considered and not backported:
- f58b26b (4.1.0), 0bcebad and 3ee983c (4.2.0): rework of the plugin's local drain (wait until the
  ring buffer reaches the FIFO, `snd_pcm_abort()` support, a bounded local wait). 4.0.0's plugin
  drain does not wait locally (it sends Drain, which 907 now bounds), and 0bcebad builds on
  f58b26b and 4.2's plugin I/O thread. The cost is audio quality: the last fraction of a second
  of a stream can be cut at close. It does not hang.
- 0959403 (4.1.0, a separate client mutex per PCM): a restructuring that 906 works around by
  keeping `synced_mtx`.
- cccc177 (4.1.0): PCM open (also on the main loop) waits forever if an IO thread fails during
  setup. That is the open path, not drain; SBC setup fails only on an allocation or encoder-init
  error. Left as a known residual.
- 5466efc (4.1.0): fixes `ba_transport_stop()` as 4.1 rewrote it around a TERMINATED thread state.
  4.0.0 has no such state, and its stop asks the thread manager to cancel and then waits on the
  thread IDs.

## Round 17 (2026-10-04): squashfs images compressed with gzip, LZ4 and zstd

spruce asked for zlib: squashfs images made with `mksquashfs`'s default compressor, gzip, did not
mount (nearly all of PortMaster's runtimes; its 32-bit Godot 4.5 runtime is zstd). The built kernels (`System.map`) had only the XZ and LZO decompressors: `SQUASHFS_LZ4=y`
from round 8 had never taken effect either. Tina's `KERNEL_SQUASHFS_{XZ,LZ4,ZLIB}` are one choice,
the rootfs image's compressor (`config/Config-images.in`), and `build/kernel-defaults.mk` copied all
three into the kernel's configuration after config-4.9: the two not chosen arrived last as "is not
set" and switched those decompressors off.

| what | where | why |
|---|---|---|
| `020-kernel-config-4.9.patch` | `device/config/chips/a133/configs/aw3/linux/config-4.9` | `SQUASHFS_ZLIB=y`, `SQUASHFS_ZSTD=y`. `ZLIB_INFLATE` was already built in, so gzip adds only squashfs's zlib wrapper; zstd brings in the kernel's backported zstd decompressor (`lib/zstd`, hidden `ZSTD_DECOMPRESS` and `XXHASH`, no new prompts). |
| `134-kernel-keeps-squashfs-decompressors.patch` | `build/kernel-defaults.mk` | The choice's unchosen "is not set" lines are no longer copied, so config-4.9 decides which decompressors the kernel has: XZ, LZ4, LZO, gzip and zstd. The rootfs image stays XZ. |

`mods_version` 11 -> 12.

## Round 18 (2026-10-05): two slots and updates

| what | where | why |
|---|---|---|
| `boards/<board>/sys_partition.fex` | `rootfs` 600 -> 512 MiB; `boot_b` (15 MiB) and `rootfs_b` (512 MiB) added after it | a second slot for updates (`docs/updates.md`) |
| `scripts/add-boot-backups.py` | the finished image | second copies of boot0 (sector 256) and the U-Boot package (24576) |
| `scripts/make-update.py` | `builds/<stamp>-<board>/` | `oakmoss-<board>-<version>.omupd` from the finished image |
