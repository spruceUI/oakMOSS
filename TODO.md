# oakMOSS wishlist: kernel and rootfs overlay

What the base image still has to grow to carry a launcher on its own, in the
order the evidence arrived (bench work on a Zero 28 and a Zero 40 with spruceOS
on the user card, September 2026). `[x]` is in the image today, `[ ]` is open,
`[?]` needs identification before it can be built. Pointers are to
`docs/hardware-notes.md` (HN), `docs/DEPENDENCIES.md` (DEP) and `docs/sdk-mods.md`
(MODS); the spruce-side workarounds named here are what the launcher does today
because the base does not.

## Kernel: config

- [x] `BLK_DEV_LOOP` (PortMaster runtimes), `INPUT_UINPUT` (gptokeyb),
      `INPUT_JOYDEV` (jsN readers), `INPUT_FF_MEMLESS` (rumble on external pads),
      `SND_USB_AUDIO`, `SQUASHFS_LZ4/LZO`, `NLS_UTF8` + FAT default iocharset utf8,
      `VIDEO_SUNXI_VIN` off (MODS, DEP §7; `sdk-patches/tree/020`).
- [x] `ZRAM` + `ZSMALLOC` (+ `CRYPTO_LZ4`/`LZO`) (round 8): the launcher's compressed-swap
      option logs "zram device not found" on every boot; without the modules the
      launcher would have to ship its own `zram.ko`, which `MODVERSIONS=n` makes a
      version-exact build (DEP §7).
- [x] `CPU_FREQ_GOV_SCHEDUTIL` (already on): candidate for the launcher's "smart"
      CPU mode; only `performance`/`powersave`/`ondemand` today.
- [x] `IKCONFIG` + `IKCONFIG_PROC` (already on): `/proc/config.gz` instead of the
      `usr/magicx/tina_config.gz` copy the image step drops in.
- [x] `LOG_BUF_SHIFT` >= 18 (round 8): the Realtek driver's debug output wrapped the ring
      buffer 62 s after boot, so `dmesg` no longer covers boot by the time anyone
      looks (`logread` keeps more; the base-boot capture is the only full copy).
- [x] **`softap` package off** (round 8): its Makefile injects `CONFIG_NF_CONNTRACK=y`,
      `NF_NAT=y` and the CONNMARK/STATE/REDIRECT/NETMAP targets into the kernel
      config, adding a pointer to `struct sk_buff`; modules built that way read
      `skb->data` 8 bytes off under MagicX's own kernel (the Zero 40 hybrid's
      xradio oops, 2026-09-16). `dnsmasq` and `hostapd` went with it (the
      supplicant and `wpa_cli` are their own packages). Any future kernel config
      must be diffed against the REAL `.config` (`lichee/linux-4.9/.config`),
      not the board file: package KCONFIG lines are merged in at build time.
- [ ] `PSTORE` + `PSTORE_RAM` (ramoops): the main-zero40 partition scheme already
      has a `pstore` partition; a lockup post-mortem needs the kernel side.
- [x] USB host input: `HID_GENERIC` (on), `JOYSTICK_XPAD`, `HID_SONY`, `HID_MICROSOFT`, `HID_LOGITECH`, `BT_HIDP` (round 8; no `HID_NINTENDO` in 4.9)
      (and `USB_STORAGE` for USB drives) — verify which are on; only `hid` is
      known loaded.
- [ ] exFAT for user cards over 32 GB: kernel 4.9 has none (DEP §7). Options:
      Samsung's out-of-tree `exfat-linux` (builds on 4.9), or userland
      `fuse-exfat` + `exfatprogs` on the already-loaded `fuse` module. Either way
      an `/etc/hotplug.d`/fstab rule must mount SD2 with it.
- [x] `SYSVIPC` (was on) / `POSIX_MQUEUE` / `SECCOMP` (round 8): verify on, some PortMaster engines
      and Godot builds want them (DEP §6).
