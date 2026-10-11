# Build host for the userland lanes (scripts/run-userland-lane.sh): the programs a build host needs,
# nothing for the target; the lanes cross-build with a mounted toolchain (docs/flip-set.md). Debian 12, because
# its tar and glibc also run under Rosetta (richese's VM builds this image for development; Ubuntu 26.04's do not).
FROM debian:bookworm@sha256:2c037a04925515fdd6ea85ea14a682d0e79931f5e9f5d07b6dbfc6ba12f9e858
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential cmake meson ninja-build autoconf automake autoconf-archive libtool libtool-bin \
        pkg-config gperf bison flex m4 gawk gettext autopoint intltool texinfo help2man xsltproc \
        python3 python3-jinja2 perl file xz-utils bzip2 zstd lzip patch unzip curl ca-certificates git \
        libexpat1-dev libffi-dev libpugixml-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*
