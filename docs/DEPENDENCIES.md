> Dependency reference for the SD1 base: what spruceOS needs from it, and what oakMOSS ships.
> It began as the study written while bringing the image up (September 2026), against Moss's
> glibc 2.29 / GCC 7.4.1 userland on the Zero 28 and Zero 40, and it is the evidence behind the
> toolchain choice (docs/toolchain.md) and the config additions (docs/sdk-mods.md). Brought up to
> date for v0.4.2-beta.1 (2026-10-05): each section says where things stand first, and keeps the
> study's findings where they still explain a decision. spruceOS paths are from
> <https://github.com/spruceUI/spruceOS>; the checks dated 2026-10-04 are against its Development
> branch.

# MagicX A133P base image (SD1): dependencies

Boards: MagicX Mini Zero 28 (640x480), Zero 40 (480x800 portrait, AXS15205 touch) and XU20 V32
(1024x768, Hynitron touch). Allwinner A133P aarch64, kernel 4.9.191, PowerVR GE8300, AXP2202
PMIC. Radios: an XR829 (WiFi, and Bluetooth over UART) on the Zero 40, a Realtek RTL8189ES (WiFi
only) on the Zero 28 and XU20. Userland: glibc 2.38 and libstdc++ `GLIBCXX_3.4.32` /
`CXXABI_1.3.14` from the Arm GNU Toolchain 13.3 (`docs/toolchain.md`); the kernel is built with
the vendor's GCC 6.4. spruce lives on SD2: `/usr/magicx/bin/runmagicx.sh` hands off to
`/mnt/SDCARD/.tmp_update/updater` (or `magicx/init.sh`). Line numbers cited from the Tina SDK
(`sdk/lichee`, proprietary and untracked) are the study's; they are the only durable record of
those files.

## 1. Summary: what spruce needs, and the state today

Tier A is what spruce needs to boot at all, tier B its full feature set, tier C PortMaster.

| need | tier | v0.4.2-beta.1 |
|---|---|---|
| squashfs root with overlayfs (how SD1 itself boots: the vendor `BoardConfig.mk` builds rootfs, overlay and data as squashfs + ext4) | A | on |
| the hand-off (`runmagicx.sh`) and SDL2 under `/usr/magicx/lib`, where PyUI's `PYSDL2_DLL_PATH` points | A | shipped: oakMOSS's own `runmagicx.sh`; TrimUI's SDL2 2.26.1 with image, mixer and ttf |
| C runtime: `libc`, `libm`, `libpthread`, `libdl`, `librt`, `libutil`, `libcrypt`, `libresolv`, `libgcc_s`, the aarch64 loader | A | glibc 2.38 |
| a correctly named `libSDL2-2.0.so.0` for native programs (§2) | A | `/usr/magicx/lib/libSDL2-2.0.so.0` |
| GE8300 userspace, kernel modules and firmware (§4) | A | shipped (fbdev) |
| onboard WiFi (§5) | A | XR829 and RTL8189ES modules with firmware |
| TrimUI's daemons under `/usr/trimui` | A (study) | not needed: spruce's MagicX device files do not run them (§8.1) |
| Bluetooth: bluez, Bluetooth audio, the XR829's HCI path (§5) | B | bluez 5.54 with bluez-alsa 4.0.0 (round 16); Zero 40 headset audio tested |
| USB gadget: mass storage and ADB | B | on |
| exFAT on user cards over 32 GB | B | **open**: no in-kernel exFAT; FUSE is a module, and no `exfat-fuse` package exists |
| `INPUT_FF_MEMLESS` (rumble on external pads), `SND_USB_AUDIO` | B | on (`=y`, `=m`) |
| loop devices for PortMaster's runtimes | C | on, 8 at least |
| squashfs decompressors for those runtimes | C | XZ, LZO, LZ4, gzip and zstd (round 17) |
| `INPUT_UINPUT` (gptokeyb), `INPUT_JOYDEV` (`/dev/input/jsN` readers) | C | on |
| libstdc++ at `GLIBCXX_3.4.26` or newer (§3) | C | `GLIBCXX_3.4.32` |
| 32-bit (armhf) programs | C | the kernel runs them (`COMPAT=y`), but the base has no armhf loader or libraries; spruce carries a loader under `spruce/flip/`. Not run on these boards |
| PortMaster device profiles (§6) | C | **open**, on PortMaster's side |

## 2. spruce payload closure (the study)

Condensed: the study's full 214-file / 102-soname table is not reproduced. It came from running
`readelf -d`/`-V`/`--dyn-syms` over every aarch64 ELF that `Zero28.cfg`'s `PATH` and
`LD_LIBRARY_PATH` reach, in September 2026. The version notes are against the study's glibc 2.29
/ `GLIBCXX_3.4.24` ceiling; today's userland (glibc 2.38, `GLIBCXX_3.4.32`) meets every one of
them (§3).