- [ ] USB WiFi dongle modules for our kernel (`8188eu`, `8812au` — the launcher's
      A133P dongle contract keys on `WIFI_USB_MODULES_DIR`), built in-tree so they
      match `MODVERSIONS=n`.
- [ ] Realtek `8189es` driver: build with `CONFIG_RTW_DEBUG` off or a lower
      `rtw_drv_log_level` (see LOG_BUF_SHIFT), and decide the power-save defaults
      (`rtw_power_mgnt`, `rtw_ips_mode`) — the IPS enter/leave cycle costs ~0.8 s
      on every scan and is the usual source of handheld SSH jitter.

## Kernel: drivers and device trees, per board

- [ ] **Zero 40 panel `RTP40WV101B` (480x800) and `axs15205` touch (twi)**: not in
      the SDK drop; the board only boots the hybrid image (main-zero40's boot0 /
      U-Boot / DTB / kernel + our rootfs, `scripts/make-hybrid-zero40.sh`). Needs
      the LCD panel init sequence (`lcd_panels/`) and the ctp driver ported into
      our lichee tree plus the `lcd0`/twi nodes in `board.dts` (HN Boards, Known gaps).
- [x] **Zero 40 hybrid: MagicX's modules, not ours** (2026-09-16): its kernel has
      `CONFIG_BUG=n`/`KALLSYMS=n` and a modular netfilter core; our round-8 modules
      never came up under it. `scripts/adapt-zero40-rootfs.sh` swaps in the set
      out of the main-zero40 image (HN "Zero 40 hybrid: whose modules"). Our own
      modules matter again only once our kernel drives the board.
- [ ] **Route 1: our kernel on the stock chain** (2026-09-16 evening; `make-own-kernel-stock.sh`,
      first images `builds/20260916-1744-xu20-own`, `20260916-1745-zero40-own`): UNTESTED. Then:
      touch drivers (Hynitron hyn_ts for the XU20, axs15205 for the Zero 40) + their nodes in
      `boards/*/board.dts`; Zero 40 WiFi with our xradio under our kernel (`chip_en` boolean in
      the stock node); retire the Android-kernel lane once both boards show the UI.
