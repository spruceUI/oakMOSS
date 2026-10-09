# Status and known gaps

oakMOSS is bench-tested on one of each board, a Zero 28, a Zero 40 and an XU20 V32, with
spruceOS on the user card (September 2026). The releases on GitHub are betas. Treat anything
below that is not marked as tested as untested.

## Releases and spruceOS

v0.5.0-beta.1 (2026-10-09) is the first release with two system slots, so it is written once
and then updated in place (`docs/updates.md`). It adds spruceOS on the system card (a
`SPRUCEOS` partition made at the first boot; SD2's spruce wins when both cards carry one,
`docs/cards.md`), the no-frontend screens, debug mode (`docs/debugging.md`), the Zero 40's
boot picture kept until the menu, the case LED's blue light off while running, shutdown
scripts in order, and BusyBox `tr` character classes. Tested on all three boards. It pairs
with spruceOS v4.5.0 or a newer nightly.

v0.4.2-beta.1 (2026-10-04) lets the kernel mount squashfs images compressed with gzip, LZ4 and
zstd as well as XZ and LZO: most PortMaster runtimes are gzip, and the 32-bit Godot 4.5 runtime
is zstd. Until then the kernel mounted only XZ and LZO, whatever its config said (`134`,
`docs/sdk-mods.md`, Round 17). Tested on all three boards. It pairs with spruceOS v4.5.0 or a
newer nightly, as v0.4.1-beta.1 does.

v0.4.1-beta.1 (2026-10-04) fixes touch for programs that read the touchscreen themselves:
the kernel drops repeated multitouch values again, so a held touch stays held
(`sdk-patches/tree/131-*`), and udev marks the touch controllers as touchscreens
(`overlay/etc/udev/rules.d/60-oakmoss-touchscreen.rules`). Tested in DraStic (trngaje's
build) and DSperate on the Zero 40 and XU20. It also replaces the SDK's 2018 bluez-alsa with
4.0.0 for Bluetooth audio, with later upstream fixes backported (`133`, `docs/sdk-mods.md`,
Round 16), tested with a headset on the Zero 40. It pairs with spruceOS v4.5.0 or a newer
nightly.

v0.4.0-beta.1 (2026-09-30) is the first release with charge mode, the SDK chain on the Zero
40 and XU20, the kernel fixes for real sleep (the I2C bus-error fix
`sdk-patches/tree/130-*` for the XU20, the Zero 40's touch after the wake in `080`) and one
key code per press. v0.3.0-beta.1 and older boot the Zero 40 and XU20 through their stock
boot0 and U-Boot, have no charge mode, and send a second code for some keys.

Images from v0.4.0-beta.1 on, and builds from `main` since 2026-09-26, need spruceOS newer
than v4.4.3-20260930 (spruceOS PR #1735). It reads the pad's key bitmap
(`docs/DEPENDENCIES.md`, section 9) and turns real sleep on for these boards. With an older
spruceOS the d-pad, volume and MENU come out one slot off, A does not confirm, and sleep
only turns the screen off and pauses the game.

## What runs

All three boards run the SDK chain since 2026-09-28: SDK boot0 and ATF/SCP, our U-Boot with
their panels, our kernel. Before that, the Zero 40 and XU20 ran our kernel behind their stock
boot0 and U-Boot; the launcher, pad, touch, audio and WiFi were first proven that way.

| | Zero 28 | Zero 40 | XU20 V32 |
|---|---|---|---|
| panel (our kernel and U-Boot) | yes | yes | yes |
| touch | - (none) | yes (AXS15205) | yes (Hynitron) |
| pad, one code per press | yes | yes | yes, plus a Home key |
| WiFi | Realtek 8189es | XR829 | Realtek 8189es |
| charge mode | yes | yes | yes |
| real sleep (power key and RTC) | yes | yes | yes |
| Bluetooth audio (bluez-alsa 4.0.0) | - (no Bluetooth) | yes (XR829 over UART; headset tested) | - (no Bluetooth) |
| squashfs images (loop mounts) | XZ, LZO, LZ4, gzip, zstd | XZ, LZO, LZ4, gzip, zstd | XZ, LZO, LZ4, gzip, zstd |

Touch loads as a module once the board has settled: built into the kernel, its probe
stalled boots at the logo (`docs/hardware-notes.md`, "Touch drivers stalled the boot").
Sleep needed two fixes, both described in `docs/hardware-notes.md` ("Sleep on the SDK
chain").

The panels and touch controllers are in our kernel (`sdk-patches/tree/070-*`, `080-*`), so
the images that borrowed MagicX's Android kernel are no longer needed.

## The vendor boot object

Each board's MagicX kernel includes a prebuilt vendor object that authenticates the board
and restarts the kernel when the check fails. The XU20 runs with the Zero 40's object
(`boards/xu20/board.conf`). How the check works is deliberately not documented here.

## Diagnostics that have worked

- A USB-TTL UART adapter on PB9 (TX) / PB10 (RX), 115200 8N1.
- The diagnostic image's colour ladder (`scripts/make-diag-image.sh`).
- Debug kernels whose marks survive a reset in an RTC register (`docs/building.md`,
  "Diagnostics and debug records").

## Known gaps

- The fixes for newer board revisions in main-zero40 v20260202-1 are not in our inputs.
- The Zero 40 takes ~4 s longer to go to sleep: after its radio module is unloaded, the
  kernel rescans the empty WiFi slot (`TODO.md`).
- Kernel 4.9 has no exFAT: large user cards must be formatted FAT32.
- BusyBox 1.27 has no `bc`.
- The XR829's crystal is assumed to be 26 MHz.
- An XU20 revision with the RTP36HD029A panel would be dark on this image (`TODO.md`).
- Two slots and updates (`docs/updates.md`) and SD1 installs (`docs/cards.md`) are tested on
  the Zero 28 only. U-Boot's fallback to its boot0 and package copies is not tested.
- With spruce on SD1, spruce's `SD_DEV` and its USB storage app's device (`/dev/mmcblk1p1`) name
  SD2, until spruce takes them from the mounts. The power-off then leaves the host to the base's
  final unmount, and USB storage mode exports SD2 (`docs/cards.md`).

The spruceOS side (platform files, PyUI device classes, the card builder) lives in
[spruceOS](https://github.com/spruceUI/spruceOS), not here.