| binary/lib | representative DT_NEEDED | class | version note |
|---|---|---|---|
| `spruce/flip/bin/python3.10` | libpthread, libdl, libutil, librt, libm, libc, `libpython3.10.so.1.0` | SHIPPED | GLIBC_2.17 |
| `spruce/flip/lib/libpython3.10.so.1.0` | libdl, librt, libm, libpthread, libutil, libc | SHIPPED | GLIBC_2.17; `_ssl`/`_hashlib`/`_sqlite3`/`_socket`/`_ctypes`/`array`/`math`/`zlib` all statically built in (confirmed via `nm -D` `PyInit_*` symbols), not separate `.so`s |
| `spruce/flip/lib/lib-dynload/_crypt*.so` | `libcrypt.so.1` | mixed | needs BASE-OS libcrypt.so.1 |
| `spruce/flip/lib/lib-dynload/_tkinter*.so` | bundled `libtcl8.6.so`/`libtk8.6.so` | SHIPPED | GLIBC_2.17 |
| `spruce/flip/lib/libSDL2-2.0.so` (**SONAME `libSDL2-2.0.so.0`, filename has no `.0`**; still so on Development, 2026-10-04) | libX11, libwayland-client, … | **broken by name**, see §3 and §8.2; on these boards the base's `/usr/magicx/lib` copy stands in | GLIBC_2.29 |
| `overlay/usr/magicx/lib/libSDL2{,_image,_mixer,_ttf}-2.0.so.0.*` | correctly named/symlinked | BORROWED (TrimUI Smart Pro / Moss-zero28) | GLIBC_2.29 max |
| `spruce/flip/lib/libavformat.so.58`, `libavutil.so.56`, `libmp3lame.so.0` | many | SHIPPED | GLIBC_2.38 |
| `spruce/flip/lib/{libsystemd,libxkbcommon,libwayland-egl++,liblzma,libvpx,libzstd,libdecor-0}` | — | SHIPPED | GLIBC_2.30–2.34 |
| `spruce/bin64/{busybox,curl,ffmpeg,rsync,ssh-keygen,jq,wget,…}` (47 tools) | mostly libc.so.6 only | SHIPPED | GLIBC_2.17–2.21 |
| `spruce/bin64/{fbfixcolor,gpiowait,setsharedmem,setsharedmem-flip}` | libc.so.6 | SHIPPED | GLIBC_2.34 (`__libc_start_main@GLIBC_2.34`, confirmed live with `readelf --dyn-syms`) |
| `RetroArch/ra64.universal` | libSDL2-2.0.so.0, libEGL, libGLESv2, libX11, libstdc++, libc | SHIPPED (bin); SDL2/EGL/GLESv2/libstdc++ → BASE-OS | GLIBCXX_3.4.26 |
| cores64 sample (genesis_plus_gx, snes9x, fbneo, fceumm, gpsp, mgba, mupen64plus_next, fake08, pcsx_rearmed, …; 91 cores total) | libc/libm/libstdc++/libz | SHIPPED | ≤GLIBCXX_3.4.21 except `swanstation_libretro.so` (3.4.26) |
| `Emu/PSP/PPSSPPSDL_TrimUI` | libSDL2-2.0.so.0, libEGL, libGLESv2, libstdc++, libc | SHIPPED; SDL2/EGL/GLESv2/libstdc++ → BASE-OS | GLIBCXX_3.4.24/CXXABI_1.3.11 |
| `Emu/PS/pcsx_64` | bundled libSDL-1.2.so.0, BASE-OS libasound.so.2, libpng16, libc | SHIPPED (SDL1.2 self-contained) | GLIBC_2.17 |
| `Emu/NDS/drastic64`, `Emu/NDS/dsperate` | libSDL2-2.0.so.0, libstdc++, libc | SHIPPED; SDL2/libstdc++ → BASE-OS | low GLIBCXX |
| `Emu/N64/mupen64plus/*` (13 files) | libSDL2-2.0.so.0, libstdc++, libc | SHIPPED; SDL2/libstdc++ → BASE-OS | GLideN64/glide64mk2 need GLIBCXX_3.4.26 |
| `Emu/SATURN/yabasanshiro`, `Emu/DC/flycast` | libstdc++, libc + bundled libs (flycast bundles OpenSSL 1.1) | SHIPPED; libstdc++ → BASE-OS | GLIBCXX_3.4.26 |
| `App/Moonlight/…/moonlight`,`love` (+20 bundled libs incl. OpenSSL 3.x) | SDL2 via liblove, libavcodec, libcurl, libssl.so.3 | SHIPPED (self-contained); SDL2 → BASE-OS | max GLIBC_2.30, GLIBCXX_3.4.21 |
| `spruce/smartpro/inputd/trimui_inputd` (patched, drops left-stick range check) | libm, libpthread, libgcc_s, libc | SHIPPED, TrimUI only (`TRIMUI_INPUTD_PATCHED` is exported by `SmartPro.cfg`) | GLIBC_2.17 |
| `Emu/SCUMMVM/scummvm_64.7z`, `App/PortMaster/portmaster.7z` | n/a — still packaged | n/a | not inspectable until extracted at runtime |