- [ ] **Zero 40 on its own stock chain** (2026-09-16, `scripts/make-hybrid-stock.sh zero40`,
      one-slot image 1240 BOOTS; two-slot 1255 carries the repaired boot package
      checksum, untested). Once a two-slot image boots, spruce's `Zero40.cfg` needs `WIFI_ONBOARD_MODULE=xr829` and no
      `MAGICX_RADIO_MODULES_DIR` (the stock kernel has MODVERSIONS; our 4.9.191
      xradio build cannot load there and the vendor's `xr829` autoloads instead),
      and the main-zero40 hybrid lane can be retired.
- [ ] **Zero 40 WiFi power**: our DTB drives `chip_en` on r_pio PL7, the known-good
      tree has `chip_en = true`; under the hybrid DTB the Realtek card is unpowered
      (no SDIO device, no wlan0). Resolve in the DTB, not by driving GPIO 359/357
      from userland (the 2042 diag experiment).
- [ ] **AXP2202 battery parameters** in both DTBs (`pmu_battery_cap`, OCV table):
      neither tree carries any, both boards run the driver's default 2600 mAh model
      and the Zero 40's larger cell reads skewed until a learned cycle (HN). The
      launcher papers over 0-1 % readings with a voltage estimate.
- [ ] **Zero 40 stick axes**: DTB `joystick1_invert=1` plus the swapped axis
      order mean the launcher flips/swaps in its cfg (`MAGICX_STICK_SWAP_XY`,
      `INVERT_X`); fix at the source so both boards report plain X/Y.
- [ ] **`simplepad` quirks** (UART MCU pad, `magicx-input`): the A button emits
      `BTN_SOUTH` 304 and `KEY_SELECT` 353 in the same instant (measured 2026-09-16,
      the launcher now ignores 353); volume keys arrive on the pad node, not the
      jack device; virtual-mouse buttons 272/273 are exposed. Trim in the driver.
- [ ] **Codec DAC volume owned by the driver**: `sound/soc/sunxi/sun50iw3-codec.c`
      `codec_aif_mute` writes `SUNXI_DAC_VOL_CTRL` = 0 on mute and the DT default
      (`gain_config.dac_digital_vol`, 160) on unmute, so a level set through the
      'DAC volume' control (MinUI, MagicX's own `vol` helper) is lost at every
      stream restart and every game starts at full volume. Restore the user's
      value (cache the kcontrol write) instead of the DT constant; also the
      'digital volume' TLV is declared backwards (0 is 0 dB on the hardware).
      The launcher works around it by keeping the level in 'digital volume'.
- [ ] **Newer-board-revision fixes** from main-zero40 v20260202-1 ("Allwinner
      supplied fixes for newer board revisions"): contents unknown, not in our
      inputs (HN Known gaps).
- [ ] **`sunxi_encrypt` object**: the Zero 40 needs MagicX's prebuilt object
      (`ENCRYPT_OBJ=zero40`, kernel relink per board). Understand what it checks so
      one kernel can serve both boards, or keep one kernel per board deliberately.
- [ ] **One image for both boards**: the `/usr/magicx/device` marker is written at
      build time; detect the board at boot (DTB model / panel) and write it, once
      the Zero 40 panel driver lives in our tree.
- [?] **Bluetooth chip**: the Zero 28's radio is a Realtek RTL8189ES-class part
      (WiFi only); the Zero 40's is an XR829 (SDIO 0x0a9e:0x2282, WiFi + UART BT),
      yet MagicX's stock Zero 40 rootfs activates an AIC `hciattach` on `/dev/ttyS1`
      (with xr829 and rtl8723ds variants beside it). Probe the UART before building
      anything; our rootfs ships `fw_xr829_bt.bin` and bluez.
- [ ] **xradio error-path use-after-free**: `xr829/wlan/main.c` `xradio_core_init`
      calls `xradio_unregister_bh` when `xradio_load_firmware` fails, and that does
      `kthread_stop` on a bh thread that has already exited; the build does not
      define `HAS_PUT_TASK_STRUCT`, so no reference is held and the kernel oopses
      in modprobe's context (Zero 40, 2026-09-16, "BUG task_struct: Poison
      overwritten"). Take the reference in `xradio_register_bh` (or check
      `bh_error` before stopping). A firmware failure must not take the kernel
      with it.
- [ ] **XR829 crystal 26 M vs 40 M**: the Zero 40 does have the XR829, so this
      is live: our `sdd_xr829.bin` is the 26 MHz table; if the firmware fails to
      boot on the Zero 40, build the 40 M variant (`XR829_USE_40M_SDD`). Keep
      `xradio_*` off the autoload list on both boards (its platform init rescans
      the SDIO bus and knocks the Zero 28's Realtek off it); the launcher loads
      the board's driver by name.

## Rootfs overlay: services and files

- [x] `etc/init.d/wpa_supplicant` no-op: wifimanager's S96 service started a second
      supplicant on wlan0 and disconnected every association the launcher's made
      (Zero 28, 2026-09-16). Better: drop the `wifimanager` package and keep only
      `wpa-supplicant`/`wpa_cli`, once it is confirmed nothing else comes from it
      (`/etc/wifi/*`, `udhcpc_wlan0`).
- [x] `etc/modules.d/net-xr829` empty (see XR829 above).
- [ ] Services the launcher never uses, off by default: `dnsmasq` (S60), `cron`
      (S50), `sysntpd` (S98, the launcher syncs time itself), `adbd` (S80; keep as
      a dev-mode toggle), `netifd`/`network` (S20; nothing to manage without
      `/etc/config/wireless`), `smartlinkd`, `hostapd`. Each costs boot time and
      RAM; rc.local runs 8 s after power-on today.
- [ ] `/dev/shm` tmpfs and `/dev/fd` -> `/proc/self/fd` at init: the launcher
      mounts/links both every boot ("stock firmware had none").
- [x] BusyBox applets: `timeout`, `nohup`, `setsid`, `paste`, `pkill`, `fuser`, `lsof`, `watch` (round 8; `flock` was on, no `bc` in 1.27) — the launcher's
      scripts call `timeout` six times and get a silent failure; `setsid` is only
      on the card. (`pkill -f`, `pgrep`, `ip` are present.)
- [x] `bash` (round 8): the launcher copies its own into `/bin/bash` at every boot.
- [ ] `evtest`, `bl`/`vol` helpers (main-zero40 ships them in `/usr/magicx/bin`;
      ours relies on the card's `bin64/evtest`).
- [ ] `rootfs_data` is 2.9 MB and half used after the first day (`/overlay`,
      ext4, the persistent upper for `/`): every `disable`, every `/etc` write
      lands there. Enlarge it in `sys_partition.fex` or keep `/etc` state on the
      user card.
- [ ] `dosfstools` (`fsck.fat`): every boot logs "Volume was not properly
      unmounted" for SD2; the launcher runs no fsck by policy, but a repair tool
      on the base costs little.
- [ ] Our own SDL2 build (2.26 or 2.30) against the GE8300 EGL blobs and fbdev,
      replacing the borrowed TrimUI Smart Pro `usr/magicx/lib/libSDL2*` (works,
      but it is someone else's binary — ATTRIBUTION.md).
- [x] `libmad` (the borrowed SDL2_mixer needs it; PyUI could not import without it).
- [x] glibc 2.38 / libstdc++ GLIBCXX_3.4.32 userland (Arm GNU 13.3) — the
      PortMaster Godot/FRT and Solarus ceiling (DEP §3, `docs/toolchain.md`).
- [ ] `harbourmaster` device profiles for zero28 and zero40 (PortMaster falls back
      to `device=unknown`: wrong `opengl` capability, wrong aspect on the Zero 40)
      — a launcher/PortMaster deliverable, listed so the base's `/etc/os-release`
      or marker can carry what it needs (DEP §6).
- [ ] Quieter console: the RTW driver and `cfg80211_rtw_get_txpower` chatter on
      the serial console; `loglevel=4` on the kernel cmdline or the driver fix above.

## XU20 V32

- First boot has not happened. Two images failed to come up; the audit could not
  settle why. A UART capture (PB9/PB10) is worth more than another attempt.
- Which physical slot is sdc0 and which is sdc2/sdc3: read `/proc/partitions` on a
  booted unit, then say so in `docs/hardware-notes.md`.
- Identify the radio by SDIO id; `WIFI_ONBOARD_MODULE` in spruce assumes 8189es.
- The stock kernel has no UTF-8 NLS and no exFAT: non-ASCII file names on the user
  card and exFAT cards do not work on this board. A rebuilt kernel is the only fix.
- `DIAG=1` is the default until a unit boots; flip it once real behaviour is measured.
- The PowerVR 1.11 userland is TrimUI's; whether it renders through the Android
  `pvrsrvkm`'s display class is the largest remaining unknown.

## Verify before building more

- Sleep/wake on both boards (`/sys/power/state` mem, rtc0 wake alarm, panel
  relight on some Zero 28 revisions — MinUI's raw-brightness trick).
- USB gadget mass storage through configfs (DEP says enabled; never exercised).
- Headphone jack detection (`audiocodec sunxi Audio Jack`, event1) driving the
  speaker/headphone switch, and the `rc.local` mixer defaults vs the launcher's
  `DAC volume` control.
- The Zero 40 radio's identity (same driver loads; chip id not read yet) and
  whether the Zero 40 has a BT part at all (spec says BT 4.2).
