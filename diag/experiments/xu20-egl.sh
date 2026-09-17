#!/bin/sh
# Stock-chain EGL experiment (2026-09-16): on the XU20 and on the Zero 40's
# Android chain PyUI dies with "Could not initialize EGL" under the vendor's
# 1.11 pvrsrvkm (a DRM-registered build) with TrimUI's 1.11 userland. Record
# what the GPU stack looks like and what eglInitialize says, with the PowerVR
# userland's own stderr, into the boot log. Runs only on those boards, only
# when installed (EXPERIMENTS="xu20-egl"). This base's BusyBox timeout takes
# `-t N`; the bare form ran nothing on the first try. The first real run
# stopped the device before blue: the test runs fenced, and only after the
# hand-off has painted blue and copied the log to the user card.
case "$(cat /usr/magicx/device 2>/dev/null)" in xu20|zero40) ;; *) exit 0 ;; esac
LOG=${LOG:-/mnt/UDISK/spruce-base-boot.log}
{
    echo "--- egl experiment (xu20-egl)"
    echo "dev: $(ls /dev/dri 2>&1 | tr '\n' ' ') $(ls /dev/pvr* /dev/graphics 2>&1 | tr '\n' ' ')"
    echo "proc/pvr: $(ls /proc/pvr 2>&1 | tr '\n' ' ')"; cat /proc/pvr/version 2>&1
    echo "sysfs drm: $(ls /sys/class/drm 2>&1 | tr '\n' ' ')"
    echo "powervr.ini: $(cat /etc/powervr.ini 2>&1 | tr '\n' ' ')"
    echo "pvr libs: $(ls -la /usr/lib/libEGL.so* /usr/lib/libsrv_um.so /usr/lib/libpvrNULL_WSEGL.so /usr/lib/libGLESv2.so* 2>&1 | awk '{print $5, $9, $10, $11}' | tr '\n' ';')"
    echo "dmesg pvr: $(dmesg | grep -iE 'pvr|rgx|drm' | tail -8 | tr '\n' ';')"
    for lib in libEGL.so.1 libEGL.so; do
        echo "egltest $lib:"; LD_LIBRARY_PATH=/usr/lib:/lib timeout -t 20 /usr/magicx/diag/egltest "$lib" 2>&1; echo "rc=$?"
    done
    echo "with the base's launcher environment:"; LD_LIBRARY_PATH=/usr/magicx/lib:/usr/lib:/lib timeout -t 20 /usr/magicx/diag/egltest libEGL.so.1 2>&1; echo "rc=$?"
    echo "dev/dri perms: $(ls -la /dev/dri 2>&1 | tr '\n' ';')"; echo "pvr_sync: $(ls -la /dev/pvr_sync 2>&1)"
    echo "dmesg after: $(dmesg | tail -6 | tr '\n' ';')"
} >> "$LOG" 2>&1
