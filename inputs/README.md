# inputs/

Everything the build consumes but does not carry in git. `scripts/fetch-inputs.sh`
fills this directory with what is publicly available and reports anything else it
needs. All hashes are pinned in `scripts/lib.sh`; the scripts refuse a file that
does not match.

| file | source | check |
|---|---|---|
| `arm-gnu-toolchain-13.3.rel1-x86_64-aarch64-none-linux-gnu.tar.xz` (~120 MB) | developer.arm.com (fetched) | sha256 `322f0b4482fc0d9fa0bb468134841f08d8c554c54ff5aa29a13a7a24bf7e1eb5` (Arm's published value) |
| `ncurses-6.2.tar.gz` | ftp.gnu.org (fetched) | sha256 `30306e0c76e0f9f1f0de987cf1c82a5c21e1ce6568b9227f7da5b71cbea86c9d` |
| `main-zero40-20260202-1.img.zip` (27 MB) | github.com/dedicated-os/main-zero40 release v20260202-1 (fetched); Zero 40 hybrid only | zip sha256 `c34d24695b95188061d072e936b6bd6dbae237a78c39cc31bfff05e21f65e81f`, image inside sha256 `0790880fdc08bbbcb5bb4dcbe39ef7c436a7013994031aead31f95af906babe6` |
| `XU20_V32-user.zip` (789 MB) | github.com/Magicx-Breeze/XU20_V32 release `Developers`, asset `user.zip` (fetched); XU20 only. `scripts/unpack-xu20-stock.sh` turns it into `inputs/xu20-stock/` | zip sha256 `9b0c414d3f9f065a6c52e699301807103d22c4eb106e6825cdd3bfa167c85dd0`, `user.img` inside sha256 `99a3ccdab8eecbb7cfbb53e8736f4427a33bf8ebaeb33a6fab8cb1ac9b50f19d` |
| `Zero40_V1-adb.img.xz` (820 MB) | github.com/Magicx-Breeze/Zero40 release `Zero40_V1`, asset `adb.img.xz` (fetched); Zero 40 stock lane only. `scripts/unpack-zero40-stock.sh` decompresses it (8 GB) into `inputs/zero40-stock/` and cuts the items out of its GPT | xz sha256 `5ee40ba1449e47ddf545b289c5963545a1f7162078b396e3236ed876a910e5c5`, raw sha256 `5219dc6b9251a351c937427726185dc3798819b0b14d8d08e68fe505f6209646` |
| `gcc-7.5.0.tar.xz`, `binutils-2.28.tar.gz` | ftp.gnu.org (`fetch-inputs.sh --with-phase2`); only for the fallback from-source toolchain | sha256 `b81946e7f01f90528a1f7352ab08cc602b9ccc05d4e44da4bd501c5a189ee661`, `cd717966fc761d840d451dbd58d44e1e5b92949d2073d75b73fccb476d772fcf` |

Not needed in `inputs/`: OpenixCard is cloned and built into `tools/` by
`scripts/build-openixcard.sh`; awutils (`scripts/build-awutils.sh`, with
`tools-patches/awutils-imagewty-0x415.patch`) and lpunpack
(`scripts/unpack-xu20-stock.sh`, `scripts/unpack-zero40-stock.sh`) likewise, all at commits pinned in `lib.sh`.

Anything not listed above is not redistributable and is not obtained by this
repository. `scripts/fetch-inputs.sh` reads a location for each from the
environment if you set one; any HTTPS URL curl can fetch works.
