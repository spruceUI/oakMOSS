# Status and known gaps

oakMOSS is bench-tested on one of each board, a Zero 28, a Zero 40 and an XU20 V32, with
spruceOS on the user card (September 2026). The releases on GitHub are betas. Treat anything
below that is not marked as tested as untested.

## The latest release, `main` and spruceOS

The latest release, v0.3.0-beta.1 (2026-09-25), is older than this work on `main`:

- charge mode, and the SDK chain on the Zero 40 and XU20 (the release boots those two
  through their stock boot0 and U-Boot);
- the kernel fixes for real sleep: the I2C bus-error fix (`sdk-patches/tree/130-*`, XU20)
  and the Zero 40's touch after the wake (`080`);
- one key code per press (2026-09-26).

Images built from `main` since 2026-09-26 need a spruceOS that reads the pad's key bitmap
(`docs/DEPENDENCIES.md`, section 9). With an older spruceOS the d-pad, volume and MENU come
out one slot off, and A does not confirm. spruceOS also decides whether a board really
sleeps: older builds turn the screen off and pause the game instead. As of 2026-09-30 these
spruceOS changes are not in a spruceOS nightly yet.

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
  "Diagnostic and debug images").

## Known gaps

- The fixes for newer board revisions in main-zero40 v20260202-1 are not in our inputs.
- The Zero 40 blanks its boot picture for 1-2 s when the GPU driver loads (`TODO.md`).
- The Zero 40 takes ~4 s longer to go to sleep: after its radio module is unloaded, the
  kernel rescans the empty WiFi slot (`TODO.md`).
- Kernel 4.9 has no exFAT: large user cards must be formatted FAT32.
- BusyBox 1.27 has no `bc`.
- The XR829's crystal is assumed to be 26 MHz.
- An XU20 revision with the RTP36HD029A panel would be dark on this image (`TODO.md`).

The spruceOS side (platform files, PyUI device classes, the card builder) lives in
[spruceOS](https://github.com/spruceUI/spruceOS), not here.