Sonames spruce leaves to the base (absent from every aarch64 directory of the spruceOS tree the
study checked): `libc.so.6`, `libm.so.6`, `libpthread.so.0`, `libdl.so.2`, `librt.so.1`,
`libutil.so.1`, `libcrypt.so.1`, `libresolv.so.2`, `ld-linux-aarch64.so.1`, `libEGL.so.1`,
`libGLESv2.so.2`, `libdrm.so.2`, `libudev.so.1`, `libasound.so.2`, `libfreetype.so.6`,
`libfontconfig.so.1`, `libffi.so.8`, `libtinfo.so.6`/`libncursesw.so.6`, `libgcc_s.so.1`, and,
per the SONAME finding above, effectively `libSDL2-2.0.so.0` and `libstdc++.so.6`. The v0.4.2-beta.1
root filesystem provides all of them except `libdrm.so.2` and `libfontconfig.so.1` (neither
package is built) and `libffi.so.8` (it has `libffi.so.7`); its libpng is 1.2 (`libpng12.so.0`),
not 1.6.

## 3. glibc / GLIBCXX

**Today:** glibc 2.38 and libstdc++ `GLIBCXX_3.4.32` / `CXXABI_1.3.14`. Every requirement the
study found is met: up to `GLIBC_2.38` in spruce's own bundle, `GLIBCXX_3.4.26` in RetroArch,
several cores and emulators, and PortMaster's Godot/FRT and Solarus runtimes. None of the gaps
below remains; they are why oakMOSS left Moss's toolchain for the Arm GNU Toolchain 13.3
(`docs/toolchain.md`).

The study's findings, against Moss's glibc 2.29 / GCC 7.4.1 Linaro (and the GCC 7.5.0 stand-in
it was built with), whose libstdc++ stops at `GLIBCXX_3.4.24` / `CXXABI_1.3.11`
(`phase2.config:398-408`: `CONFIG_GLIBC_USE_VERSION_2_29=y`, `CONFIG_GCC_USE_VERSION_7_4_LINARO=y`):

- Nothing in the closure exceeded `CXXABI_1.3.11`.
- Six SHIPPED aarch64 binaries need `GLIBCXX_3.4.26` (GCC ≥9 libstdc++, none bundling their
  own): `RetroArch/ra64.universal`, `RetroArch/.retroarch/cores64/{flycast,swanstation}_libretro.so`,
  `Emu/DC/flycast`, `Emu/N64/mupen64plus/{mupen64plus-video-GLideN64,mupen64plus-video-glide64mk2}.so`,
  `Emu/SATURN/yabasanshiro`. They would not link against GCC 7's libstdc++. `PPSSPPSDL_TrimUI`
  sat exactly at the ceiling (`GLIBCXX_3.4.24`).
- Four SHIPPED aarch64 tools need `GLIBC_2.34`: `fbfixcolor`, `gpiowait`, `setsharedmem`,
  `setsharedmem-flip` (`spruce/bin64/`). Their crt object comes from a glibc ≥2.34 toolchain,
  so glibc 2.29 refused them ("version `GLIBC_2.34' not found").
