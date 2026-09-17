#!/usr/bin/env python3
"""Decode the input-device capability bitmaps in a diag base-boot.log.

For each /dev/input/eventN the snapshot records `key=` and `abs=` bitmaps
(sysfs capabilities: space-separated hex words, most significant first).
Prints the key codes each node declares, and for the MagicX pad derives
which physical button sits on which code from MinUI's zero28 joystick
indices under SDL's evdev enumeration order (BTN_JOYSTICK=0x120.. first
in ascending code order, then 0..0x11f ascending).

usage: decode-input-bitmap.py <base-boot.log>
"""
import re
import sys

KEYNAMES = {
    1: "KEY_ESC", 28: "KEY_ENTER", 102: "KEY_HOME", 103: "KEY_UP", 105: "KEY_LEFT", 106: "KEY_RIGHT",
    108: "KEY_DOWN", 114: "KEY_VOLUMEDOWN", 115: "KEY_VOLUMEUP", 116: "KEY_POWER", 139: "KEY_MENU",
    158: "KEY_BACK", 164: "KEY_PLAYPAUSE", 172: "KEY_HOMEPAGE", 272: "BTN_LEFT", 273: "BTN_RIGHT",
    304: "BTN_SOUTH/A", 305: "BTN_EAST/B", 306: "BTN_C", 307: "BTN_NORTH/X", 308: "BTN_WEST/Y",
    309: "BTN_Z", 310: "BTN_TL", 311: "BTN_TR", 312: "BTN_TL2", 313: "BTN_TR2", 314: "BTN_SELECT",
    315: "BTN_START", 316: "BTN_MODE", 317: "BTN_THUMBL", 318: "BTN_THUMBR",
    544: "BTN_DPAD_UP", 545: "BTN_DPAD_DOWN", 546: "BTN_DPAD_LEFT", 547: "BTN_DPAD_RIGHT",
}
ABSNAMES = {0: "ABS_X", 1: "ABS_Y", 2: "ABS_Z", 3: "ABS_RX", 4: "ABS_RY", 5: "ABS_RZ",
            16: "ABS_HAT0X", 17: "ABS_HAT0Y", 53: "ABS_MT_POSITION_X", 54: "ABS_MT_POSITION_Y", 57: "ABS_MT_TRACKING_ID"}
# MinUI workspace/zero28/platform/platform.h joystick indices (SDL joystick button numbers).
MINUI_JOY = {0: "A", 1: "B", 2: "X", 3: "Y", 4: "L1", 5: "R1", 6: "L2", 7: "R2", 8: "SELECT", 9: "START",
             10: "L3", 11: "R3", 13: "UP", 14: "LEFT", 15: "RIGHT", 16: "DOWN", 17: "MINUS", 18: "PLUS", 19: "MENU"}


def bits(hexwords):
    words = [int(w, 16) for w in hexwords.split()]
    words.reverse()  # sysfs prints the most significant word first
    out = []
    for i, w in enumerate(words):
        for b in range(64):
            if w >> b & 1:
                out.append(i * 64 + b)
    return out


def sdl_button_order(codes):
    hi = sorted(c for c in codes if 0x120 <= c < 0x300)
    lo = sorted(c for c in codes if c < 0x120)
    return hi + lo


def main(path):
    text = open(path, errors="replace").read()
    seen = {}
    for m in re.finditer(r"^\[(/sys/class/input/event\d+)\] name=(.*?) key=(.*?) abs=(.*?)$", text, re.M):
        seen[m.group(1)] = (m.group(2).strip(), m.group(3).strip(), m.group(4).strip())
    if not seen:
        sys.exit("no per-node capability lines in %s (needs the 1240/1328 diag images or later)" % path)
    for node, (name, key, absw) in sorted(seen.items()):
        keys = bits(key) if key else []
        axes = bits(absw) if absw else []
        print("%s  %s" % (node, name))
        if keys:
            print("   keys: " + " ".join("%d(%s)" % (c, KEYNAMES.get(c, "?")) for c in keys))
        if axes:
            print("   abs:  " + " ".join("%d(%s)" % (c, ABSNAMES.get(c, "?")) for c in axes))
        if "magicx" in name.lower() and keys:
            order = sdl_button_order(keys)
            print("   SDL joystick order -> MinUI zero28 labels:")
            for idx, code in enumerate(order):
                label = MINUI_JOY.get(idx, "-")
                print("      idx %2d  code %3d (%-14s) = %s" % (idx, code, KEYNAMES.get(code, "?"), label))
    print()


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "base-boot.log")
