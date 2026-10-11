# The flip set: spruce/flip/lib, built for the oakMOSS image

spruce puts `spruce/flip/lib` (libraries collected for the Miyoo Flip) on the MagicX library paths. Those are
other distributions' builds, and on MagicX some of them fail: Westonpack picked up the Flip's SDL2, ScummVM's
libcrypt and libssl clashed with the image's, `libvorbisidec.so.1` is an armhf file, `libwayland-client.so.0`
needs a `libffi.so.8` that nothing provides, and `libavformat.so.58` needs OpenSSL 3. The flip set is the
same libraries built for this image, so a MagicX image can carry its own and spruce can stop borrowing.

Scope (user, 2026-10-11): all 129 libraries of `spruce/flip/lib`, every one except the Flip's SDL2, whose
place the vendor's PowerVR SDL2 in `/usr/magicx/lib` already takes.

## Building it

```
PORTS_SET=flip PORTS_TOOLCHAIN=armgnu103 scripts/run-userland-lane.sh     # -> builds/<stamp>-ports-userland-flipset/
FLIPSET=builds/<stamp>-ports-userland-flipset scripts/build.sh all zero28 zero40 xu20
```

The set is the userland lane (`scripts/build-ports-userland.sh`) with a second package list. It builds with the
Arm GNU 10.3 toolchain (glibc 2.33), whose output loads on the image's glibc 2.38, and it runs inside
`docker/userland-lane` (Debian 12 with cmake, meson, autotools, bison, gperf...), so build hosts need only
Docker. `scripts/fetch-userland.sh` downloads the sources named in `inputs/userland/urls.txt` and checks them
against `inputs/userland/SHA256SUMS`.

`build.sh` copies the set into each image as `/usr/lib/flipset` and writes `/usr/magicx/flipset`: its first
line is that directory, then the set's `SHA256SUMS` hash and the oakMOSS version it was built from. After the
rootfs is assembled, build.sh fails if any file of the set links a library that is neither in the set nor in
the image's `/lib`, `/usr/lib` or `/usr/magicx/lib`.

**spruce's side:** on a MagicX image with `/usr/magicx/flipset`, spruce puts the named directory where it
puts `spruce/flip/lib` today. Images without the marker keep today's paths.

## What ships

| Group | Libraries | Notes |
|---|---|---|
| Lane recipes reused | 23: ffmpeg's five, boost_filesystem 1.71, jpeg8, lzma, modplug, lame, mpg123, ogg, openal, png16, the PulseAudio 13.99 client trio, theoradec, vorbis, vorbisfile, vpx.so.8, webp.so.7, zstd | ffmpeg and libjpeg have flip-only variants (`ffmpegflip`, `libjpegturbo8flip`) |
| New recipes | 57: X11/xcb (15), Wayland and xkbcommon (6), codecs (17), ICU 63, cairo, pixman, tiff, fribidi, giflib, liblcf, lz4, libzip, SDL2_gfx and SDL2_net, speech-dispatcher's client, Python 3.10, Tcl/Tk 8.6 | |
| PulseAudio extras | 4: libapparmor, libasyncns, libsystemd, libwrap | the Flip's PulseAudio linked them; this set's PulseAudio does not, they ship for completeness |
| The ScummVM curl chain | 30: MIT Kerberos 1.17, Heimdal 7.7, OpenLDAP 2.4, Cyrus SASL, nettle 3.5 and 3.7, p11-kit, libtasn1, libidn2, libunistring, libpsl, nghttp2, brotli | what the libcurl ScummVM carries links |
| Needed by the above, missing from the image | libbsd, libfontconfig, libtheoraenc, libvorbisenc, libcom_err | |
| Already in the image (not shipped) | 15: SDL2_image/mixer/ttf, atomic, bz2, crypt, ffi.so.7, gcrypt, gmp, gnutls 3.6.5, gpg-error, mad, nsl, pcre, ssl 1.1 | nothing on the card needs more of GnuTLS than 3.6.5 |

The Flip's other file names for libwebp (`libwebp.so.7.5.0`, `libwebp.so.1.0.3`, `libwebpdemux.so.2.6.0`) are links.

## Versions

A soname or a C++ ABI pins most versions:

- ICU 63 (its symbols carry `_63`), liblcf 0.8 (the EasyRPG core's 46 `lcf::` imports are all among its exports),
  boost 1.71, libvpx 1.6.1 / 1.8.2 / 1.11.0 / 1.13.1 for `.so.4` / `.6` / `.7` / `.8`, libunistring 0.9.10
  (`.so.2`), libzip 1.5.2 (`.so.5`, which the PixelReader links), nettle 3.5.1 and 3.7.3, OpenLDAP 2.4.59.
- Python 3.10.19 and Tcl/Tk 8.6.14, the Flip's versions. Its `python3.10` links Python statically and never
  loads `libpython3.10.so.1.0`; the card's `python3.10` module tree matches this library.
- libjpeg-turbo 2.1.5 in the jpeg8 ABI: its `LIBJPEGTURBO_8.0` symbol versions are what the Flip's copy has.
- MIT Kerberos 1.17 (the Flip's `krb5-1.17-final`), libopenmpt 0.4.11, libtiff 4.2.0, fribidi 1.0.8, libpsl 0.21.0.

**Floors.** Where the image already has a library, the set is built against the image's version of it, so no
file imports a symbol the image lacks: FreeType 2.6.1, expat 2.1.0, SQLite 3.12.2, SDL2 2.26.1 (the vendor's),
zlib 1.2.8 (the lane's floor; the image has 1.3.1). These are build-only packages and do not ship.

## Where it differs from the Flip's copies

- `libvorbisidec.so.1` is an aarch64 build (the Flip's is armhf, which no 64-bit program can load).
- `libwayland-client.so.0` links the image's `libffi.so.7` (the Flip's wants `libffi.so.8`).
- ffmpeg is the LGPL configuration (no postproc, filters or devices) with TLS through the image's OpenSSL 1.1.
- PulseAudio is the lane's client build: no X11, D-Bus, systemd, tcp_wrappers or AppArmor behind it.
- `libldap_r` has no Debian GSSAPI patch; SASL mechanisms (none in the set) would supply that.
- `libtk8.6.so` links the shipped X11 libraries instead of carrying them inside.
- `libcom_err.so.2` is e2fsprogs', as Ubuntu's Kerberos builds link.

## Licences

The set is mostly LGPL, MIT and BSD; a52dec, libmpeg2 and faad2 are GPL-2.0, ICU is under the Unicode licence,
Python under the PSF licence, OpenLDAP under its own. Each needs an `ATTRIBUTION.md` entry, and the sources stay
in `inputs/userland`, before any image carrying the set is released.