- The `spruce/flip/lib/*` bundle (python3.10's ffmpeg, audio and wayland stack) mixes
  GLIBC_2.30 through 2.38: `libavformat.so.58`/`libavutil.so.56`/`libmp3lame.so.0` at 2.38,
  `libsystemd`/`libxkbcommon`/`liblzma`/`libvpx`/`libzstd`/`libdecor-0` at 2.30–2.34. Not on the
  hot path unless dlopened (Tkinter, ffmpeg features).
- The GE8300 userspace blobs (`libEGL.so`, `libGLESv2.so`, `libIMGegl.so`, `libsrv_um.so`,
  `libusc.so`, `libpvrNULL_WSEGL.so`) need only `GLIBC_2.17`; `libglslcompiler.so` also needs
  `libstdc++.so.6` at the unversioned `GLIBCXX_3.4`. No GPU-driver blocker (checked with
  `readelf --dyn-syms` against `sdk/lichee/package/libs/libgpu/ge8300/fbdev/glibc/lib64/*.so`).
- spruce's own `python3.10`/`libpython3.10.so*` need only `GLIBC_2.17`.
- PortMaster: the sampled port `2048_libretro.so.aarch64` needs `GLIBC_2.33`. The sampled shared
  runtimes `runtimes/frt_3.3.4` (Godot/FRT, the most shared runtime in the catalog) and
  `runtimes/solarus-1.6.5` both need `GLIBCXX_3.4.26`. `port.json`'s `min_glibc` gate is enforced
  live (`harbour.py:1160-1164`, against `hardware.py:272-314`'s `libc.so.6 --version` probe), but
  there is no `min_glibcxx` field: a libstdc++ mismatch is only discovered at run time, as a
  dynamic-linker failure.

The study's conclusion (since acted on): glibc 2.29 was adequate for almost everything spruce
ships; the libstdc++ ceiling was the real risk, two minor versions behind what
GLideN64/flycast/yabasanshiro/swanstation and the Godot/FRT runtime need. The options it gave were
a newer `libstdc++.so.6` ahead of the system one, or giving those up; oakMOSS took a third, a whole
userland on a newer toolchain.

## 4. GPU userspace (PowerVR GE8300)

**Today:** shipped as the study found it in the SDK: fbdev, no DRM, `libgpu` and
`kmod-ge8300-km` on, firmware `rgx.fw`/`rgx.sh` 22.102.54.38 in `/lib/firmware`. The kernel now
also rotates the framebuffer in hardware (see the last point).

- Kernel module: `sdk/lichee/package/kernel/gpu-km/Makefile:36-50` selects
  `PKG_NAME:=ge8300-km` for `TARGET_PLATFORM` in `mr813 r818 a133`, building `pvrsrvkm.ko` +
  `dc_sunxi.ko` from
  `lichee/linux-4.9/modules/gpu/img-rgx/linux/rogue_km/binary_sunxi_linux_nullws_release/target_aarch64/`.
- Userspace package: `package/libs/libgpu/Makefile:27-28` auto-selects `GPU_TYPE=ge8300` for
  `a133`; `DEPENDS:=+kmod-ge8300-km +libstdcpp +zlib` (L45-46); the window system is **fbdev**,
  not wayland/DRM, because `CONFIG_WESTON_DRM` is off (Makefile L52-56; `libdrm` is off too).
- Blob directory `package/libs/libgpu/ge8300/fbdev/glibc/lib64/`: `libEGL.so(.1)`,
  `libGLES_CM.so(.1)` (ES1.1), `libGLESv2.so(.2)`, `libIMGegl.so`, `libglslcompiler.so`,
  `libsrv_um.so`, `libusc.so`, `libtqvalidate.so`, `libufwriter.so`, `libpvrNULL_WSEGL.so`,
  `libPVROCL.so(.1)` + `libOpenCL.so` symlink, `libPVRScopeServices.so`, `libVK_IMG.so(.1)`,
  `libvulkan.so(.1)` (Vulkan 1.x present); `bin/{pvrsrvctl,ocl_unit_test}`;
  `firmware/{rgx.fw.22.102.54.38,rgx.sh.22.102.54.38}` -> `/lib/firmware`. DDK per `aw_version`:
  "img-rgx: add 1.19 ddk". OpenCL is off.
- **The SDL2 that spruce, PyUI and RetroArch need**, cross-validated against an independent port
  for this device: `knulli-linux/board/allwinner/a133/magicx-zero-28/` and `.../magicx-zero-40/`.
  Their `patches/sdl2/001-add-pvr-ge8300-mali-driver.patch` adds a `SDL_MALI`/`CheckMali` CMake
  option that compiles SDL2's `src/video/mali-fbdev/*.c` backend against `<EGL/egl.h>`
  (`-DLINUX -DEGL_API_FB`): SDL2 with the mali-fbdev video backend pointed at the GE8300's own
  EGL/GLESv2, `SDL_VIDEODRIVER=mali`, the pattern `App/PyUI/launch.sh:133-162` documents for the
  Anbernic XX (H700/Mali) line. Knulli ships byte-identical `rgx.fw.22.102.54.38` /
  `rgx.sh.22.102.54.38`: the same vendor DDK build.
- Kernel-side fbdev is present and sufficient: `CONFIG_FB=y` (config-4.9 L2333),
  `CONFIG_DISP2_SUNXI=y` (L2375); `CONFIG_DRM=y`/`DRM_KMS_HELPER` exist but this fbdev-only GPU
  path does not use them. `CONFIG_PACKAGE_libdrm` is off in the vendor defconfig and every config
  since, consistent with fbdev only.
- **Framebuffer rotation:** the study found hardware rotation not built
  (`CONFIG_SUNXI_DISP2_FB_DISABLE_ROTATE=y`, config-4.9 L2376-2377), so the Zero 28's portrait
  panel needed rotation in software. It is built now: G2D rotation on every flip
  (`CONFIG_SUNXI_DISP2_FB_HW_ROTATION_SUPPORT=y`, tree patches `100` and `101`, rounds 11 and 13 in
  `docs/sdk-mods.md`), from the vendor patch in MagicX's a133 Tina BSP update of 2025-10-11. Each
  board turns it on in its device tree: the Zero 28 a quarter turn, the XU20 a half turn.

## 5. WiFi / BT / audio / input stack

- **WiFi.** Today: `XR829_WLAN=m` with `kmod-net-xr829` and `xr829-firmware` for the Zero 40
  (the 26 MHz variant: `kmod-net-xr829-40M` and `XR829_USE_40M_SDD` stay off, §8.4), and
  `RTL8189ES=m` for the Zero 28 and XU20. The study found the XR829 off everywhere: kernel
  `config-4.9:1262-1263` (`# CONFIG_XR819_WLAN / CONFIG_XR829_WLAN is not set`, full driver at
  `lichee/linux-4.9/drivers/net/wireless/xr829/`), and `kmod-net-xr829`, `kmod-net-xr829-40M` and
  `xr829-firmware` off in the vendor defconfig (L3542, L2917) and both phase configs (phase1
  L3143; phase2 L3129, L2590), though the blobs exist at `package/firmware/linux-firmware/xr829/`.
  Knulli's `etc/init.d/S03modules:1-15` picks between a generic `xradio_{core,mac,wlan}.ko` build
  and a TrimUI Smart Pro `_tsp.ko` variant by board name; the MagicX boards take the generic one.
- **Bluetooth.** Today: bluez 5.54 (`bluez-libs`, `bluez-daemon`, `bluez-utils`,
  `bluez-utils-extra`), dbus 1.10.4, `XR829_BT=y`, and bluez-alsa 4.0.0 (round 16, with upstream
  drain fixes backported; the SDK's 2018 snapshot wedged). The XR829's Bluetooth is on UART
  `/dev/ttyS1`; spruce attaches it and starts `bluealsa` itself, nothing in the base does. Zero 40
  headset audio was tested on 2026-10-04; the Zero 28 and XU20 have no Bluetooth. The study found
  the vendor defconfig with Bluetooth on (`bluez-libs=y` L3986, `bluez-alsa=y` L4395,
  `bluez-daemon=y` L5328, `bluez-utils(-extra)=y` L5331-5332, `dbus=y` L5346) and Moss's phase
  configs with every bluez package and `CONFIG_XR829_BT` off (phase2 L3573, L3982, L4647-4651),
  while spruce's TrimUI A133P device file started `/etc/bluetooth/bluetoothd` unconditionally.
  The vendor HCI attach scripts are `package/allwinner/bluetooth/xradio/hciattach_xr829.init` and
  `package/allwinner/btmanager/config/xradio_bt_init.sh`.
- **wpa_supplicant / hostapd:** one package, `package/network/services/hostapd/Makefile`
  `PKG_VERSION:=2017-11-08` (wpa_supplicant 2.6/2.7 era), internal TLS
  (`CONFIG_WPA_SUPPLICANT_INTERNAL=y`). `wpa-supplicant` and `wpa-cli` are on; `hostapd` is off
  since round 8, with `softap`, whose Makefile injected `CONFIG_NF_CONNTRACK=y`
  (`docs/sdk-mods.md`). `wireless-tools` is off (the vendor default); spruce uses
  `ip`/`wpa_cli`/`jq`.
- **Audio:** `alsa-lib` 1.1.4.1; `CONFIG_SND_SOC=y` (config-4.9 L2496); `CONFIG_SND_USB_AUDIO=m`
  since round 8 (the study found it off, L2486).
- **Input:** `libevdev` 1.4.6 and `libinput` 1.5.0 on, with eudev's `libudev.so.1`. Since round
  15 the touch controllers (`axs_ts`, `hyn_ts`) are tagged as touchscreens in udev
  (`overlay/etc/udev/rules.d/60-oakmoss-touchscreen.rules`), which libudev users need, and the
  kernel drops repeated multitouch values, so a held touch stays held.
- **Library versions** (the study): `zlib` 1.2.8 (1.3.1 since round 18, tree patch 135), `libpng` 1.2.56 (the old 1.2 branch, not 1.6),
  `libjpeg` (IJG) 9a, `freetype` 2.6.1, `bluez` 5.54, `dbus` 1.10.4. `libffi` is `libffi.so.7`.
- **SDL2 is not a Tina package**: only SDL 1.2 (`package/multimedia/sdl/Makefile`), and it is
  off. spruce, PyUI and RetroArch bring SDL2 themselves, and the base ships TrimUI's SDL2 2.26.1
  under `/usr/magicx/lib` (§1, §2).

## 6. PortMaster

Not re-checked against PortMaster since the study (PortMaster-GUI, September 2026), apart from
the runtime compressors (§8.8). On spruce's side, all three boards have platform files now
(`Zero28.cfg`, `Zero40.cfg`, `XU20.cfg`).

**Detection is two separate, disagreeing code paths:**
- **Bash** (`PortMaster/device_info.txt`): `L52-54` checks `/mnt/SDCARD/spruce` *first* (commit
  `ef16b68`, "check for spruce first because of our dArkOS shenanigans") and sets
  `CFW_NAME=spruce`. `L234` computes `RESOLUTION` with a live SDL probe
  (`sdl_resolution.$DEVICE_ARCH`), so each board gets its real resolution and aspect without a
  profile. The `L276-495` `FIXES` case statement (hand overrides for `ANALOG_STICKS`/`DEVICE_CPU`/
  `DEVICE_NAME` per known board) has no MagicX branch: an A133P board's `DEVICE_NAME` falls
  through to a generic devicetree-model parse, and since `CFW_NAME=spruce`, the TrimUI override
  does not fire either. The MagicX boards very likely report the same raw `DEVICE_NAME=sun50iw10`
  that Brick/TSP/BrickPro do under spruce. `ANALOG_STICKS` defaults to 2 with no override (right
  for the Zero 28, not for the Zero 40 with one stick or the XU20 with none).
- **Python** (`harbourmaster/hardware.py`): a static table, no live probe, and no
  `/mnt/SDCARD/spruce` check (`git log` shows no spruce-related commits upstream). `PlatformSpruce`
  (PR #337, `platform.py:1277-1309`) is unreachable in stock upstream; the TrimUI Smart Pro reaches
  it only because spruce ships a patched `hardware.py`/`platform.py` on the card. `HW_INFO`
  (`hardware.py:103-193`) has no MagicX key, so an unprofiled device falls to `"default"`
  (`L192-193`): `{"resolution":(640,480),"analogsticks":2,"cpu":"unknown","capabilities":["opengl","power"]}`,
  the bug already measured on the TrimUI Smart Pro (`device=unknown`, a wrong `opengl` tag). The
  Zero 28 happens to match the default resolution; the Zero 40 (480x800) and XU20 (1024x768) get
  the wrong one.
- Tag machinery (`hardware.py:647-732`, `expand_info`): `display_ratio` via gcd (4:3 for the Zero
  28 and XU20, 3:5 for the Zero 40, which has no built-in curation), `analog_0..N`,
  `lowres`/`hires`/`wide`, RAM-tier tags. `harbour.py:1142-1189` + `util.py:700-730` AND-match a
  port's `"reqs"` tags (e.g. `ports/air/port.json: "reqs":["4:3"]`,
  `ports/aquaria/port.json: "reqs":["!lowres","analog_1"]`) against these.
- **Proposed profiles** (schema per `hardware.py:30-193`), not taken up:
  `DEVICES["MagicX Mini Zero 28"] = {"device":"zero28","manufacturer":"MagicX","cfw":["spruce"]}`,
  `HW_INFO["zero28"] = {"resolution":(640,480),"analogsticks":2,"cpu":"a133p","capabilities":[],"ram":1024}`
  (no `"opengl"`: the GE8300 is GLES-only); the Zero 40 likewise with
  `{"resolution":(480,800),"analogsticks":1,...}` and the XU20 with
  `{"resolution":(1024,768),"analogsticks":0,...}` (RAM to be measured, §8.9). Both code paths
  would need the `/mnt/SDCARD/spruce` check to reach them, and the bash `FIXES` table MagicX
  branches so the boards stop colliding with Brick/TSP's `sun50iw10`.
- **Runtime and mount needs.** Today's base: loop devices (8 at least), squashfs with XZ, LZO,
  LZ4, gzip and zstd, and a BusyBox with `losetup`, `stat`, `sha1sum`, `unzip` and `tar -z` (no
  `bc`); with glibc 2.38 the PATH `unzip` that needs `GLIBC_2.34` loads. Still to check on these
  boards: `/dev/shm` at boot (`TODO.md`). The study's measurements on other spruce devices: loop
  mounts worked everywhere except the armv7l A30; the TSPS wants 16+ loop devices where 8 exist;
  `losetup` was missing on BusyBox-heavy units; `/dev/shm` was shadowed or missing on the TSPS,
  where `pm_message` (called by 375 ports) hangs; BusyBox 1.27.2 rejects `find -quit` (8 ports)
  and `mv/cp -T` (3); `tar` without `-z` broke 9 ports. `gptokeyb` ships with spruce
  (`spruce/bin64/gptokeyb`) and needs only `/dev/uinput`. `xdelta3` is not a system dependency:
  sampled ports (e.g. `HFTSR.zip`) bundle their own static aarch64 copy.
- **Library patterns** (the study's `PortMaster-New`/`common/pm` sampling): ports overwhelmingly
  bundle their own SDL1/SDL2-family and codec/format libs (libvorbis, libmodplug, libFLAC,
  libwebp, liblzma, libjpeg, libtiff, libmikmod, libfluidsynth, libphysfs, libssl/libcrypto,
  libzip); they expect the base for `libc`/`libm`/`libpthread`/`libdl`/`libgcc_s`, GLES/EGL, ALSA
  and the CFW's `libSDL2-2.0.so.0`. Desktop-GL-only ports often bundle a **gl4es** shim
  (`antecrypt`, `counter-strike`, `pigments`, `wratchsden`) to run on the GLES-only GE8300; a few
  (`xroar`) bundle a raw `libGL.so.1` instead, unlikely to work without testing.
- **Port categories.** No longer blocked by the base: Godot/FRT and Solarus (libstdc++, and
  their gzip runtimes since round 17) and libretro cores needing a newer glibc
  (`2048_libretro.so.aarch64`, `GLIBC_2.33`); none of these has been run on these boards yet.
  Still out or untested: x86/x86_64 ports; armhf ports, which depend on spruce's armhf loader (the
  study counted 204 across spruce devices); desktop-OpenGL-only ports without a gl4es shim; ports
  gated on aspect or `wide` tags until device profiles exist; heavy mono/Godot 4.x/dotnet bundles
  until RAM and CPU are measured (§8.9).

## 7. Config changes: the study's list, and what was applied

Kernel (`sdk/lichee/device/config/chips/a133/configs/aw3/linux/config-4.9`, changed through
`sdk-patches/tree/020`; the study's line numbers). Every one of these was also on in Knulli's
`linux-sunxi64-legacy.config` for these boards (a different, newer kernel base: corroboration of
the requirement, not a config to copy):
```
L956  CONFIG_BLK_DEV_LOOP=y          # on since round 8 (BLK_DEV_LOOP_MIN_COUNT=8)
L1424 CONFIG_INPUT_UINPUT=y          # on since round 8
L1300 CONFIG_INPUT_JOYDEV=y          # on since round 8
L1291 CONFIG_INPUT_FF_MEMLESS=y      # on since round 8
L2486 CONFIG_SND_USB_AUDIO=m         # on since round 8
L1263 CONFIG_XR829_WLAN=m            # on since round 8
```
squashfs: the study found only XZ (`SQUASHFS_ZSTD`/`LZ4`/`LZO` off, L3459-3462). Round 8 set
`SQUASHFS_LZ4/LZO=y`, but only LZO took effect; since round 17 the kernel reads XZ, LZO, LZ4,
gzip and zstd (`ZLIB` and `ZSTD` added in `020`, and `134` stops the rootfs compressor choice
from switching the others off). exFAT: still none in the kernel, Tina's or Knulli's newer sunxi64
tree; the route is FUSE (`CONFIG_FUSE_FS=m`, L3390) plus an `exfat-fuse`/`exfatprogs` userspace,
not built yet (`TODO.md`). `CONFIG_MODVERSIONS` is still off (L267): a prebuilt `.ko` (spruce's
own `zram.ko`/`lzo.ko`/`zsmalloc.ko`, or a prebuilt xr829/GE8300 module) must come from a kernel
with an identical version and config to `insmod`, a build-process constraint rather than a
config line. Since round 8 the image carries `zram`, `zsmalloc`, LZ4 and LZO itself.

Packages (the study measured these against Moss's `phase2.config`; `phase1.config`'s package set
is identical but for `cortana-demo`/`cortana-sdk`). The build uses
`configs/ext-armgnu13.config`:
```
CONFIG_PACKAGE_kmod-net-xr829=y        # on
CONFIG_PACKAGE_kmod-net-xr829-40M=y    # off: the 26 MHz variant is built (§8.4)
CONFIG_PACKAGE_xr829-firmware=y        # on
CONFIG_XR829_USE_40M_SDD=y             # off (§8.4)
CONFIG_PACKAGE_bluez-libs=y            # on
CONFIG_PACKAGE_bluez-alsa=y            # on; 4.0.0 since round 16
CONFIG_PACKAGE_bluez-daemon=y          # on
CONFIG_PACKAGE_bluez-utils=y           # on
CONFIG_PACKAGE_bluez-utils-extra=y     # on
CONFIG_XR829_BT=y                      # on
```
Everything else the study checked (`libgpu`, `kmod-ge8300-km`, `alsa-lib`, `libevdev`,
`libinput`, `libexpat`, `libffi`, `dbus`, `wpa-supplicant`, `zlib`, `libpng`, `libjpeg`,
`freetype`) is on, as it was in both phase configs; `hostapd` is off since round 8 (§5).

## 8. Open questions

1. **`/usr/trimui/bin` on MagicX hardware.** *Settled.* The study found spruce's MagicX boards
   sharing the TrimUI A133P device file, whose `run_trimui_blobs` expects TrimUI's
   `trimui_inputd`/`trimui_scened`/`trimui_btmanager`/`hardwareservice`/`musicserver` in
   `/usr/trimui/bin`, which MagicX's firmware does not have. spruce's MagicX boards now have their
   own device files (`Zero28.sh`, `Zero40.sh`, `XU20.sh`, `magicx_a133p.sh`), and none of them
   runs those daemons (Development, 2026-10-04).
2. **`spruce/flip/lib/libSDL2-2.0.so` filename/SONAME mismatch** (§2). *Still in spruce*
   (Development, 2026-10-04): it defeats the "spruce brings its own SDL2" fallback for every
   native (non-PyUI) consumer. On these boards the base's `/usr/magicx/lib/libSDL2-2.0.so.0`
   stands in.
3. **No Zero 40 platform in spruce, and touch unresolved.** *Settled.* spruce has
   `Zero40.cfg`/`Zero40.sh` (and the XU20's). Touch works through our kernel's drivers
   (`sdk-patches/tree/080-*`, round 10), loaded as modules after boot, and since round 15 also in
   programs that read it themselves, such as DraStic. (Knulli's Zero 40 kernel config enabled no
   touchscreen driver at the time.)
4. **XR829 crystal (26 MHz vs 40 MHz SDD).** *Open.* Only the Zero 40 has an XR829; the Zero 28
   and XU20 carry an RTL8189ES. The 26 MHz variant is built, and WiFi and Bluetooth both work on
   it; the crystal itself is unconfirmed (`docs/hardware-notes.md`).
5. **An earlier note claimed Moss disabled wpa-supplicant, dbus, libinput, the wireless drivers,
   libexpat and libffi.** *Closed.* The two phase configs on disk showed all of them on; only the
   bluez set (and the vendor-default-off `wireless-tools`/`kmod-net-xr829`/`xr829-firmware`)
   differed. oakMOSS builds from its own `configs/ext-armgnu13.config` in any case.
6. **The `/usr/magicx/device` marker.** *Settled.* Every image writes it (`zero28`, `zero40` or
   `xu20`), and spruce tells the boards apart by it.
7. **Toolchain substitution.** *Superseded.* The study ran on `phase2-gcc750.config` (vanilla GCC
   7.5.0) because the Linaro 7.4.1 tarball was unfetchable; both stop at `GLIBCXX_3.4.24`. The
   build now uses the Arm GNU Toolchain 13.3 (`configs/ext-armgnu13.config`, `docs/toolchain.md`);
   the phase configs remain only as a fallback.
8. **PortMaster runtime squashfs compressor.** *Settled* (2026-10-04). The study sampled two
   runtimes, `frt_3.3.4` and `solarus-1.6.5`, and took them for XZ-compatible; both are gzip.
   Read from 46 PortMaster runtimes (2022-2026): 45 are gzip, and one, the 32-bit Godot 4.5, is
   zstd. The kernel read only XZ and LZO until round 17, which added gzip, LZ4 and zstd.
9. **RAM/CPU headroom** for heavy PortMaster runtimes (mono, Godot 4.x, dotnet). *Open:* not
   measured on these boards; `HW_INFO`'s `ram` figure (used for the `Ngb` capability tags) needs a
   real number before the profiles in §6 are final.

## 9. What spruce relies on beyond the study (2026-09-26 .. 10-04)

Added after the study, from bench work with spruceOS on all three boards:

- **One key code per press.** Images from 2026-09-26 on no longer give A a second code
  (353), nor the XU20's B and MENU (158, 256). spruce checks the pad's key bitmap at run
  time: if 353 is still listed, it is running on an older image and also accepts the second
  codes, so one spruce card works on both. The XU20's extra face button is `KEY_HOMEPAGE`
  (172).
- **Rumble through sysfs GPIO.** spruce drives the motor on PH3 through `/sys/class/gpio`,
  which needs `CONFIG_GPIO_SYSFS` (on since 2026-09-26). The Zero 28 has no motor.
- **Real suspend-to-RAM.** spruce's platform files choose it per board
  (`MAGICX_REAL_SLEEP=1`), and the XU20 suspends its devices one at a time
  (`MAGICX_PM_ASYNC=0`). On the SDK chain it needs the I2C bus-error fix
  (`sdk-patches/tree/130-*`) in the image: without it, the XU20 froze on the way into sleep
  with the touch driver loaded. On its stock boot chain (images before 2026-09-28) the XU20
  slept without it on the bench.
- **Charge mode stays in the base.** When U-Boot boots for the charger, the base shows its
  own charge screen instead of starting the launcher, and hands off only when the power key
  is pressed. spruce needs nothing for this.
- **Touch in programs that read it themselves** (round 15, 2026-10-02): the kernel drops
  repeated multitouch values, and udev tags the touch controllers as touchscreens, which
  libudev users such as trngaje's advdrastic need (§5).
- **Bluetooth audio** (round 16, 2026-10-03): bluez-alsa 4.0.0 with `bluealsa`,
  `bluealsa-aplay`, `bluealsa-cli`, the ALSA plugins (`/usr/lib/alsa-lib`) and the D-Bus policy
  for `org.bluealsa`. Nothing in the base starts it; spruce starts `bluealsa` (`-p a2dp-source`).
- **squashfs with gzip, LZ4 and zstd** (round 17, 2026-10-04): PortMaster's runtimes mount.
- **The spruceOS pairing:** images from v0.4.1-beta.1 on pair with spruceOS v4.5.0 or a newer
  nightly (`docs/status.md`).
