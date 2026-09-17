> Dependency study written while bringing this image up (September 2026), against the
> spruceOS tree and the Tina SDK. It is the evidence behind the toolchain choice
> (docs/toolchain.md) and the config additions (docs/sdk-mods.md); spruceOS paths cited
> below are from <https://github.com/spruceUI/spruceOS>.

# Zero28/Zero40 Tina base-image (SD1) dependency spec

Target: MagicX Mini Zero 28 (640x480 4:3) and Zero 40 (480x800 portrait, touch),
Allwinner A133P aarch64, glibc 2.29 / GCC 7.4.1 Linaro (Tina `phase2.config`),
kernel 4.9.191, PowerVR GE8300, XR829 WiFi/BT, AXP2202 PMIC. spruce lives on
SD2; the base image's `/usr/magicx/bin/runmagicx.sh` chains to
`/mnt/SDCARD/.tmp_update/updater`. All line numbers below are from the files
named; the Tina SDK at `sdk/lichee` is proprietary and untracked, so
citations there are the only durable record.

Toolchain note (detail in §8.7): the real Linaro 7.4.1 tarball is currently
unfetchable, so the buildable config today is `phase2-gcc750.config` (vanilla
GCC 7.5.0), package-identical to `phase2.config`. Both cap libstdc++ at
`GLIBCXX_3.4.24`/`CXXABI_1.3.11`, so findings citing "glibc 2.29 / GCC 7.4.1"
below apply equally to the 7.5.0 substitute.

## 1. Summary: must-have list, in priority tiers

