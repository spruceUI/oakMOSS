#!/bin/bash
# Arm GNU toolchain wrapper. The SDK's own prebuilt toolchain
# ships a sysroot pre-populated with package headers/libs, so many Tina packages compile
# without passing CPPFLAGS/LDFLAGS. Replicate that by appending the OpenWrt staging paths
# (lowest priority: -idirafter, trailing -L) whenever STAGING_DIR is set.
me=$(basename "$0"); here=$(dirname "$(readlink -f "$0")"); real="$here/../bin/$me"
extra=()
if [ -n "$STAGING_DIR" ]; then
  case "$me" in
    *-gcc|*-g++|*-c++|*-cpp)
      extra=(-idirafter "$STAGING_DIR/usr/include" -idirafter "$STAGING_DIR/include" -idirafter "$STAGING_DIR/usr/include/libxml2")
      compile_only=0; for a in "$@"; do case "$a" in -c|-S|-E|-M|-MM) compile_only=1;; esac; done
      [ $compile_only = 1 ] || extra+=(-L"$STAGING_DIR/usr/lib" -L"$STAGING_DIR/lib" -Wl,-rpath-link,"$STAGING_DIR/usr/lib:$STAGING_DIR/lib") ;;
    *-ld|*-ld.bfd)
      extra=(-L"$STAGING_DIR/usr/lib" -L"$STAGING_DIR/lib" -rpath-link "$STAGING_DIR/usr/lib:$STAGING_DIR/lib") ;;
  esac
fi
exec "$real" "$@" "${extra[@]}"
