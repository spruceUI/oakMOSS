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
| `020-kernel-config-4.9` | `device/config/chips/a133/configs/aw3/linux/config-4.9` | `NLS_UTF8=y`, FAT iocharset `utf8`, `VIDEO_SUNXI_VIN` off (Moss "changes not present in configs"); `BLK_DEV_LOOP=y` (MIN_COUNT 8), `INPUT_UINPUT=y`, `INPUT_JOYDEV=y`, `INPUT_FF_MEMLESS=y`, `SND_USB_AUDIO=m`, `XR829_WLAN=m`, `SQUASHFS_LZ4/LZO=y` (deps §7); the 21 `XRADIO*`/`XRMAC*`/`NF_LOG_COMMON`/`IPV6_FOU*`/`BT_XR_BLUEDROID_SUPPORT` symbols `olddefconfig` resolved once XR829 was on (the build's non-interactive `silentoldconfig` aborts on new prompts) | PortMaster loop mounts, gptokeyb uinput, joystick nodes, rumble, USB audio, onboard radio | Moss, deps, oakMOSS |
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
| `target/allwinner/generic/boot-resource/boot-resource/bootlogo.bmp` | `overlay/bootlogo.bmp` if present, else the SDK's original | Moss's logo is his; not shipped | oakMOSS |
| `package/add-rootfs-demo/{usr,etc}` | the whole `overlay/` (`/usr/magicx` with `bin/runmagicx.sh`, the SDL2 blobs, the `device` marker; `/etc/modules.d/net-xr829` empty; `/etc/init.d/wpa_supplicant` a no-op) plus `boards/<board>/overlay/`; `add-rootfs-demo` copies it into the rootfs and re-squashes, so these override what the packages installed | `/usr/magicx/device` is what the launcher reads to tell `zero28` from `zero40`; the empty modules file stops the XR829 driver autoloading and tearing down the Realtek 8189es's SDIO card (docs/hardware-notes.md); the init stub replaces wifimanager's S96 service, which started a second wpa_supplicant on wlan0 (empty `/etc/wifi/wpa_supplicant.conf`) that sent a DISCONNECT after every association the launcher's own supplicant made (Zero 28, 2026-09-16) - the launcher owns the radio | Moss, oakMOSS |
| `package/add-rootfs-demo/usr/magicx/tina_config.gz` | gzip of the build's `.config` | Moss's `install.sh` ships it in the image | Moss |
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
