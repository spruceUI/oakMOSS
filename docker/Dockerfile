# Build environment for the Allwinner Tina Linux v1.0 SDK (A133, "lichee").
# The SDK is a 2019 OpenWrt derivative: it wants python2, gawk, GCC <= 9 for
# its host tools and 32-bit libs for Allwinner's prebuilt pack tools, none of
# which a Debian 13 host offers. Ubuntu 18.04 matches the SDK's era.
#
# Build:  docker build -t oakmoss-tina-build:ubuntu18 --build-arg UID=$(id -u) --build-arg GID=$(id -g) docker
#         (scripts/run-in-sdk.sh does this on first use with the caller's UID/GID)
# Run:    scripts/run-in-sdk.sh (mounts sdk/lichee at /home/builder/lichee)
FROM ubuntu:18.04
ARG UID=1000
ARG GID=1000
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8 TZ=UTC
# Bionic left the main mirror after its standard support ended; fall back to old-releases when needed.
RUN dpkg --add-architecture i386 \
    && { apt-get update || { sed -i 's|http://[a-z.]*archive.ubuntu.com/ubuntu|http://old-releases.ubuntu.com/ubuntu|; s|http://security.ubuntu.com/ubuntu|http://old-releases.ubuntu.com/ubuntu|' /etc/apt/sources.list && apt-get update; }; } \
    && apt-get install -y --no-install-recommends \
    build-essential gcc-multilib g++-multilib git subversion mercurial bzr cvs \
    libncurses5-dev libncursesw5-dev zlib1g-dev libssl-dev libelf-dev libglib2.0-dev \
    gawk flex bison bc quilt patch gettext texinfo libtool autoconf automake pkg-config \
    python python-dev python3 python3-dev python3-setuptools \
    xsltproc libxml-parser-perl unzip zip xz-utils bzip2 lzop cpio rsync wget curl file \
    u-boot-tools device-tree-compiler cmake ninja-build ccache swig gperf \
    lib32z1 lib32z1-dev lib32stdc++6 libstdc++6 libc6-i386 lib32ncurses5 libncurses5 \
    locales vim-tiny time tree less openssh-client sudo ca-certificates busybox dos2unix \
    && rm -rf /var/lib/apt/lists/* \
    && locale-gen en_US.UTF-8
RUN groupadd -g ${GID} builder && useradd -m -u ${UID} -g ${GID} -s /bin/bash builder \
    && echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builder
USER builder
WORKDIR /home/builder
ENV FORCE_UNSAFE_CONFIGURE=1 USE_CCACHE=1 CCACHE_DIR=/home/builder/.ccache
CMD ["/bin/bash"]
