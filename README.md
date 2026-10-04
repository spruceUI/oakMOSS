# oakMOSS

oakMOSS is a small base operating system for three Allwinner A133P handhelds: the
**MagicX Mini Zero 28**, the **MagicX Zero 40** and the **XU RETRO / MagicX XU20 V32**. It
lives on the internal card (SD1) and has one job: start the board, mount the user card in
the second slot, and hand off to the launcher on it, normally
[spruceOS](https://github.com/spruceUI/spruceOS). It is built from the vendor's Tina Linux
SDK and follows the shape of Shaun Inman's
[Moss-zero28](https://github.com/shauninman/Moss-zero28) and
[main-zero40](https://github.com/dedicated-os/main-zero40) (see [ATTRIBUTION.md](ATTRIBUTION.md)).

## Which image

One image per board, `oakmoss-<board>-<stamp>-sd1.img`, written to the internal card.
Releases are on the [releases page](https://github.com/spruceUI/oakMOSS/releases).

> **Flashing replaces the firmware the board starts from.** Back up the stock internal card
> first; it is the only way back. Write the image raw to the whole card, and never let a
> partition tool, or Windows, touch the card afterwards. Read
> [docs/using.md](docs/using.md) before you start.

## Where things stand

All three boards boot spruceOS with their panel, pad, WiFi and audio, and touch on the two
boards that have it. Charge mode works when a board is plugged in while off, and the boards
really sleep and wake. From v0.4.1-beta.1 on, the images pair with spruceOS v4.5.0 or a
newer nightly. It is bench-tested on one of each board; the releases are betas. Details
and known gaps: [docs/status.md](docs/status.md).

## Documentation

| | |
|---|---|
| [docs/using.md](docs/using.md) | flashing, and what the board does on boot, on the charger and in sleep |
| [docs/status.md](docs/status.md) | what has been tested on which board, and the known gaps |
| [docs/building.md](docs/building.md) | building the images yourself, and the repository layout |
| [docs/hardware-notes.md](docs/hardware-notes.md) | what the boards turned out to be, and how problems were found |
| [docs/sdk-mods.md](docs/sdk-mods.md) | every change made to the vendor SDK, with the reason |
| [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md) | what spruceOS and PortMaster need from the base |
| [docs/toolchain.md](docs/toolchain.md) | why the userland is built with a newer toolchain than Moss's |
| [TODO.md](TODO.md) | open work |

oakMOSS is an independent community project. It is not affiliated with, endorsed by or
supported by MagicX, XU RETRO, TrimUI, Allwinner or Imagination Technologies, and it is not
Moss or Dedicated OS. Device, product and company names only say which hardware and which
sources are involved. Flashing a device is at your own risk; see [LICENSE](LICENSE).

License: [LICENSE](LICENSE) for oakMOSS's own files; third-party terms in
[ATTRIBUTION.md](ATTRIBUTION.md).