**Tier A — spruce boots at all (base image + rootfs mechanics)**
- Kernel: `CONFIG_SQUASHFS=y`, `CONFIG_OVERLAY_FS=y` (both already on, §7) — the vendor `BoardConfig.mk` builds this board's rootfs/overlay/data partitions as squashfs+ext4 hybrids (`sdk/lichee/target/allwinner/a133-aw3/BoardConfig.mk` L3-4, L6-7), so these aren't optional extras, they're how SD1 itself boots.
- `/usr/magicx/bin/runmagicx.sh` (already staged, `overlay/usr/magicx/bin/runmagicx.sh` L1-22) and the borrowed SDL2 blobs at `usr/magicx/lib/*` it points `PYSDL2_DLL_PATH` at (`App/PyUI/launch.sh:348`).
- `/usr/trimui/bin/{trimui_inputd,trimui_scened,trimui_btmanager,hardwareservice,musicserver}` and `/usr/trimui/lib/*` — **OPEN QUESTION, see §8**: `device_functions/trimui_a133p.sh:199` calls `run_trimui_blobs` which does `cd /usr/trimui/bin || return 1` (`trimui_delegate.sh:264`); MagicX is not TrimUI hardware and no evidence was found its Tina firmware ships anything at that path. If it doesn't, spruce's whole button-input daemon chain silently never starts on Zero28/40.
- BASE-OS `libc.so.6`/`libm.so.6`/`libpthread.so.0`/`libdl.so.2`/`librt.so.1`/`libutil.so.1`/`libcrypt.so.1`/`ld-linux-aarch64.so.1`/`libgcc_s.so.1` — needed by `flip/bin/python3.10` (PyUI's interpreter) and every spruce-shipped `bin64` tool.
- **BASE-OS `libSDL2-2.0.so.0` (a real, correctly-versioned shared object)** — see §2/§3: spruce's own copy at `spruce/flip/lib/libSDL2-2.0.so` has the right `SONAME` but the wrong on-disk filename, so every native (non-PyUI) consumer (RetroArch, PPSSPP, drastic, mupen64plus, flycast, Moonlight, gptokeyb, …) resolves `libSDL2-2.0.so.0` from the base OS. Without it, nothing renders except PyUI (`PYSDL2_DLL_PATH`/ctypes, a separate lookup).
- BASE-OS GE8300 userspace: `libEGL.so.1`, `libGLESv2.so.2`, `libIMGegl.so`, `libsrv_um.so`, `libusc.so`, `libglslcompiler.so` + `pvrsrvkm.ko`/`dc_sunxi.ko` + `rgx.fw.22.102.54.38` firmware (§4). `CONFIG_PACKAGE_libgpu=y`/`CONFIG_PACKAGE_kmod-ge8300-km=y` are already on in vendor defconfig and both phase configs — no delta needed, just confirmation it isn't disabled.
- BASE-OS onboard WiFi: XR829 kernel driver + firmware, currently OFF (§5/§7) — spruce/PyUI expect a working `wlan0` for its whole networking stack.

**Tier B — spruce full feature set (Bluetooth, USB modes, external storage)**
- `bluez-daemon`/`bluez-libs`/`bluez-utils`/`bluez-alsa` + the XR829 BT HCI path — currently disabled by Moss's phase configs (§5, §7) even though `trimui_a133p.sh:196` unconditionally starts `/etc/bluetooth/bluetoothd`.
- USB gadget: mass storage + ADB via configfs — already enabled (§7).
- exFAT for SD2 cards >32GB — no in-kernel path exists anywhere checked (Tina 4.9.191 kernel, Knulli's newer sunxi64 kernel for the same board); needs FUSE (`CONFIG_FUSE_FS` already `=m`) + an `exfat-fuse`/`exfatprogs` userspace package, not found anywhere in the Tina package tree.
- `CONFIG_INPUT_FF_MEMLESS`, `CONFIG_SND_USB_AUDIO` — external controller rumble / USB audio dongles, both currently off.

**Tier C — PortMaster maximum compatibility**
- `CONFIG_BLK_DEV_LOOP=y` — currently OFF; PortMaster cannot mount any `runtimes/*.squashfs` without it (§6, §7).
- `CONFIG_INPUT_UINPUT=y`/`m` — currently OFF; `gptokeyb` (already shipped, `spruce/bin64/gptokeyb`) needs `/dev/uinput` to inject virtual-pad input.
- `CONFIG_INPUT_JOYDEV=y` — currently OFF; several bundled engines still read `/dev/input/jsN` directly.
- A base-OS `libstdc++.so.6` newer than GCC 7.4.1/7.5.0's (§3/§6) — the single biggest PortMaster compatibility gap found: the dominant shared PortMaster runtime (Godot/FRT) and Solarus both need `GLIBCXX_3.4.26`.
- A Zero28 **and** Zero40 `harbourmaster` device profile (§6) — today both fall back to `device=unknown`'s wrong `"opengl"` capability and (for Zero40) the wrong 640x480/4:3 resolution/aspect tags.

## 2. spruce payload closure (condensed — the full 214-file / 102-soname table is not
reproduced here; it was produced by running `readelf -d`/`-V`/`--dyn-syms` over every aarch64 ELF the
Zero28.cfg PATH/LD_LIBRARY_PATH chain can reach)

| binary/lib | representative DT_NEEDED | class | version note |
|---|---|---|---|
| `spruce/flip/bin/python3.10` | libpthread, libdl, libutil, librt, libm, libc, `libpython3.10.so.1.0` | SHIPPED | GLIBC_2.17 |
| `spruce/flip/lib/libpython3.10.so.1.0` | libdl, librt, libm, libpthread, libutil, libc | SHIPPED | GLIBC_2.17; `_ssl`/`_hashlib`/`_sqlite3`/`_socket`/`_ctypes`/`array`/`math`/`zlib` all statically built in (confirmed via `nm -D` `PyInit_*` symbols), not separate `.so`s |
| `spruce/flip/lib/lib-dynload/_crypt*.so` | `libcrypt.so.1` | mixed | needs BASE-OS libcrypt.so.1 |
| `spruce/flip/lib/lib-dynload/_tkinter*.so` | bundled `libtcl8.6.so`/`libtk8.6.so` | SHIPPED | GLIBC_2.17 |
| `spruce/flip/lib/libSDL2-2.0.so` (**SONAME `libSDL2-2.0.so.0`, filename has no `.0`**) | libX11, libwayland-client, … | **broken by name** — see §3 | GLIBC_2.29 |
| `overlay/usr/magicx/lib/libSDL2{,​_image,_mixer,_ttf}-2.0.so.0.*` | correctly named/symlinked | BORROWED (TrimUI Smart Pro / Moss-zero28) | GLIBC_2.29 max |
| `spruce/flip/lib/libavformat.so.58`, `libavutil.so.56`, `libmp3lame.so.0` | many | SHIPPED | **GLIBC_2.38** — exceeds 2.29 |
| `spruce/flip/lib/{libsystemd,libxkbcommon,libwayland-egl++,liblzma,libvpx,libzstd,libdecor-0}` | — | SHIPPED | **GLIBC_2.30–2.34** — exceeds 2.29 |
| `spruce/bin64/{busybox,curl,ffmpeg,rsync,ssh-keygen,jq,wget,…}` (47 tools) | mostly libc.so.6 only | SHIPPED | GLIBC_2.17–2.21 |
| `spruce/bin64/{fbfixcolor,gpiowait,setsharedmem,setsharedmem-flip}` | libc.so.6 | SHIPPED | **GLIBC_2.34** — build-toolchain mismatch, confirmed live (`readelf --dyn-syms`) |
| `RetroArch/ra64.universal` | libSDL2-2.0.so.0, libEGL, libGLESv2, libX11, libstdc++, libc | SHIPPED (bin); SDL2/EGL/GLESv2/libstdc++ → BASE-OS | **GLIBCXX_3.4.26** — exceeds 3.4.24 |
| cores64 sample (genesis_plus_gx, snes9x, fbneo, fceumm, gpsp, mgba, mupen64plus_next, fake08, pcsx_rearmed, …; 91 cores total) | libc/libm/libstdc++/libz | SHIPPED | ≤GLIBCXX_3.4.21 except `swanstation_libretro.so` (3.4.26) |
| `Emu/PSP/PPSSPPSDL_TrimUI` | libSDL2-2.0.so.0, libEGL, libGLESv2, libstdc++, libc | SHIPPED; SDL2/EGL/GLESv2/libstdc++ → BASE-OS | GLIBCXX_3.4.24/CXXABI_1.3.11 — exactly at ceiling |
| `Emu/PS/pcsx_64` | bundled libSDL-1.2.so.0, BASE-OS libasound.so.2, libpng16, libc | SHIPPED (SDL1.2 self-contained) | GLIBC_2.17 |
| `Emu/NDS/drastic64`, `Emu/NDS/dsperate` | libSDL2-2.0.so.0, libstdc++, libc | SHIPPED; SDL2/libstdc++ → BASE-OS | low GLIBCXX, fine |
| `Emu/N64/mupen64plus/*` (13 files) | libSDL2-2.0.so.0, libstdc++, libc | SHIPPED; SDL2/libstdc++ → BASE-OS | GLideN64/glide64mk2 need **GLIBCXX_3.4.26** |
| `Emu/SATURN/yabasanshiro`, `Emu/DC/flycast` | libstdc++, libc + bundled libs (flycast bundles OpenSSL 1.1) | SHIPPED; libstdc++ → BASE-OS | **GLIBCXX_3.4.26** |
| `App/Moonlight/…/moonlight`,`love` (+20 bundled libs incl. OpenSSL 3.x) | SDL2 via liblove, libavcodec, libcurl, libssl.so.3 | SHIPPED (self-contained); SDL2 → BASE-OS | max GLIBC_2.30, GLIBCXX_3.4.21 |
| `spruce/smartpro/inputd/trimui_inputd` (patched, drops left-stick range check) | libm, libpthread, libgcc_s, libc | SHIPPED, **not wired up for Zero28** — `TRIMUI_INPUTD_PATCHED` only exported by `SmartPro.cfg:84`, not `Zero28.cfg` | GLIBC_2.17 |
| `Emu/SCUMMVM/scummvm_64.7z`, `App/PortMaster/portmaster.7z` | n/a — still packaged | n/a | not inspectable until extracted at runtime |

BASE-OS-only sonames confirmed absent from every aarch64/Zero28-relevant
directory in the tree (present, if at all, only under other devices' 32-bit
dirs): `libc.so.6`, `libm.so.6`, `libpthread.so.0`, `libdl.so.2`, `librt.so.1`,
`libutil.so.1`, `libcrypt.so.1`, `libresolv.so.2`, `ld-linux-aarch64.so.1`,
`libEGL.so.1`, `libGLESv2.so.2`, `libdrm.so.2`, `libudev.so.1`,
`libasound.so.2`, `libfreetype.so.6`, `libfontconfig.so.1`, `libffi.so.8`,
`libtinfo.so.6`/`libncursesw.so.6`, `libgcc_s.so.1`, and — per §2's SONAME
finding — effectively `libSDL2-2.0.so.0`/`libstdc++.so.6` themselves.

## 3. glibc / GLIBCXX findings

Ceiling for glibc 2.29 / GCC 7.4.1(or 7.5.0) Linaro-lineage libstdc++:
`GLIBCXX_3.4.24`, `CXXABI_1.3.11` (confirmed against `phase2.config:398-408`,
which sets `CONFIG_GLIBC_USE_VERSION_2_29=y` and `CONFIG_GCC_USE_VERSION_7_4_LINARO=y`).

- **Nothing in the closure exceeds `CXXABI_1.3.11`.**
- **Six SHIPPED aarch64 binaries need `GLIBCXX_3.4.26`** (GCC ≥9 libstdc++,
  none bundling their own): `RetroArch/ra64.universal`,
  `RetroArch/.retroarch/cores64/{flycast,swanstation}_libretro.so`,
  `Emu/DC/flycast`, `Emu/N64/mupen64plus/{mupen64plus-video-GLideN64,mupen64plus-video-glide64mk2}.so`,
  `Emu/SATURN/yabasanshiro` — **will fail to dynamically link on a base image
  whose libstdc++ is really capped at GCC 7.4.1/7.5.0**, a real blocker
  independent of PortMaster. `PPSSPPSDL_TrimUI` sits exactly at the ceiling
  (`GLIBCXX_3.4.24`), not over it.
- **Four SHIPPED aarch64 tools need `GLIBC_2.34`**: `fbfixcolor`, `gpiowait`,
  `setsharedmem`, `setsharedmem-flip` (all in `spruce/bin64/`, confirmed live
  via `readelf --dyn-syms`). These need `__libc_start_main@GLIBC_2.34` — their
  crt object was linked against a glibc ≥2.34 toolchain and **will refuse to
  load** ("version `GLIBC_2.34' not found") on this base image's glibc 2.29.
- The `spruce/flip/lib/*` bundle (python3.10's runtime libs — ffmpeg/audio/
  wayland stack) mixes GLIBC_2.30 through **2.38** (`libavformat.so.58`/
  `libavutil.so.56`/`libmp3lame.so.0` at 2.38; `libsystemd`/`libxkbcommon`/
  `liblzma`/`libvpx`/`libzstd`/`libdecor-0` at 2.30–2.34) — built against a
  materially newer glibc than the 2.29 it ships for. Not on the Zero28
  `LD_LIBRARY_PATH` hot path unless dlopened, but any code path that touches
  them (Tkinter, ffmpeg features) is at risk.
- GE8300 GPU userspace blobs (`libEGL.so`,`libGLESv2.so`,`libIMGegl.so`,
  `libsrv_um.so`,`libusc.so`,`libpvrNULL_WSEGL.so`) need only `GLIBC_2.17`;
  `libglslcompiler.so` additionally needs `libstdc++.so.6` at base
  `GLIBCXX_3.4` (unversioned) — **no GPU-driver blocker** (verified directly
  with `readelf --dyn-syms` against `sdk/lichee/package/libs/libgpu/ge8300/fbdev/glibc/lib64/*.so`).
- spruce's own `python3.10`/`libpython3.10.so*` need only `GLIBC_2.17`.
- **PortMaster-side**: sampled port `2048_libretro.so.aarch64` needs
  `GLIBC_2.33` (exceeds 2.29). Sampled shared runtimes
  `runtimes/frt_3.3.4.aarch64.squashfs` (Godot/FRT — the dominant shared
  runtime across the whole catalog) and `runtimes/solarus-1.6.5.aarch64.squashfs`
  both need **`GLIBCXX_3.4.26`**, exceeding 3.4.24. `port.json`'s `min_glibc`
  gate is enforced live (`harbour.py:1160-1164`, compares against
  `hardware.py:272-314`'s live `libc.so.6 --version` probe) but there is no
  equivalent `min_glibcxx` field anywhere — a libstdc++ mismatch is never
  gated, only discovered at runtime as a dynamic-linker failure.

**Net conclusion**: glibc 2.29 is adequate for almost everything spruce ships
(only 4 stray `bin64` tools built off-profile need fixing). The **libstdc++
ceiling is the real risk**: GCC 7.4.1/7.5.0's `GLIBCXX_3.4.24` is two minor
versions behind what GLideN64/flycast/yabasanshiro/swanstation and
PortMaster's dominant Godot/FRT runtime need. Fix via (a) a newer standalone
`libstdc++.so.6` on the base image or PortMaster runtime tree, ahead of the
system one, independent of the GCC 7.x BSP toolchain, or (b) accept those
cores/ports/engines as unsupported on this base.

## 4. GPU userspace (PowerVR GE8300)

- Kernel module: `sdk/lichee/package/kernel/gpu-km/Makefile:36-50`
  selects `PKG_NAME:=ge8300-km` for `TARGET_PLATFORM` in `mr813 r818 a133`,
  building `pvrsrvkm.ko` + `dc_sunxi.ko` from
  `lichee/linux-4.9/modules/gpu/img-rgx/linux/rogue_km/binary_sunxi_linux_nullws_release/target_aarch64/`
  (prebuilt binary tree confirmed present on disk).
- Userspace package: `package/libs/libgpu/Makefile:27-28` auto-selects
  `GPU_TYPE=ge8300` for `a133`; `DEPENDS:=+kmod-ge8300-km +libstdcpp +zlib`
  (L45-46); window system is **fbdev**, not wayland/DRM, because
  `CONFIG_WESTON_DRM` is off (Makefile L52-56; `libdrm` is also explicitly
  disabled, see §5).
- Blob directory `package/libs/libgpu/ge8300/fbdev/glibc/lib64/`: `libEGL.so(.1)`,
  `libGLES_CM.so(.1)` (ES1.1), `libGLESv2.so(.2)`, `libIMGegl.so`,
  `libglslcompiler.so`, `libsrv_um.so`, `libusc.so`, `libtqvalidate.so`,
  `libufwriter.so`, `libpvrNULL_WSEGL.so`, `libPVROCL.so(.1)`+`libOpenCL.so`
  symlink, `libPVRScopeServices.so`, `libVK_IMG.so(.1)`, `libvulkan.so(.1)`
  (Vulkan 1.x present); `bin/{pvrsrvctl,ocl_unit_test}`;
  `firmware/{rgx.fw.22.102.54.38,rgx.sh.22.102.54.38}` -> `/lib/firmware`. DDK
  per `aw_version`: "img-rgx: add 1.19 ddk". Already enabled by default:
  `CONFIG_PACKAGE_libgpu=y`, `CONFIG_PACKAGE_kmod-ge8300-km=y` (vendor
  defconfig L3502/3782; `phase2.config:3089,3369` unchanged) — OpenCL off.
- **SDL2 build spruce/PyUI/RetroArch need — cross-validated against a real
  independent Zero28/Zero40 port**: `knulli-linux/board/allwinner/a133/magicx-zero-28/`
  and `.../magicx-zero-40/` are actual community board ports for **this
  device**. Their `patches/sdl2/001-add-pvr-ge8300-mali-driver.patch` adds a
  `SDL_MALI`/`CheckMali` CMake option compiling SDL2's existing
  `src/video/mali-fbdev/*.c` backend against `<EGL/egl.h>` (`-DLINUX
  -DEGL_API_FB`), i.e. **SDL2 built with the mali-fbdev video backend,
  pointed at the GE8300's own EGL/GLESv2**, `SDL_VIDEODRIVER=mali` — the same
  pattern `App/PyUI/launch.sh:133-162` already documents for the Anbernic XX
  (H700/Mali) line ("the mali build is the only backend on this box that can
  reach the panel"). Firmware cross-check: Knulli ships byte-identical
  `rgx.fw.22.102.54.38`/`rgx.sh.22.102.54.38` — the same vendor DDK build.
- Kernel-side fbdev is present and sufficient: `CONFIG_FB=y` (config-4.9 L2333),
  `CONFIG_DISP2_SUNXI=y` (L2375); `CONFIG_DRM=y`/`DRM_KMS_HELPER` exist but are
  unused by this fbdev-only GPU path.
- `CONFIG_PACKAGE_libdrm` is explicitly off in the vendor defconfig and both
  phase configs (phase2 L2627) — consistent with fbdev-only, not a gap.
- Hardware framebuffer rotation is **not** built: `CONFIG_SUNXI_DISP2_FB_DISABLE_ROTATE=y`
  / `ROTATION_SUPPORT` unset (config-4.9 L2376-2377), so Zero28's
  `DISPLAY_ROTATION="90"` (`Zero28.cfg:26`) must be handled in software today.
  MagicX's a133 Tina BSP update drop (2025-10-11) carries an optional
  `0001-feat-support-disp2-fb-hw-rotate.patch` (G2D-accelerated rotation via
  `CONFIG_SUNXI_DISP2_FB_HW_ROTATION_SUPPORT`) — a future optimization, not a
  correctness requirement (§8).

## 5. WiFi / BT / audio / input stack

- **WiFi (XR829)**: kernel Kconfig symbol present but off —
  `config-4.9:1262-1263` (`# CONFIG_XR819_WLAN / CONFIG_XR829_WLAN is not
  set`); full driver source at `lichee/linux-4.9/drivers/net/wireless/xr829/`.
  Package layer `CONFIG_PACKAGE_kmod-net-xr829` is off everywhere checked —
  vendor defconfig L3542, `phase1.config:3143`, `phase2.config:3129` — same
  for `kmod-net-xr829-40M` and `CONFIG_PACKAGE_xr829-firmware` (phase2 L2590;
  vendor L2917), even though the firmware blobs themselves exist at
  `package/firmware/linux-firmware/xr829/*.bin`. `CONFIG_XR829_USE_40M_SDD`
  is off everywhere (crystal-dependent — open question, §8).
  Independent confirmation from Knulli's `etc/init.d/S03modules:1-15`: even a
  working from-scratch port picks between a **generic** `xradio_{core,mac,wlan}.ko`
  build and a `trimui-smart-pro`-specific `_tsp.ko` variant by board name —
  MagicX Zero28/40 need the generic build, not TrimUI's.
- **Bluetooth**: vendor `a133-aw3` defconfig ships it on (`bluez-libs=y`
  L3986, `bluez-alsa=y` L4395, `bluez-daemon=y` L5328, `bluez-utils(-extra)=y`
  L5331-5332, `dbus=y` L5346) but **Moss's phase configs turn all bluez
  packages off** while keeping dbus on (`phase2.config`: `bluez-libs` off
  L3573, `bluez-alsa` off L3982, `bluez-daemon` off L4647,
  `bluez-utils(-extra)` off L4650-4651). `CONFIG_XR829_BT` is off too (phase2
  L4648) — the kernel HCI transport backed by
  `lichee/linux-4.9/drivers/bluetooth/xradio_btlpm.c`/`xradio_btfdi.c`.
  **Live bug risk**: `device_functions/trimui_a133p.sh:196` runs
  `/etc/bluetooth/bluetoothd start` unconditionally in `device_init_a133p` on
  every A133P device including Zero28 — without `bluez-daemon` that binary
  won't exist, so Bluetooth silently never comes up (backgrounded, so it
  won't crash boot). Re-enable the bluez-* set and `CONFIG_XR829_BT` for
  working Bluetooth; HCI attach already exists at
  `package/allwinner/bluetooth/xradio/hciattach_xr829.init` +
  `package/allwinner/btmanager/config/xradio_bt_init.sh`.
- wpa_supplicant/hostapd: combined package, `package/network/services/hostapd/Makefile`
  `PKG_VERSION:=2017-11-08` (~wpa_supplicant 2.6/2.7 era), internal TLS
  (`CONFIG_WPA_SUPPLICANT_INTERNAL=y`, phase2 L4346). `wpa-supplicant`/
  `wpa-cli`/`hostapd` are **on** in vendor defconfig and both phase configs
  unchanged — contra an earlier working note that Moss disabled wpa-supplicant; the
  files on disk say otherwise (flagged in §8). `CONFIG_PACKAGE_wireless-tools`
  is off everywhere (vendor default, not a Moss deletion) — low priority,
  spruce's own tooling uses `ip`/`wpa_cli`/`jq`.
- Audio: `alsa-lib` 1.1.4.1 (`package/libs/alsa-lib/Makefile`), `CONFIG_PACKAGE_alsa-lib=y`
  both phases; `CONFIG_SND_SOC=y` (config-4.9 L2496); `CONFIG_SND_USB_AUDIO`
  off (L2486, optional — USB audio dongles).
- Input libs `libevdev` 1.4.6 and `libinput` 1.5.0 are **both on** in phase1/
  phase2 (`CONFIG_PACKAGE_libevdev=y`, `libinput=y`), as are `libexpat`/
  `libffi` — again contra that earlier note claiming Moss disabled them; ground
  truth in the two config files says otherwise (§8).
- Other confirmed library versions: `zlib` 1.2.8, `libpng` **1.2.56** (old 1.2
  branch, not 1.6), `libjpeg` (IJG) 9a, `freetype` 2.6.1, `bluez` 5.54
  (currently disabled), `dbus` 1.10.4.
- **SDL2 does not exist as a Tina package at all** — only SDL **1.2**
  (`package/multimedia/sdl/Makefile`), and it's off everywhere
  (`# CONFIG_PACKAGE_sdl is not set` in vendor defconfig, phase1 L4010,
  phase2 L3996). This confirms spruce/PyUI/RetroArch must keep bringing SDL2
  themselves (§2/§3's SONAME issue is exactly this dependency going wrong).

## 6. PortMaster

**Detection is two separate, disagreeing code paths** (both read-only
inspected in `PortMaster-GUI`):
- **Bash** (`PortMaster/device_info.txt`): `L52-54` checks
  `/mnt/SDCARD/spruce` *first* (moved there in commit `ef16b68`, "check for
  spruce first because of our dArkOS shenanigans") and sets `CFW_NAME=spruce`.
  `L234` computes `RESOLUTION` via a **live SDL probe**
  (`sdl_resolution.$DEVICE_ARCH`), so Zero28 (640x480) / Zero40 (480x800) get
  correct resolution/aspect automatically, no profile needed at this layer.
  The `L276-495` `FIXES` case statement (hand overrides for `ANALOG_STICKS`/
  `DEVICE_CPU`/`DEVICE_NAME` per known board) has **no Zero28/Zero40 branch**;
  an A133P board's `DEVICE_NAME` falls through to a generic devicetree-model
  parse and, since `CFW_NAME=spruce` (not `TrimUI`), the TrimUI-forcing
  override doesn't fire either — Zero28 will very likely report the same raw
  `DEVICE_NAME=sun50iw10` string Brick/TSP/BrickPro already do under spruce,
  indistinguishable from them. `ANALOG_STICKS` defaults to 2 with no
  override (correct for Zero28; would need a Zero40 override if it's not 2).
- **Python** (`harbourmaster/hardware.py`): a static table, no live probe, and
  it has **no `/mnt/SDCARD/spruce` check at all** (`git log` shows no
  spruce-related commits touch this file upstream) — `PlatformSpruce` (added
  by PR #337, `platform.py:1277-1309`) is unreachable in stock upstream; the
  TrimUI Smart Pro only reaches it because spruce's own Development build ships a
  patched `hardware.py`/`platform.py` on-card, not present in this checkout.
  `HW_INFO` (`hardware.py:103-193`) has no `zero28`/`zero40` key; an
  unprofiled device falls to `"default"` (`L192-193`):
  `{"resolution":(640,480),"analogsticks":2,"cpu":"unknown","capabilities":["opengl","power"]}`
  — the exact bug already measured on the TrimUI Smart Pro (`device=unknown`,
  wrong `opengl` capability). Zero28's real resolution
  happens to match the default, so it would get right numbers with a wrong
  `opengl` tag; **Zero40 would get the wrong resolution entirely** (640x480/
  4:3 instead of 480x800/portrait) — a worse failure mode.
- Tag machinery (`hardware.py:647-732`, `expand_info`): `display_ratio` via
  gcd (4:3 for Zero28, 3:5 for Zero40, no built-in curation for 3:5),
  `analog_0..N`, `lowres`/`hires`/`wide`, ram-tier tags. `harbour.py:1142-1189`
  + `util.py:700-730` AND-match a port's literal `"reqs"` tags (e.g.
  `ports/air/port.json: "reqs":["4:3"]`, `ports/aquaria/port.json:
  "reqs":["!lowres","analog_1"]`) against these — this is the literal
  aspect-ratio gate the task asked about.
- **Proposed profiles** (schema per `hardware.py:30-193`):
  `DEVICES["MagicX Mini Zero 28"] = {"device":"zero28","manufacturer":"MagicX","cfw":["spruce"]}`,
  `HW_INFO["zero28"] = {"resolution":(640,480),"analogsticks":2,"cpu":"a133p","capabilities":[],"ram":1024}`
  (no `"opengl"` — GE8300 is GLES-only); `DEVICES["MagicX Zero 40"]` similarly
  with `HW_INFO["zero40"] = {"resolution":(480,800),"analogsticks":0,"cpu":"a133p","capabilities":[],"ram":1024}`
  (sticks/RAM TBD — hardware verification needed). Both need the missing
  `/mnt/SDCARD/spruce` check added to `new_device_info()` to even be reached;
  spruce's own bash `device_info.txt` FIXES table should also gain Zero28/40
  branches so they don't collide with Brick/TSP's shared `sun50iw10` string.
- **Runtime/mount needs** (measured on other spruce devices, not re-derived): squashfs loop mounts work on every measured device except
  armv7l A30; TSPS wants 16+ loop devices but only 8 exist anywhere measured;
  `losetup` is absent on BusyBox-heavy units. `/dev/shm` is
  shadowed/nonexistent on TSPS and `pm_message` (375 ports call it) hangs
  there — boot-order dependent, needs a fresh check on Zero28/40. BusyBox
  1.27.2 (closest A133P analogs) rejects `find -quit` (8 ports), `mv/cp -T`
  (3), lacks `sha1sum`/`bc`/`stat`; `tar` has no `-z` (breaks 9 ports); the
  PATH `unzip` needs `GLIBC_2.34` and fails below glibc 2.33 (44 ports) —
  none of this is architecture-specific, all reproduce on Zero28/40 unless
  fixed. `gptokeyb` is already shipped (`spruce/bin64/gptokeyb`, §1); it only
  needs `/dev/uinput` (§7). `xdelta3` isn't a system dependency — sampled
  ports (e.g. `HFTSR.zip`) bundle their own static aarch64 copy.
- **Library patterns** (`PortMaster-New`/`common/pm` sampling): ports
  overwhelmingly bundle their own SDL1/SDL2-family and codec/format libs
  (libvorbis, libmodplug, libFLAC, libwebp, liblzma, libjpeg, libtiff,
  libmikmod, libfluidsynth, libphysfs, libssl/libcrypto, libzip); they expect
  the base OS for `libc`/`libm`/`libpthread`/`libdl`/`libgcc_s`, GLES/EGL,
  ALSA, and the CFW `libSDL2-2.0.so.0` baseline. Desktop-GL-only ports often
  bundle a **gl4es** shim (`antecrypt`, `counter-strike`, `pigments`,
  `wratchsden`) to run on the GLES-only GE8300; a minority (`xroar`) bundle a
  raw `libGL.so.1` instead, unlikely to work without live verification.
  `PortMaster-New` is confirmed `blob:none` sparse (only `*.sh/*.json/*.md/…`
  materialize; `.so` files exist per `git ls-tree` but were never fetched) —
  filename-level survey only for that repo, byte-level for `common/pm` zips.
- **Port categories that will not work regardless of base-image tuning**:
  Godot/FRT- and Solarus-engine ports (GLIBCXX ceiling, §3); ports gated on
  `"reqs":["16:9"]`/`"wide"` (Zero28) or lacking a portrait/4:3 profile
  (Zero40) until a device profile exists; armhf-only ports if the base image
  ships no armhf loader (204 counted across spruce devices); x86/x86_64-only
  ports (aarch64 excludes them
  categorically); libretro cores needing glibc >2.29
  (`2048_libretro.so.aarch64` needs 2.33); desktop-OpenGL-only ports without
  a gl4es shim; heavy mono/Godot-4.x/dotnet bundles pending real RAM/CPU
  figures (not benchmarked here).

## 7. Concrete deltas vs Moss `phase2.config` + kernel `config-4.9`

Kernel (`sdk/lichee/device/config/chips/a133/configs/aw3/linux/config-4.9`,
3941 lines, `VERSION=4 PATCHLEVEL=9 SUBLEVEL=191` confirmed in
`lichee/linux-4.9/Makefile:1-3`) — change from `# ... is not set` to the value
shown; every one of these except exFAT/zstd was independently proven working
on real Zero28/40 hardware by Knulli's `linux-sunxi64-legacy.config` (a
different, newer kernel base — corroboration of the *requirement*, not a
config to copy):
```
L956  CONFIG_BLK_DEV_LOOP=y          # PortMaster squashfs runtime mounts
L1424 CONFIG_INPUT_UINPUT=y          # gptokeyb virtual pad (already shipped)
L1300 CONFIG_INPUT_JOYDEV=y          # legacy /dev/input/jsN readers
L1291 CONFIG_INPUT_FF_MEMLESS=y      # external controller rumble/FF
L2486 CONFIG_SND_USB_AUDIO=m         # USB audio dongles (nice-to-have)
L1263 CONFIG_XR829_WLAN=m            # onboard WiFi (or build out-of-tree)
```
No in-kernel exFAT anywhere checked (Tina 4.9.191 or Knulli's newer sunxi64
tree for this same board) — plan on FUSE (`CONFIG_FUSE_FS` already `=m`,
L3390) + `exfat-fuse`/`exfatprogs`, not a kernel option. `CONFIG_SQUASHFS_ZSTD`/
`LZ4`/`LZO` (L3459-3462) are all off, only XZ — nice-to-have pending
confirmation whether any PortMaster runtime squashfs uses zstd.
`CONFIG_MODVERSIONS` is off (L267): any prebuilt `.ko` (spruce's own
`zram.ko`/`lzo.ko`/`zsmalloc.ko`, or a prebuilt xr829/GE8300 module) must be
built against a kernel with an identical version+config to `insmod` cleanly —
a build-process constraint, not a config line, listed here because it gates
whether the deltas above can even be applied to a prebuilt kernel image.

`phase2.config` (package selection; `phase1.config`'s `CONFIG_PACKAGE_*` set
is identical except unrelated `cortana-demo`/`cortana-sdk` — the two phase
files are not where the package differences are, the vendor `a133-aw3
defconfig` vs phase files is):
```
CONFIG_PACKAGE_kmod-net-xr829=y        # was: not set (L3129) — onboard WiFi module
CONFIG_PACKAGE_kmod-net-xr829-40M=y    # was: not set (L3130) — pick 40M/26M SDD variant per hw (§8)
CONFIG_PACKAGE_xr829-firmware=y        # was: not set (L2590) — WiFi firmware blobs
CONFIG_XR829_USE_40M_SDD=y             # was: not set (L2587) — IF hardware uses 40M crystal (§8)
CONFIG_PACKAGE_bluez-libs=y            # was: not set (L3573) — vendor default is already y
CONFIG_PACKAGE_bluez-alsa=y            # was: not set (L3982)
CONFIG_PACKAGE_bluez-daemon=y          # was: not set (L4647) — bluetoothd binary trimui_a133p.sh:196 calls
CONFIG_PACKAGE_bluez-utils=y           # was: not set (L4650)
CONFIG_PACKAGE_bluez-utils-extra=y     # was: not set (L4651)
CONFIG_XR829_BT=y                      # was: not set (L4648) — XR829 BT HCI transport
```
Everything else this report checked (`libgpu`, `kmod-ge8300-km`, `alsa-lib`,
`libevdev`, `libinput`, `libexpat`, `libffi`, `dbus`, `wpa-supplicant`,
`hostapd`, `zlib`, `libpng`, `libjpeg`, `freetype`) is **already `=y`** in
both phase configs — no delta needed, listed in §4/§5 for completeness only.

## 8. Open questions

1. **`/usr/trimui/bin` on MagicX hardware.** No evidence either way that
   MagicX's Tina firmware ships `trimui_inputd`/`trimui_scened`/
   `trimui_btmanager`/`hardwareservice`/`musicserver` there, yet
   `device_functions/trimui_a133p.sh:199` (shared by Zero28 via `Zero28.sh:8`)
   calls `run_trimui_blobs` expecting exactly that; absent, the whole
   input-daemon chain silently no-ops. Needs a firmware dump or vendor
   confirmation — none found in the vendor SDK drops on hand (no genuine
   TrimUI Smart Pro/Brick dump there; `sdk_tg5050_linux_v1.0.0.tgz` is a
   different A523/Mali generation; `G243_SW_V03_20251218.zip` is an unrelated
   MediaTek phone image; `Linux_SDK.zip`/`longan.tgz` are Android BSP trees).
2. **`spruce/flip/lib/libSDL2-2.0.so` filename/SONAME mismatch** (§2/§3) looks
   like a packaging bug independent of this base-image spec — worth fixing
   in spruceOS regardless of what the base image ships, since it silently
   defeats the intended "spruce brings its own SDL2" fallback for every
   native (non-PyUI) consumer.
3. **No `Zero40.cfg` / `device_functions/Zero40.sh` exist in spruceOS at
   all** (checked `spruce/scripts/platform/`) — only `Zero28.cfg`. The base
   image can plausibly be built for Zero40 today (Knulli already has a
   `magicx-zero-40` board, and the Zero 40 overlay mirrors Zero 28's
   borrowed-SDL2 layout), but spruce itself has no platform identity for it
   yet, and Knulli's own Zero40 kernel config enables no touchscreen driver
   either (`grep` for `CONFIG_TOUCHSCREEN_*`/`CONFIG_INPUT_TOUCHSCREEN` came
   up empty) — touch input for Zero40 is unresolved even in the community
   reference.
4. **XR829 crystal variant (26M vs 40M SDD)** — `CONFIG_XR829_USE_40M_SDD`
   and the matching `kmod-net-xr829-40M` firmware pick need real hardware
   verification on Zero28 and Zero40 (they may differ from each other).
5. **Earlier-note discrepancy**: an earlier working note said "Moss disabled
   wpa-supplicant, dbus, libinput, wireless drivers, libexpat, libffi... in
   its phase III list." Ground truth in the only two phase config files on
   disk (`phase1.config`, `phase2.config`) shows those five are all **on**;
   only bluez-* and (already-vendor-default-off) wireless-tools/kmod-net-xr829/
   xr829-firmware are off relative to vendor defaults. Either a third "phase
   III" config existed and was never committed, or the note is stale.
6. **`usr/magicx/device` marker.** `docs/sdk-mods.md` documents an
   intended `usr/magicx/device` marker file (`zero28`/`zero40`) as "the
   spruce discriminator," but no such file exists yet under either
   the Zero 28 or Zero 40 overlay — presumably still
   WIP; spruce-side code that would read it was not found.
7. **Toolchain substitution**: the real `gcc-linaro-7.4-2019.02` tarball is
   currently unfetchable (per `docs/sdk-mods.md`), so the
   buildable config today is `phase2-gcc750.config` (vanilla GCC 7.5.0), not
   `phase2.config`'s true Linaro 7.4.1. Both are package-identical and both
   land on the same `GLIBCXX_3.4.24`/`CXXABI_1.3.11` ceiling used throughout
   this report, so the findings hold either way, but the two files should
   not be treated as interchangeable if the Linaro tarball resurfaces later.
8. **PortMaster runtime squashfs compressor**: only 2 runtime squashfs
   images were sampled (`frt_3.3.4`, `solarus-1.6.5`, both XZ-compatible in
   practice); whether any catalog runtime actually needs zstd (which this
   kernel config lacks, §7) was not exhaustively checked.
9. **RAM/CPU headroom** for heavy PortMaster runtimes (mono, Godot 4.x,
   dotnet) on Zero28/40 was not benchmarked — `HW_INFO`'s `ram` figure (used
   for `Ngb` capability tags) needs a real number before the proposed device
   profiles in §6 are finalized.
