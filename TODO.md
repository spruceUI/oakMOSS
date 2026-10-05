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
      `VIDEO_SUNXI_VIN` off (MODS, DEP §7; `sdk-patches/tree/020`). LZ4 took effect only in
      round 17, with gzip and zstd beside it (`134`: the rootfs compressor choice had switched
      it off).
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
      has a `pstore` partition; a lockup post-mortem needs the kernel side. A RAM-backed
      log does not survive a reset on these boards: boot0 fills DRAM with a test pattern
      (`0x9c5c9939`/`0x63a366c6`) on every boot, measured 2026-09-29 on a reserved,
      unmapped region the kernel never touched. What survives is RTC general-purpose
      register 5 (the debug patch's mark, saved into the U-Boot env as `bootmark`); a
      panic writer to the `pstore` partition would need an MMC panic-write path.
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

- [x] **Zero 40 panel `RTP40WV101B` (480x800) and `axs15205` touch (twi)** (2026-09-17/18):
      not in the SDK drop, so ported: the panel in `070-*`, the AXS15205 in `080-*`, the
      `lcd0`/twi nodes in `boards/zero40/board.dts`. The board runs our kernel on its
      stock chain (`make-own-kernel-stock.sh`), touch loaded after boot as a module.
- [x] **Zero 40 hybrid: MagicX's modules, not ours** (2026-09-16): its kernel has
      `CONFIG_BUG=n`/`KALLSYMS=n` and a modular netfilter core; our round-8 modules
      never came up under it. `scripts/adapt-zero40-rootfs.sh` swaps in the set
      out of the main-zero40 image (HN "Zero 40 hybrid: whose modules"). Our own
      modules matter again only once our kernel drives the board.
- [x] **Route 1: our kernel on the stock chain** (`make-own-kernel-stock.sh`): both boards run
      spruce on our kernel (2026-09-17; the XU20 with ENCRYPT_OBJ=zero40), with WiFi, and with
      touch since 2026-09-18 (`080-*` as modules, `090-*`; HN "Touch drivers stalled the boot").
- [ ] **Retire the Android-kernel lanes** (`make-hybrid-stock.sh`, `make-hybrid-xu20.sh`, the
      main-zero40 hybrid) now that both boards show the UI on our kernel.
- [ ] **Touch reset with the IRQ installed**: the Hynitron driver's `hyn_resume` and its
      I2C-error recovery still pulse reset after requesting the IRQ, the pattern that froze the
      XU20 at probe. Real suspend is in use since 2026-09-28: the XU20 resumed with touch
      working after RTC and power-key sleeps (2026-09-29/30), so `hyn_resume` has held up; the
      I2C-error recovery path is still unexercised.
- [x] **Suspend-to-RAM resumes on all three boards** (was: never resumes, XU20 2026-09-18).
      Two causes, both in Linux: (1) the XU20's asynchronous device suspend never finished
      (stock chain, 2026-09-28) - spruce suspends its devices one at a time there
      (`MAGICX_PM_ASYNC=0`); (2) on the SDK chain the display's suspend cut the panel rail,
      the XU20's touch controller on twi1 went down with it, and the I2C driver's bus-error
      handling fired its interrupt for ever, a hard lockup on the way into sleep
      (2026-09-29) - `sdk-patches/tree/130-*`. Verified on all three boards by RTC-woken and
      power-key sleeps of about a minute (2026-09-29/30); `docs/hardware-notes.md`, "Sleep
      on the SDK chain".
- [ ] **Backlight polarity**: 0 and 1 have each been read as inverted on the XU20/Zero 40
      (HN "Backlight polarity"); spruce mirrors the level on those two boards meanwhile.
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
- [x] **Bluetooth chip** (settled 2026-10-04): the Zero 28's radio is a Realtek
      RTL8189ES-class part (WiFi only), and so is the XU20's; the Zero 40's is an XR829
      (SDIO 0x0a9e:0x2282, WiFi + UART BT on `/dev/ttyS1`), although MagicX's stock Zero 40
      rootfs activates an AIC `hciattach`. spruce brings it up the way the base's
      `bt_init.sh_xr829` does, with our `fw_xr829_bt.bin` and bluez; headset audio through
      bluez-alsa 4.0.0 (MODS, round 16) was tested on 2026-10-04.
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

- [ ] **Zero 40: the boot picture blanks when the GPU driver loads (~4.2 s).** On every Zero 40
      boot on the SDK chain (charger or battery), U-Boot's picture goes dark as `pvrsrvkm`'s
      display class (`dc_sunxi`) calls `sunxi_fb_open()`, which re-runs the panel's enable
      (power sequence + layer config) when the LCD device reports not enabled, although the
      kernel took the display over smoothly ("smooth display screen:0 type:1 mode:4"); the
      purple power LED lights at the same moment. The picture returns only on an unblank.
      Today `/etc/init.d/chargeframe` (charger boots) unblanks and draws at ~5.2 s, leaving a
      1-2 s gap; the Zero 28 and XU20 (rotated, a G2D copy on screen) show none. Next: log
      `is_enabled()` in `sunxi_fb_open` and the return of `disp_lcd_sw_enable` on a Zero 40
      boot, then mark the smoothly taken-over LCD enabled (or skip the enable there).
      Trace tool: `touch /mnt/UDISK/charge-debug` (charge-screen display trace).

- [ ] **Zero 40: suspend waits ~4 s for an SDIO rescan of the empty WiFi slot.** Real sleep
      unloads `xradio_wlan` (loaded and associated it refuses the suspend); the MMC core then
      rescans `sdc1` for a card - `cmd 5` fails four times at 400/300/200/100 kHz, about a second
      each - and "Freezing remaining freezable tasks" waits for that work (4.126 s, 2026-09-29),
      so the board goes dark ~4 s after the power key. Options: keep the SDIO host from
      rescanning while the module is out (unbind it, or mark the slot non-removable), or stop
      the radio without unloading the module.

## Rootfs overlay: services and files

- [ ] **A version stamp spruce can read** (next bundle, with spruce's side). Write the image's
      version at build time where the launcher can read it - `OS_NAME=oakMOSS` and
      `OS_VERSION=<git describe>` in `/etc/os-release`, and/or `/usr/magicx/version` - so
      spruce can show it on About and offer an update when the base is older than its
      target (dArkMoss's `OS_VERSION` + `TARGET_DARKMOSS_VERSION`, fail-closed: no stamp
      or an unparseable one counts as older). `BUILD-INFO.txt` already carries the string;
      the image does not.
- [ ] **Optionally stamp the platform too** (`SPRUCE_PLATFORM=Zero40` etc., as dArkMoss
      does), so a new board needs no spruce detection change; spruce keeps the
      `/usr/magicx/device` mapping as the fallback.

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

- Boots and runs spruceOS on the SDK chain (`scripts/build.sh image xu20`), with panel,
  rotation, touch, pad, WiFi, charge mode and real sleep verified on a unit (2026-09-28..30).
  The system card is `/dev/mmcblk0`, the user card `/dev/mmcblk1p1`.
- The radio is a Realtek 8189es, as spruce assumes.
- The Android-kernel lanes (`make-hybrid-xu20.sh`, `make-own-kernel-stock.sh` on the stock
  chain) are superseded; `DIAG` still defaults to 1 in those scripts. The stock kernel's
  limits (no UTF-8 NLS, no exFAT) do not apply to our kernel's NLS, and exFAT is missing
  from both.

- [ ] **The RTP36HD029A panel variant** (analysis 2026-09-28, nothing built). The stock XU20
      U-Boot and its Android kernel (`boot.fex`) both carry an `RTP36HD029A` driver beside
      `RTP32HD016A`; the stock tree names only `RTP32HD016A` in `lcd0` and has no `lcd0_0..9`
      alternates, although that U-Boot reads `/soc/lcd0_0..9`. So another XU20 revision (by the
      name a 3.6" panel) ships a firmware whose tree selects it; an XU20 with that panel would be
      dark on our image (U-Boot and kernel). Needed: (1) that revision's stock firmware - its
      `lcd0` timings (x/y, dclk, porches, lanes) and touch node exist only there; (2) the
      driver's open/close flow and DSI init table, recovered from the stock kernel's
      `RTP36HD029A` code the way `070-*` was (disassembly, call for call), and the same in
      U-Boot (`103-*`); (3) selection: a separate board (`boards/xu20-v36`) if the revisions are
      told apart by model, or the SDK's `lcd0_N` compatible-panel probe (panel ID read over DSI)
      if one image must serve both - which the stock U-Boot supports but its tree does not use.

## Verify before building more

- ~~Sleep/wake~~: done on all three boards (2026-09-29/30; see the kernel section). Panel
  relight on other Zero 28 revisions (MinUI's raw-brightness trick) is still unchecked.
- USB gadget mass storage through configfs (DEP says enabled; never exercised).
- Headphone jack detection (`audiocodec sunxi Audio Jack`, event1) driving the
  speaker/headphone switch, and the `rc.local` mixer defaults vs the launcher's
  `DAC volume` control.
- The Zero 40 radio's identity (same driver loads; chip id not read yet) and
  whether the Zero 40 has a BT part at all (spec says BT 4.2).
